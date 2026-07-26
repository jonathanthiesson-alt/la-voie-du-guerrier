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

// ── Config (env, avec valeurs par défaut « prof. 4 / 100 parties ») ──────
const FORMAT_ID = process.env.BW_FORMAT || "standard";
const DEPTH = Math.min(Math.max(+(process.env.BW_DEPTH || 4), 1), 6);
const GAMES = Math.min(Math.max(+(process.env.BW_GAMES || 100), 1), 2000);
const EVAL_KEY = process.env.BW_EVAL || "symmetric";
// Ouverture à 6 demi-coups par défaut (vs 4 côté navigateur) : élargit
// l'espace de parties DISTINCTES (~top-4^6 ≈ des milliers) pour que l'anti-
// doublon ne plafonne pas trop tôt. Les coups restent parmi les meilleurs
// (top-4), donc du jeu plausible, pas des ouvertures au hasard.
const OPENING_N = process.env.BW_OPENING !== undefined ? +process.env.BW_OPENING : 6;
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
  if (!dec) { console.log("○ Aucune partie décisive à enregistrer (que des nulles)."); return; }

  const testLabel = "srv:" + FORMAT_ID;
  const evalLabel = EVAL_LABELS[EVAL_KEY] || EVAL_KEY;

  // Signature (sha1 de la séquence de coups) + DÉDUP LOCAL : une même partie ne
  // compte pas deux fois dans un même run.
  const bySig = new Map();
  for (const m of decisive) {
    const sig = createHash("sha1").update(m.moves || "").digest("hex");
    if (!bySig.has(sig)) bySig.set(sig, { sig, winner: m.winner, plies: m.plies });
  }
  const local = [...bySig.values()];

  // Anti-doublon EN BASE : il ne reste que les parties INÉDITES (jamais vues).
  const fresh = await insertGamesDedup(SUPABASE_URL, SERVICE_KEY, testLabel, evalLabel, DEPTH, local);
  const dupLocal = decisive.length - local.length;
  const dupDb = local.length - fresh.length;
  if (!fresh.length) {
    console.log(`○ ${dec} décisives simulées, 0 inédite (${dupLocal} doublons internes, ${dupDb} déjà en base) → stats inchangées.`);
    return;
  }

  // On n'incrémente les stats QUE par les parties inédites → σ honnête.
  const agg = { games: fresh.length, white: 0, black: 0, plies: 0, under15: 0 };
  for (const g of fresh) {
    if (g.winner === "white") agg.white++; else if (g.winner === "black") agg.black++;
    agg.plies += g.plies || 0; if ((g.plies || 0) < 15) agg.under15++;
  }
  await upsertStats(SUPABASE_URL, SERVICE_KEY, testLabel, evalLabel, DEPTH, agg);
  console.log(`✓ ${fresh.length} parties INÉDITES enregistrées (ignorés : ${dupLocal} doublons internes + ${dupDb} déjà en base) → dev_balance_stats "${testLabel}" prof.${DEPTH}.`);
}

main().catch((e) => { console.error("✗ balance-worker :", e.message); process.exit(1); });
