// ════════════════════════════════════════════════════════════════════════
// balance-worker.mjs — worker serveur d'équilibre (exécuté par GitHub Actions)
// ════════════════════════════════════════════════════════════════════════
// Fait tourner des parties bot vs bot en PROFONDEUR 4-5 (là où l'équilibre a
// été validé) et écrit le taux de victoire Blanc/Noir dans dev_balance_stats —
// la MÊME table que le Laboratoire du navigateur. Tourne sans aucun appareil
// allumé : une GitHub Action planifiée l'appelle (voir .github/workflows/).
//
// Pourquoi ici et pas dans une Edge Function Supabase : le minimax en prof. 4-5
// dépasse le budget CPU serré des Edge Functions (mesuré : échec dès 3 parties
// en prof. 4). Node dans un runner GitHub n'a pas cette limite, et l'Action est
// gratuite/illimitée sur un repo public.
//
// CLÉ DE VOÛTE (identique au Labo navigateur) : on ne duplique pas le moteur —
// on lit la SOURCE VIVANTE. Le Labo utilise Function.toString() ; ici on lit le
// texte de index.html (checkout du repo) et on extrait les mêmes fonctions.
// Une seule source de vérité, zéro dérive, zéro build. Le driver du Worker
// (labWorkerDriver) est réutilisé tel quel via un shim onmessage/postMessage.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createHash } from "node:crypto";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(join(ROOT, "index.html"), "utf8");

// EXACTEMENT la liste engineFns de labBuildEngineSource (isValid/isV2mode
// exclus : redéfinis dans le préambule à partir du descripteur de format).
const ENGINE_NAMES = [
  "findMaster", "dist", "threatCount", "cloneBS", "applyToClone", "allMoves",
  "labResolveDirs", "labGenericMoves", "labPieceValue", "legalMoves", "execMove",
  "evalPosition", "evalTrainer", "evalBalanceCurrent", "evalBalanceMobilityFixed",
  "evalBalanceSymmetric", "evalBalanceAgDfFixed", "minimaxFn", "minimaxPlay",
  "devSimTopMoves",
];

// Extracteur conscient des chaînes et commentaires : `function name(` puis
// équilibrage des accolades en ignorant strings/commentaires.
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
  throw new Error("ACCOLADES DÉSÉQUILIBRÉES: " + name);
}
function extractBody(src, name) {
  const f = extractFn(src, name);
  return f.slice(f.indexOf("{") + 1, f.lastIndexOf("}"));
}
function getFormat(src, id) {
  const key = id + ":{";
  const s = src.indexOf(key);
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
  throw new Error("Accolades du format " + id);
}
function buildScript(src, format) {
  const prelude = [
    "var FORMAT=" + JSON.stringify(format) + ";",
    "var VOID_STD=new Set(FORMAT.voids||[]);",
    'function isValid(r,c){return r>=0&&r<(FORMAT.rows||5)&&c>=0&&c<(FORMAT.cols||5)&&!VOID_STD.has(r+","+c);}',
    "var DO=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1}];",
    "var DA=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1},{dr:-1,dc:-1},{dr:-1,dc:1},{dr:1,dc:-1},{dr:1,dc:1}];",
    "var PP={totalCaptures:0,totalPushes:0};",
    "function playSound(){} function haptic(){}",
    "var G={simulating:true,rows:FORMAT.rows||5,cols:FORMAT.cols||5,sumoMode:!!FORMAT.sumo,pieceDefs:(FORMAT.pieces||null),turn:null,lastMovedByColor:{white:null,black:null}};",
    "function isV2mode(){return !!FORMAT.v2;}",
  ].join("\n");
  const body = ENGINE_NAMES.map((n) => extractFn(src, n)).join("\n\n");
  const driver = extractBody(src, "labWorkerDriver");
  return prelude + "\n\n" + body + "\n\n" + driver;
}
// Compile le moteur UNE fois (coûteux : new Function sur ~600 lignes) et rend
// une fonction qui lance des LOTS successifs. Utile pour respecter un budget de
// temps : on lance par petits lots et on s'arrête quand le budget est atteint.
// Chaque partie repart d'un plateau neuf (labSetupState), donc réutiliser
// l'instance entre les lots est sûr.
function makeRunner(script) {
  const results = [];
  const factory = new Function(
    "postMessage",
    "var onmessage;\n" + script + "\nreturn {get onmessage(){return onmessage;}};",
  );
  const api = factory((msg) => results.push(msg));
  return function runChunk(cfg, batch) {
    results.length = 0;
    api.onmessage({ data: Object.assign({ cmd: "run", batch }, cfg) });
    const out = [];
    for (const m of results) if (m.type === "game") out.push({ winner: m.winner, plies: m.plies, moves: m.moves });
    return out;
  };
}

// ── Écriture des résultats dans Supabase (RPC dev_record_balance_result) ──
const EVAL_LABELS = {
  symmetric: "Production actuelle (symétrique)",
  current: "Ancienne formule (asymétrique 1,3/1,6)",
  agdffix: "Variante — ag=df seul",
  mobfix: "Variante — mobilité seule",
};
// On écrit EN DIRECT dans la table (service_role → contourne la RLS), et non
// via l'RPC dev_record_balance_result : celle-ci est gardée par is_admin_user()
// qui exige un UTILISATEUR admin (auth.uid()), or le service_role n'est pas un
// utilisateur → « admin only ». On agrège tout le lot en UNE écriture sur la
// ligne unique (test_label, eval_label, depth_white, depth_black), avec la MÊME
// sémantique que l'RPC (games/wins/plies comptés sur les parties DÉCISIVES ;
// les nulles ne sont pas enregistrées). Pas de course : le workflow a un
// concurrency-group et le label `srv:` est distinct de celui du navigateur.
async function sbFetch(base, key, path, init) {
  const res = await fetch(base + "/rest/v1/" + path, {
    ...init,
    headers: { apikey: key, Authorization: "Bearer " + key, ...(init && init.headers) },
  });
  if (!res.ok) throw new Error((init && init.method || "GET") + " " + res.status + " : " + (await res.text()).slice(0, 200));
  return res;
}
async function upsertStats(base, key, testLabel, evalLabel, depth, agg) {
  const filter = `test_label=eq.${encodeURIComponent(testLabel)}` +
    `&eval_label=eq.${encodeURIComponent(evalLabel)}` +
    `&depth_white=eq.${depth}&depth_black=eq.${depth}`;
  const rows = await (await sbFetch(base, key,
    `dev_balance_stats?${filter}&select=id,games,white_wins,black_wins,total_plies,games_under_15`)).json();
  const now = new Date().toISOString();
  const prev = rows[0];
  if (prev) {
    await sbFetch(base, key, `dev_balance_stats?id=eq.${prev.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({
        games: prev.games + agg.games,
        white_wins: prev.white_wins + agg.white,
        black_wins: prev.black_wins + agg.black,
        total_plies: Number(prev.total_plies) + agg.plies,
        games_under_15: prev.games_under_15 + agg.under15,
        updated_at: now,
      }),
    });
  } else {
    await sbFetch(base, key, "dev_balance_stats", {
      method: "POST",
      headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({
        test_label: testLabel, eval_label: evalLabel, depth_white: depth, depth_black: depth,
        games: agg.games, white_wins: agg.white, black_wins: agg.black,
        total_plies: agg.plies, games_under_15: agg.under15, updated_at: now,
      }),
    });
  }
}

// Insertion anti-doublon : insert groupé dans dev_balance_games en visant la
// contrainte UNIQUE (on_conflict) avec resolution=ignore-duplicates. PostgREST
// ne renvoie ALORS que les lignes RÉELLEMENT insérées (les parties déjà vues
// dans un run précédent sont écartées). `games` est déjà dédupliqué localement.
async function insertGamesDedup(base, key, testLabel, evalLabel, depth, games) {
  if (!games.length) return [];
  const rows = games.map((g) => ({
    test_label: testLabel, eval_label: evalLabel,
    depth_white: depth, depth_black: depth,
    sig: g.sig, winner: g.winner, plies: g.plies,
  }));
  const res = await sbFetch(base, key,
    "dev_balance_games?on_conflict=test_label,eval_label,depth_white,depth_black,sig", {
      method: "POST",
      headers: { "Content-Type": "application/json", Prefer: "resolution=ignore-duplicates,return=representation" },
      body: JSON.stringify(rows),
    });
  return await res.json(); // uniquement les lignes insérées (doublons exclus)
}

// Lecture/écriture de la config du worker (Action = service_role, accès direct
// à la table, la RLS étant contournée — le navigateur, lui, passe par les RPC).
async function readWorkerConfig(base, key) {
  const rows = await (await sbFetch(base, key, "dev_worker_config?id=eq.1&select=*")).json();
  return rows[0] || null;
}
async function setCycleCurrent(base, key, next) {
  await sbFetch(base, key, "dev_worker_config?id=eq.1", {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ cycle_current: next }),
  });
}

// Dédup (local + base) puis incrémente dev_balance_stats par les parties INÉDITES.
async function persistDecisive(base, key, format, evalKey, depth, decisive) {
  const testLabel = "srv:" + format;
  const evalLabel = EVAL_LABELS[evalKey] || evalKey;
  const bySig = new Map();
  for (const m of decisive) {
    const sig = createHash("sha1").update(m.moves || "").digest("hex");
    if (!bySig.has(sig)) bySig.set(sig, { sig, winner: m.winner, plies: m.plies });
  }
  const local = [...bySig.values()];
  const fresh = await insertGamesDedup(base, key, testLabel, evalLabel, depth, local);
  const out = { fresh: fresh.length, dupLocal: decisive.length - local.length, dupDb: local.length - fresh.length };
  if (fresh.length) {
    const agg = { games: fresh.length, white: 0, black: 0, plies: 0, under15: 0 };
    for (const g of fresh) {
      if (g.winner === "white") agg.white++; else if (g.winner === "black") agg.black++;
      agg.plies += g.plies || 0; if ((g.plies || 0) < 15) agg.under15++;
    }
    await upsertStats(base, key, testLabel, evalLabel, depth, agg);
  }
  return out;
}

// ── Config d'exécution ───────────────────────────────────────────────────
// Deux sources : MANUEL (dispatch avec profondeur / dry-run local → variables
// BW_*) ou CONFIG (cron → lit dev_worker_config). Le cron ne fournit pas
// BW_DEPTH → mode config. BW_USE_CONFIG='true' force le mode config même en
// dispatch (pour tester le pilotage depuis le Labo).
const USE_CONFIG = process.env.BW_USE_CONFIG === "true";
const MANUAL = !USE_CONFIG && !!(process.env.BW_DEPTH && String(process.env.BW_DEPTH).trim());
const PERSIST = process.env.BW_PERSIST !== "0"; // BW_PERSIST=0 → dry-run local
const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";

async function main() {
  const t0 = Date.now();
  // Si on doit écrire mais que le secret repo n'est pas posé : veille (exit 0,
  // pas d'échec rouge). S'active seul dès que SUPABASE_SERVICE_ROLE_KEY est là.
  if (PERSIST && (!SUPABASE_URL || !SERVICE_KEY)) {
    console.log("⏸ Secret SUPABASE_SERVICE_ROLE_KEY absent → worker en veille. Ajoute-le dans Settings → Secrets and variables → Actions. (Dry-run local : BW_PERSIST=0.)");
    return;
  }

  // Résolution des paramètres.
  let fmtId, depth, evalKey, opening, gamesTarget, budgetSec, advanceCycleTo = null, customFormat = null;
  if (MANUAL) {
    fmtId = process.env.BW_FORMAT || "standard";
    depth = Math.min(Math.max(+process.env.BW_DEPTH, 1), 6);
    evalKey = process.env.BW_EVAL || "symmetric";
    opening = process.env.BW_OPENING !== undefined && process.env.BW_OPENING !== "" ? +process.env.BW_OPENING : 6;
    gamesTarget = Math.min(Math.max(+(process.env.BW_GAMES || 100), 1), 2000);
    budgetSec = Math.min(Math.max(+(process.env.BW_BUDGET || 1800), 30), 3300);
    // Dispatch manuel d'un mode custom : le descripteur JSON via BW_CUSTOM_FORMAT.
    if (fmtId === "custom" && process.env.BW_CUSTOM_FORMAT) customFormat = JSON.parse(process.env.BW_CUSTOM_FORMAT);
    console.log(`▶ manuel : ${fmtId}, prof.${depth}, cible ${gamesTarget} parties / ${budgetSec}s, éval ${evalKey}, ouverture ${opening}`);
  } else {
    if (!PERSIST) { console.log("↩ dry-run sans profondeur : fournis BW_DEPTH pour un essai local."); return; }
    const cfg = await readWorkerConfig(SUPABASE_URL, SERVICE_KEY);
    if (!cfg) { console.log("⚠ dev_worker_config introuvable — rien à faire."); return; }
    if (!cfg.enabled) { console.log("⏸ Worker désactivé (dev_worker_config.enabled=false). Rien à faire."); return; }
    fmtId = cfg.format; evalKey = cfg.eval_key; opening = cfg.opening;
    gamesTarget = cfg.games; budgetSec = cfg.time_budget_sec;
    customFormat = cfg.custom_format || null; // mode 'custom' construit dans le Labo
    if (cfg.mode === "cycle") {
      depth = Math.min(Math.max(cfg.cycle_current, cfg.cycle_min), cfg.cycle_max);
      advanceCycleTo = depth >= cfg.cycle_max ? cfg.cycle_min : depth + 1; // prochain tick
      console.log(`▶ config : ${fmtId}, prof.${depth} (cycle ${cfg.cycle_min}→${cfg.cycle_max}), cible ${gamesTarget} / ${budgetSec}s, éval ${evalKey}, ouverture ${opening}`);
    } else {
      depth = Math.min(Math.max(cfg.fixed_depth, 1), 6);
      console.log(`▶ config : ${fmtId}, prof.${depth} (fixe), cible ${gamesTarget} / ${budgetSec}s, éval ${evalKey}, ouverture ${opening}`);
    }
  }

  // Le mode 'custom' n'est PAS dans index.html : son descripteur vient de la
  // config (dev_worker_config.custom_format) ou de BW_CUSTOM_FORMAT. Les autres
  // formats sont extraits du registre LAB_FORMATS d'index.html (source vivante).
  let fmtObj;
  if (fmtId === "custom") {
    if (!customFormat) { console.log("⚠ format 'custom' demandé mais aucun descripteur (dev_worker_config.custom_format vide). Charge un mode depuis le Labo puis ré-enregistre la config."); return; }
    fmtObj = customFormat;
  } else {
    fmtObj = getFormat(html, fmtId);
  }
  const runChunk = makeRunner(buildScript(html, fmtObj));

  // Boucle par lots, bornée par la cible de parties ET le budget de temps
  // (la prof. 5-6 est lente → le budget garde chaque run sous la limite du job).
  const CHUNK = 10, budgetMs = budgetSec * 1000;
  const decisive = [];
  let n = 0, draw = 0, w = 0, b = 0, plies = 0;
  while (n < gamesTarget && (Date.now() - t0) < budgetMs) {
    const games = runChunk({ depthW: depth, depthB: depth, evalKey, openingN: opening }, Math.min(CHUNK, gamesTarget - n));
    for (const g of games) {
      n++; plies += g.plies;
      if (g.winner === "white") { w++; decisive.push(g); }
      else if (g.winner === "black") { b++; decisive.push(g); }
      else draw++;
    }
  }
  const dec = w + b;
  const wp = dec ? (100 * w / dec).toFixed(1) : "—";
  const sigma = dec ? (Math.abs(w / dec - 0.5) / (0.5 / Math.sqrt(dec))).toFixed(2) : "—";
  console.log(`■ ${n} parties (${draw} nulles) · Blancs ${w}/Noirs ${b} · ${wp}% Blancs · σ=${sigma} · ${(plies / Math.max(n, 1)).toFixed(1)} coups · ${Date.now() - t0}ms`);

  if (PERSIST) {
    if (dec) {
      const r = await persistDecisive(SUPABASE_URL, SERVICE_KEY, fmtId, evalKey, depth, decisive);
      if (r.fresh) console.log(`✓ ${r.fresh} parties INÉDITES → dev_balance_stats "srv:${fmtId}" prof.${depth} (ignorés : ${r.dupLocal} internes + ${r.dupDb} déjà en base).`);
      else console.log(`○ 0 inédite (${r.dupLocal} internes, ${r.dupDb} déjà en base) → stats inchangées.`);
    } else {
      console.log("○ Que des nulles → rien à enregistrer.");
    }
    // Avance le cycle pour le prochain tick (mode config cycle uniquement).
    if (advanceCycleTo !== null) {
      await setCycleCurrent(SUPABASE_URL, SERVICE_KEY, advanceCycleTo);
      console.log(`↻ Cycle : prochaine profondeur = ${advanceCycleTo}.`);
    }
  } else {
    console.log("↩ dry-run : rien écrit.");
  }
}

main().catch((e) => { console.error("✗ balance-worker :", e.message); process.exit(1); });
