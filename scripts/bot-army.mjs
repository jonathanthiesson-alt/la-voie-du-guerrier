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
      // 🔴 lastPush = mémoire de la dernière poussée : SANS lui, allMoves n'applique
      // pas la règle anti-contre-poussée immédiate et le bot "triche" (il contre-
      // pousse là où un humain ne peut pas). Le vrai coup online le sérialise aussi.
      G.lastPush = st.lastPush || null;
      var moves = allMoves(color, G.board, G.stacks, G.lastMoved, G.lastPush, G.lastMovedByColor);
      if(!moves || !moves.length) return JSON.stringify({ noMove:true });
      var mv = null;
      try { mv = minimaxPlay(moves, G.board, G.stacks, G.lastMoved, G.lastPush, depth||2, evalTrainer, color); } catch(e){}
      if(!mv) mv = moves[Math.floor(Math.random()*moves.length)];
      var won = execMove(mv.fr, mv.fc, mv.tr, mv.tc, mv.action);
      return JSON.stringify({
        state:{ board:G.board, stacks:G.stacks, lastMoved:G.lastMoved, lastMovedByColor:G.lastMovedByColor, lastPush:G.lastPush },
        won: !!won, turn: color==='white'?'black':'white'
      });
    }
    // Position de départ standard 5×5, IDENTIQUE à setupBoard() d'index.html
    // (épéiste + 2 sabres en 2e ligne, bouclier devant). board et stacks sont
    // des tableaux rows×cols de null. Les Blancs commencent (turn géré à part).
    function startState(){
      var R=FORMAT.rows||5, C=FORMAT.cols||5;
      var board=[], stacks=[];
      for(var r=0;r<R;r++){ board.push(new Array(C).fill(null)); stacks.push(new Array(C).fill(null)); }
      board[0][2]={type:'epeiste',color:'white'}; board[0][1]={type:'sword',color:'white'}; board[0][3]={type:'sword',color:'white'}; board[1][2]={type:'shield',color:'white'};
      board[4][2]={type:'epeiste',color:'black'}; board[4][1]={type:'sword',color:'black'}; board[4][3]={type:'sword',color:'black'}; board[3][2]={type:'shield',color:'black'};
      return { board:board, stacks:stacks, lastMoved:null, lastPush:null, lastMovedByColor:{white:null,black:null} };
    }`;
  const factory = new Function(prelude + "\n\n" + body + "\n\n" + mover + "\n\nreturn { botChooseAndApply: botChooseAndApply, startState: startState };");
  return factory();
}

// ── Moteur CHAMP DE BATAILLE (9×9, élimination d'unité) ───────────────
// Comme makeMover mais avec le format champDeBataille + les fonctions
// d'élimination (mêmes que le client, extraites d'index.html). G.battlefieldMode
// active la règle de propriété (un combattant ne pousse QUE ses pièces) déjà
// gardée dans legalMoves. Trois entrées :
//   botChooseAndApplyBattlefield : joue le coup du combattant `unit` (restriction
//     racine au bon combattant, comme scheduleAI côté client) + élimination.
//   bfHasMove : le combattant a-t-il un coup légal (pour sauter un siège bloqué).
//   bfEliminate : balaie une escouade (forfait/timeout) et dit si le camp tombe.
function makeBattlefieldMover() {
  const format = getFormat(html, "champDeBataille");
  const prelude = [
    "var FORMAT=" + JSON.stringify(format) + ";",
    "var VOID_STD=new Set(FORMAT.voids||[]);",
    'function isValid(r,c){return r>=0&&r<(FORMAT.rows||9)&&c>=0&&c<(FORMAT.cols||9)&&!VOID_STD.has(r+","+c);}',
    "var DO=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1}];",
    "var DA=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1},{dr:-1,dc:-1},{dr:-1,dc:1},{dr:1,dc:-1},{dr:1,dc:1}];",
    "var PP={totalCaptures:0,totalPushes:0};",
    "function playSound(){} function haptic(){}",
    "var G={simulating:true,battlefieldMode:true,rows:FORMAT.rows||9,cols:FORMAT.cols||9,sumoMode:false,pieceDefs:(FORMAT.pieces||null),turn:null,lastPush:null,lastMoved:null,lastMovedByColor:{white:null,black:null},eliminatedUnits:[]};",
    "function isV2mode(){return !!FORMAT.v2;}",
  ].join("\n");
  const names = ENGINE_NAMES.concat(["bfSameUnit", "battlefieldVictim", "sweepBattlefieldUnit", "battlefieldResolve"]);
  const body = names.map((n) => extractFn(html, n)).join("\n\n");
  const mover = `
    function botChooseAndApplyBattlefield(stateJson, color, unit, depth){
      var st=JSON.parse(stateJson);
      G.board=st.board; G.stacks=st.stacks||{};
      G.lastMoved=st.lastMoved||null; G.lastMovedByColor=st.lastMovedByColor||{white:null,black:null}; G.lastPush=st.lastPush||null;
      G.eliminatedUnits=st.eliminatedUnits||[];
      var all=allMoves(color,G.board,G.stacks,G.lastMoved,G.lastPush,G.lastMovedByColor);
      // Restriction RACINE au combattant du siège (les autres unités du camp
      // sont jouées par leurs propres joueurs, à leur propre tour).
      var moves=all.filter(function(m){ var p=G.board[m.fr]&&G.board[m.fr][m.fc]; return p&&p.unit===unit; });
      if(!moves.length) return JSON.stringify({ noMove:true });
      var mv=null;
      try{ mv=minimaxPlay(moves,G.board,G.stacks,G.lastMoved,G.lastPush,depth||1,evalTrainer,color); }catch(e){}
      if(!mv) mv=moves[Math.floor(Math.random()*moves.length)];
      // Victime identifiée AVANT execMove (qui écrase le plateau), puis résolution
      // d'élimination : won=true seulement si le CAMP entier tombe.
      var victim=battlefieldVictim(mv.action,mv.fr,mv.fc,mv.tr,mv.tc,color);
      var won=execMove(mv.fr,mv.fc,mv.tr,mv.tc,mv.action);
      won=battlefieldResolve(victim,won);
      return JSON.stringify({
        state:{ board:G.board, stacks:G.stacks, lastMoved:G.lastMoved, lastMovedByColor:G.lastMovedByColor, lastPush:G.lastPush, eliminatedUnits:G.eliminatedUnits, format:FORMAT },
        won:!!won, camp:color
      });
    }
    function bfHasMove(stateJson, color, unit){
      var st=JSON.parse(stateJson);
      G.board=st.board; G.stacks=st.stacks||{};
      G.lastMoved=st.lastMoved||null; G.lastMovedByColor=st.lastMovedByColor||{white:null,black:null}; G.lastPush=st.lastPush||null;
      var ms=allMoves(color,G.board,G.stacks,G.lastMoved,G.lastPush,G.lastMovedByColor);
      for(var i=0;i<ms.length;i++){ var p=G.board[ms[i].fr]&&G.board[ms[i].fr][ms[i].fc]; if(p&&p.unit===unit) return true; }
      return false;
    }
    function bfEliminate(stateJson, color, unit){
      var st=JSON.parse(stateJson);
      G.board=st.board; G.stacks=st.stacks||{};
      G.eliminatedUnits=st.eliminatedUnits||[];
      sweepBattlefieldUnit(color,unit);
      if(G.eliminatedUnits.indexOf(color+':'+unit)<0) G.eliminatedUnits.push(color+':'+unit);
      var camp=(findMaster(color,G.board)===null);
      return JSON.stringify({
        state:{ board:G.board, stacks:G.stacks, lastMoved:st.lastMoved||null, lastMovedByColor:st.lastMovedByColor||{white:null,black:null}, lastPush:st.lastPush||null, eliminatedUnits:G.eliminatedUnits, format:FORMAT },
        campEliminated:camp
      });
    }`;
  const factory = new Function(prelude + "\n\n" + body + "\n\n" + mover + "\n\nreturn { botChooseAndApplyBattlefield: botChooseAndApplyBattlefield, bfHasMove: bfHasMove, bfEliminate: bfEliminate };");
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
// Crée (ou met à jour) le profil du bot en service_role. 🔴 Les comptes anonymes
// n'ont PAS de trigger de création de profil (l'app insère la ligne côté client
// après signup) : un simple PATCH ne toucherait aucune ligne. On UPSERT donc la
// ligne. Seuls id + pseudo sont obligatoires ; le reste a des valeurs par défaut.
async function flagBotProfile(userId, n) {
  await sbAdmin("profiles?on_conflict=id", {
    method: "POST",
    headers: { "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
    // Pseudo unique par compte (le pseudo a une contrainte UNIQUE) : suffixe
    // avec un fragment de l'uid pour ne pas collisionner entre deux runs.
    body: JSON.stringify({ id: userId, is_bot: true, pseudo: "bot_" + String(n).padStart(3, "0") + "_" + userId.slice(0, 4) }),
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
      // 3) chercher un adversaire ; le plus petit id crée la partie.
      // 🔴 Uniquement des entrées RÉCENTES (< 90 s) : sinon on se matche avec un
      // bot d'une cohorte morte (worker terminé) → partie orpheline jamais jouée.
      const fresh = new Date(Date.now() - 90000).toISOString();
      const { data: cands } = await c.from("matchmaking_queue").select("*")
        .eq("timer_seconds", timer).neq("player_id", bot.uid).gt("joined_at", fresh)
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

// Crée la partie (game_state initial) — plateau standard neuf via le moteur
// (startState() reproduit setupBoard() d'index.html).
async function createGame(client, whiteId, blackId, timer, mover) {
  const gs = mover.startState();
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
  // 🔴 Handshake de présence : le client adverse masque le plateau ("En attente
  // de l'adversaire…") tant que les DEUX colonnes ready_white/ready_black ne sont
  // pas à true (voir markReadyAndWaitForOpponent dans index.html). Le bot pose la
  // sienne, sinon un joueur humain reste bloqué sur un plateau non chargé.
  const myReadyCol = myColor === "white" ? "ready_white" : "ready_black";
  try { await c.from("online_games").update({ [myReadyCol]: true }).eq("id", gameId); } catch (e) {}
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

// ══════════════════════════════════════════════════════════════════════
// MODE backfill — « l'équipe des 15 » (Phase B)
// Provisionne les 16 bots NOMMÉS (comptes persistants + profils is_bot + Elo
// fixe + devise=sens du nom), puis apparie les joueurs qui poireautent dans la
// file (want_backfill) avec le bot d'Elo le plus proche et pilote ses coups.
// Tout en service_role (les 16 sont des identités serveur, pas de session).
// ══════════════════════════════════════════════════════════════════════

// Admin Auth API (création de comptes) — endpoint /auth/v1, pas /rest/v1.
async function sbAuthAdmin(path, init) {
  const res = await fetch(SUPABASE_URL + "/auth/v1/" + path, {
    ...init,
    headers: { apikey: SERVICE_KEY, Authorization: "Bearer " + SERVICE_KEY, "Content-Type": "application/json", ...(init && init.headers) },
  });
  return res;
}
const randPass = () => "Bot!" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2).toUpperCase();

async function fetchRoster() {
  return await (await sbAdmin("bot_roster?select=*&order=sort")).json();
}
async function findProfileIdByPseudo(pseudo) {
  const rows = await (await sbAdmin("profiles?pseudo=eq." + encodeURIComponent(pseudo) + "&select=id")).json();
  return rows[0] ? rows[0].id : null;
}
async function adminFindUserIdByEmail(email) {
  for (let page = 1; page <= 20; page++) {
    const res = await sbAuthAdmin("admin/users?page=" + page + "&per_page=200", { method: "GET" });
    if (!res.ok) break;
    const data = await res.json();
    const users = data.users || data || [];
    const hit = users.find((u) => (u.email || "").toLowerCase() === email.toLowerCase());
    if (hit) return hit.id;
    if (!users.length || users.length < 200) break;
  }
  return null;
}
async function adminCreateUser(email) {
  const res = await sbAuthAdmin("admin/users", {
    method: "POST",
    body: JSON.stringify({ email, password: randPass(), email_confirm: true, user_metadata: { team15_bot: true } }),
  });
  if (res.ok) { const u = await res.json(); return u.id || (u.user && u.user.id) || null; }
  // Déjà créé (422) ou autre : on tentera la récupération par email en aval.
  return null;
}
// UPSERT du profil du bot (id = auth user). Devise = explication du nom (le
// trigger enforce_devise la valide ; nos devises sont propres, ≤60).
async function upsertBotProfile(b, pid) {
  await sbAdmin("profiles?on_conflict=id", {
    method: "POST",
    headers: { "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({
      id: pid, pseudo: b.pseudo, is_bot: true, is_online: true,
      elo_3s: b.base_elo, elo_5s: b.base_elo, elo_10s: b.base_elo, devise: b.devise,
    }),
  });
}
async function setRosterProfileId(key, pid) {
  await sbAdmin("bot_roster?key=eq." + encodeURIComponent(key), {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ profile_id: pid }),
  });
}
// Idempotent : réutilise profile_id si déjà lié, sinon adopte un profil de même
// pseudo, sinon crée le compte auth. Renseigne bot_roster.profile_id.
async function provisionRosterBots() {
  const roster = await fetchRoster();
  for (const b of roster) {
    try {
      let pid = b.profile_id || (await findProfileIdByPseudo(b.pseudo));
      if (!pid) {
        const email = "bot-" + b.key + "@team15.bots";
        pid = (await adminCreateUser(email)) || (await adminFindUserIdByEmail(email));
      }
      if (!pid) { console.warn("provision roster : pas d'id pour", b.key); continue; }
      await upsertBotProfile(b, pid);
      if (b.profile_id !== pid) await setRosterProfileId(b.key, pid);
      b.profile_id = pid;
    } catch (e) { console.warn("provision roster", b.key, e.message); }
    await sleep(150);
  }
  const ok = roster.filter((b) => b.profile_id);
  console.log("✓ Roster provisionné : " + ok.length + "/16 bots nommés.");
  return ok;
}
// Force minimax ∝ Elo (plus le bot est fort, plus il regarde loin).
function botDepth(elo) { return elo < 1150 ? 1 : elo < 1800 ? 2 : elo < 2400 ? 3 : 4; }
const inList = (col, ids) => col + "=in.(" + ids.join(",") + ")";

// Le joueur a-t-il une partie active RÉCENTE (< 5 min) ? Sert à ne PAS backfill
// un joueur déjà en partie, tout en IGNORANT les parties 'active' orphelines
// (jamais soldées) qui, sinon, le bloqueraient à vie.
const FRESH_GAME_MS = 5 * 60 * 1000;
async function hasFreshActiveGame(playerId) {
  const rows = await (await sbAdmin("online_games?or=(white_player_id.eq." + playerId + ",black_player_id.eq." + playerId + ")&status=eq.active&select=created_at,updated_at&order=created_at.desc&limit=3")).json();
  if (!Array.isArray(rows)) return false;
  return rows.some((g) => (Date.now() - new Date(g.updated_at || g.created_at).getTime()) < FRESH_GAME_MS);
}

// Un tour de backfill : apparie les humains qui attendent avec un bot libre.
async function backfillTick(mover, roster, busyPids, stats) {
  const _waiting = await (await sbAdmin("matchmaking_queue?want_backfill=eq.true&select=*")).json();
  const waiting = Array.isArray(_waiting) ? _waiting : [];
  for (const q of waiting) {
    try {
      const ageS = (Date.now() - new Date(q.joined_at).getTime()) / 1000;
      if (ageS < (q.backfill_after || 20)) continue;                    // pas encore assez patienté
      // Déjà en partie RÉCENTE ? (le poll du joueur l'aura ramassée) On ignore
      // les parties « active » PÉRIMÉES : un online_games orphelin (onglet fermé
      // en pleine partie, jamais soldé) restait 'active' à vie et bloquait le
      // backfill du joueur POUR TOUJOURS (bug vécu : une partie fantôme de 44 h
      // empêchait tout bot de rejoindre). Seuil 5 min ≫ timer par coup (3/5/10s).
      if (await hasFreshActiveGame(q.player_id)) continue;
      // Bots partagés : un même bot peut affronter PLUSIEURS joueurs à la fois,
      // sur toutes les cadences ET tous les modes (partie rapide, arène…). On
      // n'exclut donc plus les bots « occupés » — deux joueurs d'Elo voisin, un
      // en 3s l'autre en 5s, tombent volontiers sur le même bot (celui de leur
      // niveau). driveRosterGames pilote en parallèle toutes les parties d'un
      // bot, donc la concurrence est déjà gérée côté pilotage.
      let free = roster.slice();
      // Plafond de déblocage : le joueur n'affronte que les bots qu'il a
      // débloqués (base_elo <= backfill_max_elo). 0/absent = pas de filtre.
      // Repli si le filtre ne laisse rien (ex. tous ses bots occupés) : on garde
      // la liste complète plutôt que de le laisser sans compagnon.
      if (q.backfill_max_elo && q.backfill_max_elo > 0) {
        const capped = free.filter((b) => b.base_elo <= q.backfill_max_elo);
        if (capped.length) free = capped;
      }
      if (!free.length) break;
      // Choix du bot : au HASARD si le joueur a coché « aléatoire »
      // (backfill_random), sinon le plus proche de son Elo (défaut).
      let bot;
      if (q.backfill_random) {
        bot = free[Math.floor(Math.random() * free.length)];
      } else {
        free.sort((a, b) => Math.abs(a.base_elo - q.elo) - Math.abs(b.base_elo - q.elo));
        bot = free[0];
      }
      // crée la partie humain↔bot (amicale : ranked=false), bot déjà « prêt »
      const iAmWhite = Math.random() < 0.5;
      const gs = mover.startState();
      await sbAdmin("online_games", {
        method: "POST",
        headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({
          white_player_id: iAmWhite ? bot.profile_id : q.player_id,
          black_player_id: iAmWhite ? q.player_id : bot.profile_id,
          game_state: gs, turn: "white", timer_seconds: q.timer_seconds, ranked: false,
          ready_white: iAmWhite ? true : false, ready_black: iAmWhite ? false : true,
        }),
      });
      await sbAdmin("matchmaking_queue?player_id=eq." + q.player_id, { method: "DELETE", headers: { Prefer: "return=minimal" } });
      console.log("🤝 backfill : " + bot.pseudo + " (Elo " + bot.base_elo + ") rejoint un joueur (Elo " + q.elo + ").");
    } catch (e) { stats.errors++; console.warn("backfillTick", e.message); }
  }
}

// Pilote les coups des bots du roster dans leurs parties actives (service_role).
async function driveRosterGames(mover, byPid, stats) {
  const pids = [...byPid.keys()];
  if (!pids.length) return new Set();
  const busy = new Set();
  // ⚠ PostgREST : dans un or=(...), la syntaxe est POINTÉE (col.in.(…)), pas
  // col=in.(…) comme un filtre de premier niveau (cf. inList). Utiliser inList
  // ici donnait un 400 (PGRST100) → games devenait un objet d'erreur, le for…of
  // levait une exception et le backfill n'écrivait jamais son rapport.
  const idCsv = pids.join(",");
  const _games = await (await sbAdmin("online_games?status=eq.active&select=*&or=(white_player_id.in.(" + idCsv + "),black_player_id.in.(" + idCsv + "))")).json();
  const games = Array.isArray(_games) ? _games : [];
  for (const g of games) {
    try {
      // Marque « prêt » TOUT bot présent (blanc et/ou noir) — sinon le plateau
      // adverse reste masqué. Gère aussi le cas bot-vs-bot (les deux côtés).
      for (const col of ["white", "black"]) {
        const pid = col === "white" ? g.white_player_id : g.black_player_id;
        const readyCol = col === "white" ? "ready_white" : "ready_black";
        if (byPid.has(pid) && !g[readyCol]) {
          await sbAdmin("online_games?id=eq." + g.id, { method: "PATCH", headers: { "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify({ [readyCol]: true }) });
        }
      }
      // On pilote le camp AU TRAIT s'il est un bot (essentiel en bot-vs-bot de
      // tournoi : sinon seul le blanc jouait et le noir restait bloqué).
      const turnPid = g.turn === "white" ? g.white_player_id : g.black_player_id;
      if (!byPid.has(turnPid)) continue; // au tour d'un humain
      const bot = byPid.get(turnPid);
      const myColor = g.turn;
      busy.add(turnPid);
      let out;
      try { out = JSON.parse(mover.botChooseAndApply(JSON.stringify(g.game_state), myColor, botDepth(bot.base_elo))); }
      catch (e) { stats.errors++; continue; }
      const upd = out.noMove
        ? { status: "finished", winner: otherColor(myColor) }
        : { game_state: out.state, turn: out.turn, ...(out.won ? { status: "finished", winner: myColor } : {}) };
      await sbAdmin("online_games?id=eq." + g.id, { method: "PATCH", headers: { "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify(upd) });
      if (out.won) { stats.wins++; stats.gamesPlayed++; }
      else if (out.noMove) { stats.losses++; stats.gamesPlayed++; }
    } catch (e) { stats.errors++; console.warn("driveRosterGames", e.message); }
  }
  return busy;
}

// Un tour de backfill ARÈNE : un joueur d'arène qui poireaute (want_backfill)
// est rejoint par un bot d'Elo voisin, en match AMICAL (arena_matches ranked=
// false) + sa manche 1. Le client humain gère ensuite la progression du BO3
// (il détecte l'adversaire bot). Comme le backfill classique : bots partagés
// (un bot peut servir plusieurs joueurs, toutes cadences/modes confondus).
async function arenaBackfillTick(mover, roster, stats) {
  const _awaiting = await (await sbAdmin("arena_matchmaking_queue?want_backfill=eq.true&select=*")).json();
  const waiting = Array.isArray(_awaiting) ? _awaiting : [];
  for (const q of waiting) {
    try {
      if ((q.mode || "arena") !== "arena") continue; // pas le SUMO (événement)
      const ageS = (Date.now() - new Date(q.joined_at).getTime()) / 1000;
      if (ageS < (q.backfill_after || 20)) continue;
      // déjà dans un match d'arène actif RÉCENT ? (son poll l'aura rejoint) On
      // ignore les matchs orphelins : seuil 15 min (un BO3 dure quelques min).
      const _m0 = await (await sbAdmin("arena_matches?status=eq.active&or=(white_player_id.eq." + q.player_id + ",black_player_id.eq." + q.player_id + ")&select=created_at&order=created_at.desc&limit=3")).json();
      if (Array.isArray(_m0) && _m0.some((m) => (Date.now() - new Date(m.created_at).getTime()) < 15 * 60 * 1000)) continue;
      // bot d'Elo voisin (mêmes règles que le backfill classique)
      let free = roster.slice();
      if (q.backfill_max_elo && q.backfill_max_elo > 0) {
        const capped = free.filter((b) => b.base_elo <= q.backfill_max_elo);
        if (capped.length) free = capped;
      }
      if (!free.length) break;
      const myElo = q.elo || 1200;
      let bot;
      if (q.backfill_random) bot = free[Math.floor(Math.random() * free.length)];
      else { free.sort((a, b) => Math.abs(a.base_elo - myElo) - Math.abs(b.base_elo - myElo)); bot = free[0]; }
      // Match d'arène AMICAL (ranked=false) + manche 1. Couleurs = slots du match
      // (createArenaRound côté client fait pareil en manche impaire).
      const iAmWhite = Math.random() < 0.5;
      const whiteId = iAmWhite ? bot.profile_id : q.player_id;
      const blackId = iAmWhite ? q.player_id : bot.profile_id;
      const created = await (await sbAdmin("arena_matches", {
        method: "POST",
        headers: { "Content-Type": "application/json", Prefer: "return=representation" },
        body: JSON.stringify({ white_player_id: whiteId, black_player_id: blackId, timer_seconds: q.timer_seconds, mode: "arena", ranked: false }),
      })).json();
      const match = created && created[0];
      if (!match) { stats.errors++; continue; }
      const gs = mover.startState();
      await sbAdmin("online_games", {
        method: "POST",
        headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({
          white_player_id: whiteId, black_player_id: blackId,
          game_state: gs, turn: "white", timer_seconds: q.timer_seconds, ranked: false,
          arena_match_id: match.id, arena_round_number: 1,
          ready_white: whiteId === bot.profile_id, ready_black: blackId === bot.profile_id,
        }),
      });
      await sbAdmin("arena_matchmaking_queue?player_id=eq." + q.player_id, { method: "DELETE", headers: { Prefer: "return=minimal" } });
      console.log("🥊 arène backfill : " + bot.pseudo + " (Elo " + bot.base_elo + ") rejoint un joueur (Elo " + myElo + ").");
    } catch (e) { stats.errors++; console.warn("arenaBackfillTick", e.message); }
  }
}

// Tournoi : les bots jouent réellement leurs rondes. Pour chaque tournoi en
// cours ('running'), on traite les paires NON soldées de la ronde courante qui
// contiennent au moins un bot :
//  • bot vs bot : on crée la partie (online_games) si absente et on l'attache au
//    pairing (service_role). driveRosterGames pilote les DEUX camps ; à la fin
//    on reporte via tournament_report_from_game (idempotent, sans garde auth).
//  • bot vs humain : l'humain crée et joue la partie ; on se contente de
//    reporter le résultat si sa partie est finie mais pas encore soldée.
// La progression des rondes (appariements, deadlines, forfaits) reste 100 %
// serveur (pg_cron tournament_cleanup) — rien à faire ici.
async function tournamentTick(mover, roster, byPid, stats) {
  const _running = await (await sbAdmin("tournaments?status=eq.running&select=id,current_round,timer_seconds")).json();
  const running = Array.isArray(_running) ? _running : [];
  for (const t of running) {
    try {
      const _pairs = await (await sbAdmin("tournament_pairings?tournament_id=eq." + t.id + "&round=eq." + t.current_round + "&result=is.null&select=*")).json();
      const pairs = Array.isArray(_pairs) ? _pairs : [];
      for (const pr of pairs) {
        if (!pr.white_id || !pr.black_id) continue; // bye : géré serveur
        const whiteBot = byPid.has(pr.white_id), blackBot = byPid.has(pr.black_id);
        if (!whiteBot && !blackBot) continue;        // paire 100 % humaine
        if (!pr.online_game_id) {
          // Seul le cas bot-vs-bot exige qu'on crée la partie : sinon on laisse
          // l'humain la créer (chemin client normal).
          if (whiteBot && blackBot) {
            const gs = mover.startState();
            const g = await (await sbAdmin("online_games", {
              method: "POST",
              headers: { "Content-Type": "application/json", Prefer: "return=representation" },
              body: JSON.stringify({
                white_player_id: pr.white_id, black_player_id: pr.black_id,
                game_state: gs, turn: "white", timer_seconds: t.timer_seconds, ranked: false,
                ready_white: true, ready_black: true,
              }),
            })).json();
            const gid = g && g[0] && g[0].id;
            if (gid) await sbAdmin("tournament_pairings?id=eq." + pr.id, { method: "PATCH", headers: { "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify({ online_game_id: gid }) });
          }
          continue;
        }
        // Partie attachée : finie ? On reporte (idempotent).
        const gr = await (await sbAdmin("online_games?id=eq." + pr.online_game_id + "&select=status,winner&limit=1")).json();
        const g = gr && gr[0];
        if (g && g.status === "finished" && g.winner) {
          await sbAdmin("rpc/tournament_report_from_game", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ p_game_id: pr.online_game_id, p_winner: g.winner }),
          });
          stats.gamesPlayed++;
        }
      }
    } catch (e) { stats.errors++; console.warn("tournamentTick", e.message); }
  }
}

// Guerre de guilde : dès qu'un défi inter-guildes est ACTIF, on fait s'affronter
// en parties CLASSÉES les bots des deux guildes, puis on score chaque partie finie
// via guild_report_win_server (RPC serveur — guild_report_win exige auth.uid(),
// inappelable en service_role, exactement comme tournament_report_from_game).
// Dormant s'il n'y a aucun défi actif, ou si les guildes n'ont pas de bots du
// roster (défi 100 % humain : rien à piloter ici → aucun effet de bord).
async function guildWarTick(mover, byPid, stats) {
  const _wars = await (await sbAdmin("guild_tournaments?status=eq.active&select=id,guild_a,guild_b,deadline")).json();
  const wars = Array.isArray(_wars) ? _wars : [];
  for (const w of wars) {
    try {
      const mems = await (await sbAdmin("guild_members?select=player_id,guild_id&guild_id=in.(" + w.guild_a + "," + w.guild_b + ")")).json();
      if (!Array.isArray(mems)) continue;
      const botsA = mems.filter((m) => m.guild_id === w.guild_a && byPid.has(m.player_id)).map((m) => m.player_id);
      const botsB = mems.filter((m) => m.guild_id === w.guild_b && byPid.has(m.player_id)).map((m) => m.player_id);
      if (!botsA.length || !botsB.length) continue;   // il faut au moins un bot de chaque côté
      const allBots = botsA.concat(botsB);
      const idCsv = allBots.join(",");
      // 1) SCORER les parties classées finies non comptées de ces bots.
      const _fin = await (await sbAdmin("online_games?status=eq.finished&guild_counted=eq.false&ranked=eq.true&select=id&limit=50&or=(white_player_id.in.(" + idCsv + "),black_player_id.in.(" + idCsv + "))")).json();
      const fin = Array.isArray(_fin) ? _fin : [];
      for (const g of fin) {
        await sbAdmin("rpc/guild_report_win_server", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ p_game_id: g.id }) });
      }
      // 2) ENTRETENIR l'affrontement : s'il n'y a pas déjà une partie active
      //    croisée A↔B, en créer une (classée, les deux bots « prêts »).
      const _act = await (await sbAdmin("online_games?status=eq.active&select=white_player_id,black_player_id&or=(white_player_id.in.(" + idCsv + "),black_player_id.in.(" + idCsv + "))")).json();
      const act = Array.isArray(_act) ? _act : [];
      const cross = (a, b) => (botsA.includes(a) && botsB.includes(b)) || (botsB.includes(a) && botsA.includes(b));
      const hasCross = act.some((g) => cross(g.white_player_id, g.black_player_id));
      if (!hasCross) {
        const a = botsA[Math.floor(Math.random() * botsA.length)];
        const b = botsB[Math.floor(Math.random() * botsB.length)];
        const aWhite = Math.random() < 0.5;
        const gs = mover.startState();
        await sbAdmin("online_games", {
          method: "POST",
          headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
          body: JSON.stringify({
            white_player_id: aWhite ? a : b, black_player_id: aWhite ? b : a,
            game_state: gs, turn: "white", timer_seconds: 5, ranked: true,
            ready_white: true, ready_black: true,
          }),
        });
        console.log("⚔ guerre de guilde " + w.guild_a + " vs " + w.guild_b + " : nouvelle passe classée.");
      }
    } catch (e) { stats.errors++; console.warn("guildWarTick", e.message); }
  }
}

// ══════════════════════════════════════════════════════════════════
// CHAMP DE BATAILLE — pilotage des sièges bots + timeouts + file solo
// ══════════════════════════════════════════════════════════════════
// battlefield_games : partie 6 sièges (table dédiée, cf. battlefield_online.sql).
// Le siège ACTIF est seats[seat_idx]. On ne pilote que les sièges bots du roster ;
// les humains jouent depuis le client. Toutes ces fonctions avalent l'absence de
// table (SQL pas encore exécuté) pour ne jamais casser la boucle de backfill.

function bfDeadline(timer){ const s = (timer && timer > 0) ? timer : 5; return new Date(Date.now() + s * 1000 + 3000).toISOString(); }
function bfSeatsElim(seats, elim){ const e = elim || []; return (seats || []).map((s) => ({ ...s, eliminated: e.indexOf(s.color + ":" + s.unit) >= 0 })); }
function bfSeatOk(bfMover, seat, state, elim){
  if (!seat) return false;
  if ((elim || []).indexOf(seat.color + ":" + seat.unit) >= 0) return false;
  try { return bfMover.bfHasMove(JSON.stringify(state), seat.color, seat.unit); } catch (e) { return true; }
}
// Prochain siège jouable (saute éliminés + combattants sans coup), sur l'état
// APRÈS le coup — même règle que bfAdvanceSeat/bfOnlineComputeNextIdx du client.
function bfNextPlayable(bfMover, seats, fromIdx, state, elim){
  const n = seats.length; if (!n) return 0;
  let idx = fromIdx, tries = 0;
  do { idx = (idx + 1) % n; tries++; } while (!bfSeatOk(bfMover, seats[idx], state, elim) && tries <= n);
  return idx;
}

// Pilote le siège bot au trait dans chaque partie battlefield active.
async function driveBattlefieldGames(bfMover, byPid, stats){
  try {
    const _games = await (await sbAdmin("battlefield_games?status=eq.active&select=*")).json();
    const games = Array.isArray(_games) ? _games : [];
    for (const g of games) {
      try {
        const seats = g.seats || [];
        const seat = seats[g.seat_idx];
        if (!seat || !seat.is_bot || !byPid.has(seat.player_id)) continue; // humain au trait, ou bot hors roster
        if (!g.game_state || !g.game_state.board) continue;                // plateau pas encore posé par le créateur
        let out;
        // Profondeur 1 (glouton) : le 9×9 + 6 combattants a un facteur de
        // branchement élevé ; on privilégie la réactivité à la profondeur.
        try { out = JSON.parse(bfMover.botChooseAndApplyBattlefield(JSON.stringify(g.game_state), seat.color, seat.unit, 1)); }
        catch (e) { stats.errors++; continue; }
        let upd;
        if (out.noMove) {
          const ni = bfNextPlayable(bfMover, seats, g.seat_idx, g.game_state, (g.game_state.eliminatedUnits || []));
          upd = { seat_idx: ni, turn: (seats[ni] || {}).color || g.turn, turn_deadline: bfDeadline(g.timer_seconds) };
        } else if (out.won) {
          upd = { game_state: out.state, seats: bfSeatsElim(seats, out.state.eliminatedUnits), status: "finished", winner: seat.color };
        } else {
          const seats2 = bfSeatsElim(seats, out.state.eliminatedUnits);
          const ni = bfNextPlayable(bfMover, seats2, g.seat_idx, out.state, out.state.eliminatedUnits || []);
          upd = { game_state: out.state, seats: seats2, seat_idx: ni, turn: (seats2[ni] || {}).color || otherColor(seat.color), turn_deadline: bfDeadline(g.timer_seconds) };
        }
        await sbAdmin("battlefield_games?id=eq." + g.id, { method: "PATCH", headers: { "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify(upd) });
        if (out.won) { stats.wins++; stats.gamesPlayed++; }
      } catch (e) { stats.errors++; console.warn("driveBattlefieldGames(g)", e.message); }
    }
  } catch (e) { /* table absente tant que battlefield_online.sql n'est pas exécuté */ }
}

// Impose la cadence : un siège HUMAIN dont l'échéance est dépassée = forfait
// (son combattant est éliminé, comme une déconnexion), puis rotation. Les sièges
// bots jouent vite, on ne les fait pas expirer.
async function battlefieldTimeoutTick(bfMover, stats){
  try {
    const now = Date.now();
    const _games = await (await sbAdmin("battlefield_games?status=eq.active&select=*")).json();
    const games = Array.isArray(_games) ? _games : [];
    for (const g of games) {
      try {
        const seats = g.seats || [];
        const seat = seats[g.seat_idx];
        if (!seat || seat.is_bot) continue;
        if (!g.turn_deadline || new Date(g.turn_deadline).getTime() > now) continue;
        if (!g.game_state || !g.game_state.board) continue;
        let out;
        try { out = JSON.parse(bfMover.bfEliminate(JSON.stringify(g.game_state), seat.color, seat.unit)); }
        catch (e) { stats.errors++; continue; }
        const seats2 = bfSeatsElim(seats, out.state.eliminatedUnits);
        let upd;
        if (out.campEliminated) {
          upd = { game_state: out.state, seats: seats2, status: "finished", winner: otherColor(seat.color) };
        } else {
          const ni = bfNextPlayable(bfMover, seats2, g.seat_idx, out.state, out.state.eliminatedUnits || []);
          upd = { game_state: out.state, seats: seats2, seat_idx: ni, turn: (seats2[ni] || {}).color, turn_deadline: bfDeadline(g.timer_seconds) };
        }
        await sbAdmin("battlefield_games?id=eq." + g.id, { method: "PATCH", headers: { "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify(upd) });
        console.log("⏱ battlefield : forfait " + seat.color + ":" + seat.unit + " (temps dépassé).");
      } catch (e) { stats.errors++; console.warn("battlefieldTimeoutTick(g)", e.message); }
    }
  } catch (e) { /* table absente */ }
}

// File solo → slots ouverts : délègue au RPC serveur (place les joueurs de
// battlefield_solo_queue dans les équipes 'forming' ouvertes d'ELO proche).
async function battlefieldSoloFill(stats){
  try {
    const res = await sbAdmin("rpc/battlefield_solo_place", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
    const n = await res.json();
    if (n && n > 0) console.log("🎲 file solo battlefield : " + n + " joueur(s) placé(s).");
  } catch (e) { /* RPC/table absents tant que le SQL n'est pas exécuté */ }
}

async function runBackfill(mover, t0) {
  const roster = await provisionRosterBots();
  if (!roster.length) { console.log("✗ Aucun bot du roster provisionné — abandon."); return; }
  const byPid = new Map(roster.map((b) => [b.profile_id, b]));
  const stats = { gamesPlayed: 0, wins: 0, losses: 0, errors: 0 };
  // Moteur champ de bataille (9×9) — construit une fois. Si l'extraction échoue
  // (format absent), on continue sans : le reste du backfill n'en dépend pas.
  let bfMover = null;
  try { bfMover = makeBattlefieldMover(); } catch (e) { console.warn("makeBattlefieldMover", e.message); }
  const budgetMs = RUN_MINUTES * 60 * 1000;
  let ticks = 0;
  while (Date.now() - t0 < budgetMs) {
    try {
      const ctrl = await readControl();
      if (!ctrl || !ctrl.enabled) { console.log("■ Directive coupée → arrêt backfill."); break; }
      // 1) piloter TOUTES les parties en cours des bots (partie rapide, arène,
      //    tournoi — driveRosterGames balaie tout online_games contenant un bot)
      const busy = await driveRosterGames(mover, byPid, stats);
      // 2) apparier les joueurs en attente avec un bot (partie rapide + arène)
      await backfillTick(mover, roster, busy, stats);
      await arenaBackfillTick(mover, roster, stats);
      // 3) tournoi : créer/reporter les parties des paires contenant un bot
      await tournamentTick(mover, roster, byPid, stats);
      // 3bis) guerre de guilde : si un défi inter-guildes est actif, faire jouer
      //       et scorer les bots des deux guildes (dormant sinon)
      await guildWarTick(mover, byPid, stats);
      // 3ter) champ de bataille : piloter les sièges bots, imposer les timeouts
      //       (forfait) et remplir les slots ouverts depuis la file solo.
      if (bfMover) {
        await driveBattlefieldGames(bfMover, byPid, stats);
        await battlefieldTimeoutTick(bfMover, stats);
        await battlefieldSoloFill(stats);
      }
      // 4) garder les bots « en ligne » (le pg_cron le fait aussi, ceinture+bretelles)
      if (++ticks % 30 === 0) {
        await sbAdmin("profiles?" + inList("id", [...byPid.keys()]), { method: "PATCH", headers: { "Content-Type": "application/json", Prefer: "return=minimal" }, body: JSON.stringify({ is_online: true, last_seen: new Date().toISOString() }) });
      }
      await writeReport("backfill", { bots_active: roster.length, games_played: stats.gamesPlayed, wins: stats.wins, losses: stats.losses, errors: stats.errors });
    } catch (e) { console.warn("backfill boucle", e.message); }
    await sleep(2000);
  }
  await writeReport("backfill", { bots_active: 0, games_played: stats.gamesPlayed, wins: stats.wins, losses: stats.losses, errors: stats.errors, note: "run terminé" });
  console.log("✔ Backfill terminé : " + stats.wins + "V/" + stats.losses + "D, " + stats.errors + " err.");
}

async function main() {
  const t0 = Date.now();
  if (!SUPABASE_URL || !SERVICE_KEY) { console.log("⏸ Secret SUPABASE_SERVICE_ROLE_KEY absent → veille."); return; }
  if (!ANON_KEY) { console.log("✗ Clé anon introuvable dans index.html."); return; }

  const ctrl0 = await readControl();
  if (!ctrl0) { console.log("⚠ bot_army_control introuvable — dev_bot_army.sql exécuté ?"); return; }
  if (!ctrl0.enabled) { console.log("⏸ Directive désactivée (enabled=false) — rien à faire."); return; }

  // BOT_ARMY_MODE (input du workflow) peut surcharger la directive : permet de
  // lancer le backfill sans changer la directive (dont le RPC ne connaît pas
  // encore 'backfill' — ce sera câblé au lot 3, menu dev).
  // .toLowerCase() : l'input du workflow peut arriver capitalisé ('Backfill')
  // — sans ça, le test mode==='backfill' échouait et on retombait sur le mode
  // anonyme par défaut (bug vécu : rapport « Backfill », 0 bot du roster créé).
  const mode = (process.env.BOT_ARMY_MODE || ctrl0.mode || "matchmaking").toLowerCase();
  const count = Math.min(Math.max(ctrl0.count || 0, 0), 100);
  console.log(`▶ Armée de bots : mode=${mode}, count=${count}, durée max=${RUN_MINUTES}min`);

  // Mode « équipe des 15 » : bots nommés persistants qui servent TOUT le live
  // (partie rapide + arène en backfill, tournois joués réellement). Les anciens
  // libellés 'arena'/'tournament' pointent vers la même boucle unifiée : plus
  // besoin de worker dédié par mode.
  if (mode === "backfill" || mode === "arena" || mode === "tournament") {
    const moverBf = makeMover(getFormat(html, "standard"));
    await runBackfill(moverBf, t0);
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
