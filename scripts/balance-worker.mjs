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

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(join(ROOT, "index.html"), "utf8");

// EXACTEMENT la liste engineFns de labBuildEngineSource (isValid/isV2mode
// exclus : redéfinis dans le préambule à partir du descripteur de format).
const ENGINE_NAMES = [
  "findMaster", "dist", "threatCount", "cloneBS", "applyToClone", "allMoves",
  "labResolveDirs", "labGenericMoves", "legalMoves", "execMove", "evalPosition",
  "evalTrainer", "evalBalanceCurrent", "evalBalanceMobilityFixed",
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
function runScript(script, cfg) {
  const results = [];
  const factory = new Function(
    "postMessage",
    "var onmessage;\n" + script + "\nreturn {get onmessage(){return onmessage;}};",
  );
  const api = factory((msg) => results.push(msg));
  api.onmessage({ data: Object.assign({ cmd: "run" }, cfg) });
  return results;
}

// ── Écriture des résultats dans Supabase (RPC dev_record_balance_result) ──
const EVAL_LABELS = {
  symmetric: "Production actuelle (symétrique)",
  current: "Ancienne formule (asymétrique 1,3/1,6)",
  agdffix: "Variante — ag=df seul",
  mobfix: "Variante — mobilité seule",
};
async function postGame(base, key, payload) {
  const res = await fetch(base + "/rest/v1/rpc/dev_record_balance_result", {
    method: "POST",
    headers: {
      "apikey": key,
      "Authorization": "Bearer " + key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) throw new Error("RPC " + res.status + " : " + (await res.text()).slice(0, 200));
}
// Petit pool de concurrence pour ne pas ouvrir des centaines de requêtes d'un coup.
async function pool(items, size, worker) {
  let i = 0;
  const runners = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (i < items.length) { const idx = i++; await worker(items[idx]); }
  });
  await Promise.all(runners);
}

// ── Config (env, avec valeurs par défaut « prof. 4 / 100 parties ») ──────
const FORMAT_ID = process.env.BW_FORMAT || "standard";
const DEPTH = Math.min(Math.max(+(process.env.BW_DEPTH || 4), 1), 6);
const GAMES = Math.min(Math.max(+(process.env.BW_GAMES || 100), 1), 2000);
const EVAL_KEY = process.env.BW_EVAL || "symmetric";
const OPENING_N = process.env.BW_OPENING !== undefined ? +process.env.BW_OPENING : 4;
const PERSIST = process.env.BW_PERSIST !== "0"; // BW_PERSIST=0 → dry-run local

const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";

async function main() {
  const t0 = Date.now();
  // Avant de dépenser du CPU : si on doit écrire mais que le secret repo n'est
  // pas encore posé, on ne fait RIEN (exit 0, pas d'échec rouge). Le worker
  // s'active tout seul dès que SUPABASE_SERVICE_ROLE_KEY est ajouté.
  if (PERSIST && (!SUPABASE_URL || !SERVICE_KEY)) {
    console.log("⏸ Secret SUPABASE_SERVICE_ROLE_KEY absent → worker en veille. Ajoute-le dans Settings → Secrets and variables → Actions pour l'activer. (Dry-run local : BW_PERSIST=0.)");
    return;
  }
  const format = getFormat(html, FORMAT_ID);
  const script = buildScript(html, format);
  console.log(`▶ balance-worker : ${FORMAT_ID}, prof. ${DEPTH}, ${GAMES} parties, éval ${EVAL_KEY}`);

  const results = runScript(script, {
    batch: GAMES, depthW: DEPTH, depthB: DEPTH, evalKey: EVAL_KEY, openingN: OPENING_N,
  });

  let w = 0, b = 0, draw = 0, plies = 0, n = 0;
  const decisive = [];
  for (const m of results) {
    if (m.type !== "game") continue;
    n++; plies += m.plies;
    if (m.winner === "white") { w++; decisive.push(m); }
    else if (m.winner === "black") { b++; decisive.push(m); }
    else draw++;
  }
  const dec = w + b;
  const wp = dec ? (100 * w / dec).toFixed(1) : "—";
  const se = dec ? 0.5 / Math.sqrt(dec) : 0;
  const sigma = dec ? (Math.abs(w / dec - 0.5) / se).toFixed(2) : "—";
  console.log(`■ ${n} parties (${draw} nulles non comptées) · Blancs ${w} / Noirs ${b} · ${wp}% Blancs · σ=${sigma} · ${(plies / Math.max(n, 1)).toFixed(1)} coups/partie · ${Date.now() - t0} ms`);

  if (!PERSIST) { console.log("↩ dry-run (BW_PERSIST=0) : rien écrit."); return; }

  const testLabel = "srv:" + FORMAT_ID;
  const evalLabel = EVAL_LABELS[EVAL_KEY] || EVAL_KEY;
  await pool(decisive, 8, (m) => postGame(SUPABASE_URL, SERVICE_KEY, {
    p_test_label: testLabel, p_eval_label: evalLabel,
    p_depth_white: DEPTH, p_depth_black: DEPTH,
    p_winner: m.winner, p_plies: m.plies,
  }));
  console.log(`✓ ${decisive.length} parties décisives écrites dans dev_balance_stats (label "${testLabel}").`);
}

main().catch((e) => { console.error("✗ balance-worker :", e.message); process.exit(1); });
