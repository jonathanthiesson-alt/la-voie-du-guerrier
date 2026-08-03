// ════════════════════════════════════════════════════════════════════════
// bot-army.mjs — worker « armée de bots » (GitHub Actions). Voir docs/BOT_ARMY_PLAN.md
// ════════════════════════════════════════════════════════════════════════
// Déploie des bots (comptes ANONYMES Supabase) qui jouent en ligne comme de
// vrais joueurs, pour tester le online SEUL. Piloté par la table bot_army_control
// (écrite depuis le menu dev) ; écrit un rapport par mode dans bot_army_report.
//
// 🔴 STATUT : v1 À VALIDER EN LIVE. Le matchmaking/soumission de coup est
// reconstruit d'après le protocole d'index.html (matchmaking_queue, game_state,
// online_games) mais N'A PAS pu être testé hors-ligne. À éprouver avec l'auth
// anonyme activée + un vrai match, puis itérer. Aucun impact sur le jeu normal :
// ce worker ne tourne que si la directive est « enabled » ET l'auth anon activée.
//
// Réutilise le pattern du worker d'équilibre : moteur EXTRAIT d'index.html
// (source vivante, zéro dérive). Les bots s'authentifient via @supabase/supabase-js
// (auth anonyme) ; les tâches admin (is_bot, contrôle, rapport, purge des comptes)
// passent par la service_role en REST direct (contourne la RLS).

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createClient } from "@supabase/supabase-js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(join(ROOT, "index.html"), "utf8");

const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const RUN_MINUTES = Math.min(Math.max(+(process.env.BOT_ARMY_MINUTES || 50), 1), 330);
// Clé anon (publique) lue dans index.html — pas besoin de la hardcoder ailleurs.
const ANON_KEY = (html.match(/SUPABASE_ANON_KEY\s*=\s*['"]([^'"]+)['"]/) || [])[1] || "";

// ── Moteur de jeu extrait d'index.html (mêmes fonctions que le worker d'équilibre) ──
const ENGINE_NAMES = [
  "findMaster", "dist", "threatCount", "cloneBS", "applyToClone", "allMoves",
  "labResolveDirs", "labGenericMoves", "labPieceValue", "legalMoves", "execMove",
  "evalPosition", "evalTrainer", "minimaxFn", "minimaxPlay",
];
function extractFn(src, name) {
  const sig = "function " + name + "(";
  const start = src.indexOf(sig);
  if (start < 0) throw new Error("INTROUVABLE: " + name);
  const i = src.indexOf("{", start);
  let depth = 0, inS = false, q = "", inLC = false, inBC = false;
  for (let k = i; k < src.length; k++) {
    const c = src[k], n = src[k + 1];
    if (inLC) { if (c === "\n") inLC = false; continue; }
    if (inBC) { if (c === "*" && n === "/") { inBC = false; k++; } continue; }
    if (inS) { if (c === "\\") { k++; continue; } if (c === q) inS = false; continue; }
    if (c === "/" && n === "/") { inLC = true; k++; continue; }
    if (c === "/" && n === "*") { inBC = true; k++; continue; }
    if (c === '"' || c === "'" || c === "`") { inS = true; q = c; continue; }
    if (c === "{") depth++;
    else if (c === "}") { depth--; if (depth === 0) return src.slice(start, k + 1); }
  }
  throw new Error("ACCOLADES: " + name);
}
function getFormat(src, id) {
  const s = src.indexOf(id + ":{");
  if (s < 0) throw new Error("Format inconnu: " + id);
  const i = src.indexOf("{", s);
  let depth = 0, inS = false, q = "", inLC = false, inBC = false;
  for (let k = i; k < src.length; k++) {
    const c = src[k], n = src[k + 1];
    if (inLC) { if (c === "\n") inLC = false; continue; }
    if (inBC) { if (c === "*" && n === "/") { inBC = false; k++; } continue; }
    if (inS) { if (c === "\\") { k++; continue; } if (c === q) inS = false; continue; }
    if (c === "/" && n === "/") { inLC = true; k++; continue; }
    if (c === "/" && n === "*") { inBC = true; k++; continue; }
    if (c === '"' || c === "'" || c === "`") { inS = true; q = c; continue; }
    if (c === "{") depth++;
    else if (c === "}") { depth--; if (depth === 0) return eval("(" + src.slice(i, k + 1) + ")"); }
  }
  throw new Error("Accolades format " + id);
}
// Construit un moteur pour le format standard et expose botChooseAndApply :
// prend un game_state + une couleur, choisit un coup (minimax prof.2, évalTrainer)
// et renvoie le NOUVEAU game_state + le drapeau de victoire + le tour suivant.
function makeMover(format) {
  const prelude = [
    "var FORMAT=" + JSON.stringify(format) + ";",
    "var VOID_STD=new Set(FORMAT.voids||[]);",
    'function isValid(r,c){return r>=0&&r<(FORMAT.rows||5)&&c>=0&&c<(FORMAT.cols||5)&&!VOID_STD.has(r+","+c);}',
    "var DO=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1}];",
    "var DA=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1},{dr:-1,dc:-1},{dr:-1,dc:1},{dr:1,dc:-1},{dr:1,dc:1}];",
    "var PP={totalCaptures:0,totalPushes:0};",
    "function playSound(){} function haptic(){}",
    "var G={simulating:true,rows:FORMAT.rows||5,cols:FORMAT.cols||5,sumoMode:!!FORMAT.sumo,pieceDefs:(FORMAT.pieces||null),turn:null,lastPush:null,lastMoved:null,lastMovedByColor:{white:null,black:null}};",
    "function isV2mode(){return !!FORMAT.v2;}",
  ].join("\n");
  const body = ENGINE_NAMES.map((n) => extractFn(html, n)).join("\n\n");
  // ⚠ Reconstruit : signatures d'après index.html (scheduleAI/executeDrop).
  // Coups au format {fr,fc,tr,tc,action} ; execMove mute G.board/G.stacks et
  // renvoie `won`. À CONFIRMER contre le comportement réel en live.
  const mover = `
    function botChooseAndApply(stateJson, color, depth){
      var st = JSON.parse(stateJson);
      G.board = st.board; G.stacks = st.stacks || {};
      G.lastMoved = st.lastMoved || null;
      G.lastMovedByColor = st.lastMovedByColor || {white:null,black:null};
      var moves = allMoves(color, G.board, G.stacks, G.lastMoved, G.lastPush, G.lastMovedByColor);
      if(!moves || !moves.length) return JSON.stringify({ noMove:true });
      var mv = null;
      try { mv = minimaxPlay(moves, G.board, G.stacks, G.lastMoved, G.lastPush, depth||2, evalTrainer, color); } catch(e){}
      if(!mv) mv = moves[Math.floor(Math.random()*moves.length)];
      var won = execMove(mv.fr, mv.fc, mv.tr, mv.tc, mv.action);
      return JSON.stringify({
        state:{ board:G.board, stacks:G.stacks, lastMoved:G.lastMoved, lastMovedByColor:G.lastMovedByColor },
        won: !!won, turn: color==='white'?'black':'white'
      });
    }`;
  const factory = new Function(prelude + "\n\n" + body + "\n\n" + mover + "\n\nreturn { botChooseAndApply: botChooseAndApply };");
  return factory();
}

// ── REST admin (service_role → contourne la RLS), comme le worker d'équilibre ──
async function sbAdmin(path, init) {
  const res = await fetch(SUPABASE_URL + "/rest/v1/" + path, {
    ...init,
    headers: { apikey: SERVICE_KEY, Authorization: "Bearer " + SERVICE_KEY, ...(init && init.headers) },
  });
  if (!res.ok) throw new Error((init && init.method || "GET") + " " + path + " " + res.status + " : " + (await res.text()).slice(0, 200));
  return res;
}
async function readControl() {
  const rows = await (await sbAdmin("bot_army_control?id=eq.1&select=*")).json();
  return rows[0] || null;
}
async function writeReport(mode, agg) {
  await sbAdmin("bot_army_report?on_conflict=mode", {
    method: "POST",
    headers: { "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({ mode, ...agg, updated_at: new Date().toISOString() }),
  });
}
// Marque un profil comme bot (service_role), avec un pseudo reconnaissable.
async function flagBotProfile(userId, n) {
  await sbAdmin("profiles?id=eq." + userId, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ is_bot: true, pseudo: "bot_" + String(n).padStart(3, "0") }),
  });
}

// ── Provisionne un bot : client anon + sign-in anonyme + flag is_bot ──
async function provisionBot(n) {
  const client = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: true } });
  const { data, error } = await client.auth.signInAnonymously();
  if (error) throw new Error("signInAnonymously: " + error.message);
  const uid = data.user.id;
  // Le trigger de création de profil peut être asynchrone : petite attente.
  await sleep(400);
  try { await flagBotProfile(uid, n); } catch (e) { console.warn("flagBot", n, e.message); }
  return { n, client, uid };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const otherColor = (c) => (c === "white" ? "black" : "white");

// ── MODE matchmaking : le bot suit le protocole matchmaking_queue d'index.html ──
// (enqueue → poll → le plus petit player_id crée online_games → jouer). ⚠ v1.
async function botMatchmakingLoop(bot, mover, timer, isAliveRef, stats) {
  const c = bot.client;
  while (isAliveRef.alive) {
    try {
      // 1) déjà dans une partie active ?
      const { data: games } = await c.from("online_games").select("*")
        .or(`white_player_id.eq.${bot.uid},black_player_id.eq.${bot.uid}`)
        .eq("status", "active").order("created_at", { ascending: false }).limit(1);
      if (games && games.length && !games[0].arena_match_id) {
        await playGame(bot, mover, games[0], stats);
        continue;
      }
      // 2) s'inscrire dans la queue
      await c.from("matchmaking_queue").delete().eq("player_id", bot.uid);
      await c.from("matchmaking_queue").insert({ player_id: bot.uid, pseudo: "bot_" + bot.n, elo: 1000, timer_seconds: timer });
      // 3) chercher un adversaire ; le plus petit id crée la partie
      const { data: cands } = await c.from("matchmaking_queue").select("*")
        .eq("timer_seconds", timer).neq("player_id", bot.uid)
        .order("joined_at", { ascending: true }).limit(5);
      if (cands && cands.length) {
        const opp = cands[0];
        if (bot.uid < opp.player_id) {
          await c.from("matchmaking_queue").delete().in("player_id", [bot.uid, opp.player_id]);
          const iAmWhite = Math.random() < 0.5;
          await createGame(c, iAmWhite ? bot.uid : opp.player_id, iAmWhite ? opp.player_id : bot.uid, timer, mover);
        }
      }
    } catch (e) { stats.errors++; console.warn("mm bot", bot.n, e.message); }
    await sleep(2500 + Math.random() * 1500); // rythme réaliste, jamais instantané
  }
  try { await c.from("matchmaking_queue").delete().eq("player_id", bot.uid); } catch (e) {}
}

// Crée la partie (game_state initial) — plateau standard neuf via le moteur.
async function createGame(client, whiteId, blackId, timer, mover) {
  // On construit un plateau de départ standard en jouant "aucun coup" : le
  // moteur d'index.html initialise via initGame() côté client — ici on lit le
  // plateau de départ depuis le format. ⚠ v1 : à confirmer (peut nécessiter un
  // helper labSetupState pour un état de départ identique).
  const start = mover.startState ? mover.startState() : null;
  const gs = start || { board: null, stacks: {}, lastMoved: null, lastMovedByColor: { white: null, black: null } };
  await client.from("online_games").insert({
    white_player_id: whiteId, black_player_id: blackId,
    game_state: gs, turn: "white", timer_seconds: timer,
  });
}

// Joue une partie jusqu'au bout (quand c'est notre tour, on pousse un coup). ⚠ v1.
async function playGame(bot, mover, game, stats) {
  const c = bot.client;
  const myColor = game.white_player_id === bot.uid ? "white" : "black";
  let gameId = game.id;
  for (let guard = 0; guard < 200; guard++) {
    const { data: rows } = await c.from("online_games").select("*").eq("id", gameId).limit(1);
    const g = rows && rows[0];
    if (!g || g.status !== "active") break;
    if (g.turn !== myColor) { await sleep(1200); continue; }
    // Notre tour : choisir + appliquer un coup, puis pousser le nouvel état.
    let out;
    try { out = JSON.parse(mover.botChooseAndApply(JSON.stringify(g.game_state), myColor, 2)); }
    catch (e) { stats.errors++; break; }
    if (!out || out.noMove) {
      await c.from("online_games").update({ status: "finished", winner: otherColor(myColor) }).eq("id", gameId);
      stats.losses++; break;
    }
    const upd = { game_state: out.state, turn: out.turn };
    if (out.won) { upd.status = "finished"; upd.winner = myColor; }
    await c.from("online_games").update(upd).eq("id", gameId);
    if (out.won) { stats.wins++; break; }
    await sleep(900 + Math.random() * 900);
  }
  stats.gamesPlayed++;
}

// ── MODE free : présence seule (le bot « existe » en ligne, sans jouer) ──
async function botFreeLoop(bot, isAliveRef) {
  const c = bot.client;
  while (isAliveRef.alive) {
    try { await c.from("profiles").update({ is_online: true, last_seen: new Date().toISOString() }).eq("id", bot.uid); }
    catch (e) {}
    await sleep(60000);
  }
}

async function main() {
  const t0 = Date.now();
  if (!SUPABASE_URL || !SERVICE_KEY) { console.log("⏸ Secret SUPABASE_SERVICE_ROLE_KEY absent → veille."); return; }
  if (!ANON_KEY) { console.log("✗ Clé anon introuvable dans index.html."); return; }

  const ctrl0 = await readControl();
  if (!ctrl0) { console.log("⚠ bot_army_control introuvable — dev_bot_army.sql exécuté ?"); return; }
  if (!ctrl0.enabled) { console.log("⏸ Directive désactivée (enabled=false) — rien à faire."); return; }

  const mode = ctrl0.mode || "matchmaking";
  const count = Math.min(Math.max(ctrl0.count || 0, 0), 100);
  console.log(`▶ Armée de bots : mode=${mode}, count=${count}, durée max=${RUN_MINUTES}min`);

  if (mode === "arena" || mode === "tournament") {
    // TODO v2 : cartographier les RPC de jointure (arena_*/tournament_register)
    // et faire rejoindre les bots à l'événement ciblé (ctrl0.target_id).
    console.log(`⚠ Mode « ${mode} » pas encore implémenté (v1). Utilise matchmaking ou free pour l'instant.`);
    await writeReport(mode, { bots_active: 0, games_played: 0, wins: 0, losses: 0, errors: 0, note: "non implémenté (v1)" });
    return;
  }

  const mover = makeMover(getFormat(html, "standard"));
  const isAliveRef = { alive: true };
  const stats = { gamesPlayed: 0, wins: 0, losses: 0, errors: 0 };
  const timer = 5; // cadence de test par défaut

  // Provisionne les bots (auth anonyme).
  const bots = [];
  for (let i = 1; i <= count; i++) {
    try { bots.push(await provisionBot(i)); } catch (e) { console.warn("provision", i, e.message); stats.errors++; }
    await sleep(120); // évite un burst de sign-ups
  }
  console.log(`✓ ${bots.length}/${count} bots provisionnés.`);

  // Lance les boucles par bot selon le mode.
  const loops = bots.map((b) => (mode === "free" ? botFreeLoop(b, isAliveRef) : botMatchmakingLoop(b, mover, timer, isAliveRef, stats)));

  // Boucle de supervision : rapport périodique + arrêt si directive coupée / temps écoulé.
  const budgetMs = RUN_MINUTES * 60 * 1000;
  while (Date.now() - t0 < budgetMs) {
    await sleep(5000);
    try {
      const ctrl = await readControl();
      if (!ctrl || !ctrl.enabled) { console.log("■ Directive coupée → arrêt des bots."); break; }
      await writeReport(mode, {
        bots_active: bots.length, games_played: stats.gamesPlayed,
        wins: stats.wins, losses: stats.losses, errors: stats.errors,
      });
    } catch (e) { console.warn("supervision", e.message); }
  }
  isAliveRef.alive = false;
  await Promise.race([Promise.allSettled(loops), sleep(5000)]);
  await writeReport(mode, { bots_active: 0, games_played: stats.gamesPlayed, wins: stats.wins, losses: stats.losses, errors: stats.errors, note: "run terminé" });
  console.log(`✔ Fin : ${stats.gamesPlayed} parties, ${stats.wins}V/${stats.losses}D, ${stats.errors} err, ${Math.round((Date.now() - t0) / 1000)}s.`);
}

main().catch((e) => { console.error("✗ bot-army :", e.message); process.exit(1); });
