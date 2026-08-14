// ════════════════════════════════════════════════════════════════════════
// mine-puzzles.mjs — extrait des défis « mat forcé en 2-3 coups » depuis les
// vraies parties jouées (table game_history), et les insère dans
// mined_puzzles (voir sql_a_executer/mined_puzzles.sql).
//
// Réutilise le moteur EXTRAIT d'index.html (même technique que
// scripts/bot-army.mjs et scripts/balance-worker.mjs — source vivante, zéro
// dérive) : allMoves/execMove/legalMoves + le décodeur de notation.
//
// Recherche ET/OU (mate forcé) : pour chaque position candidate (fin de
// partie décisive), on cherche un coup du camp gagnant tel que, QUELLE QUE
// SOIT la réplique adverse, le camp gagnant peut encore mater dans le budget
// restant. Une fois trouvée, UNE ligne de réplique adverse (parmi toutes,
// puisqu'elles perdent toutes) est figée dans le défi livré — le lecteur de
// leçon existant (steps scriptés) n'a pas besoin d'être modifié.
//
// Usage : SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/mine-puzzles.mjs [--dry]
// ════════════════════════════════════════════════════════════════════════

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createClient } from "@supabase/supabase-js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(join(ROOT, "index.html"), "utf8");
const DRY = process.argv.includes("--dry");

const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";

const ENGINE_NAMES = [
  "findMaster", "dist", "threatCount", "cloneBS", "applyToClone", "allMoves",
  "labResolveDirs", "labGenericMoves", "labPieceValue", "legalMoves", "execMove",
  "bfSameUnit",
  // Décodage de notation (voir index.html, section "HISTORIQUE DES PARTIES").
  "pieceNotationCode", "parseMoveToken", "buildStandardStartBoard",
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

// Format standard (5x5, Rempart V2) — même prélude que bot-army/balance-worker.
const FORMAT = { rows: 5, cols: 5, v2: true, sumo: false, voids: [] };
const prelude = [
  "var FORMAT=" + JSON.stringify(FORMAT) + ";",
  "var VOID_STD=new Set(FORMAT.voids||[]);",
  'function isValid(r,c){return r>=0&&r<(FORMAT.rows||5)&&c>=0&&c<(FORMAT.cols||5)&&!VOID_STD.has(r+","+c);}',
  "var DO=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1}];",
  "var DA=[{dr:-1,dc:0},{dr:1,dc:0},{dr:0,dc:-1},{dr:0,dc:1},{dr:-1,dc:-1},{dr:-1,dc:1},{dr:1,dc:-1},{dr:1,dc:1}];",
  "var PP={totalCaptures:0,totalPushes:0};",
  "function playSound(){} function haptic(){}",
  "var G={simulating:true,rows:5,cols:5,sumoMode:false,pieceDefs:null,turn:null,lastPush:null,lastMoved:null,lastMovedByColor:{white:null,black:null}};",
  "function isV2mode(){return true;}",
].join("\n");
const body = ENGINE_NAMES.map((n) => extractFn(html, n)).join("\n\n");
// Même technique que scripts/bot-army.mjs (makeMover) : new Function plutôt
// qu'un faux module — le code extrait référence des globales (G, PP, DO,
// DA...) via closure, pas via des exports explicites. setG/getG donnent un
// accès en lecture/écriture à CE G-là depuis l'extérieur (execMove le mute
// en place, getG().lastMoved etc. reflètent donc bien le coup qui vient
// d'être joué).
const factory = new Function(prelude + "\n\n" + body
  + "\n\nreturn { allMoves, execMove, legalMoves, parseMoveToken, buildStandardStartBoard, setG: function(patch){ Object.assign(G, patch); }, getG: function(){ return G; } };");
const engine = factory();
const { allMoves, execMove, legalMoves, parseMoveToken, buildStandardStartBoard, setG, getG } = engine;

function cloneBoard(b) { return b.map(row => row.map(p => p ? Object.assign({}, p) : null)); }
function cloneLMBC(x) { return { white: x && x.white ? Object.assign({}, x.white) : null, black: x && x.black ? Object.assign({}, x.black) : null }; }

// Rejoue une notation complète, renvoie la liste des positions
// {board,stacks,lastMoved,lastPush,lastMovedByColor,turnNext} après chaque coup.
function replay(notation) {
  var board = buildStandardStartBoard();
  var stacks = Array.from({ length: 5 }, () => Array(5).fill(null));
  var lastMoved = null, lastPush = null, lastMovedByColor = { white: null, black: null };
  var out = [];
  var tokens = (notation || "").split(";").filter(Boolean);
  for (const token of tokens) {
    const parsed = parseMoveToken(token);
    if (!parsed) return out; // notation corrompue : on garde ce qu'on a
    const moves = legalMoves(parsed.color, board, stacks, { r: parsed.fr, c: parsed.fc }, lastMoved, lastPush);
    const mv = moves.find(m => m.r === parsed.tr && m.c === parsed.tc);
    if (!mv) return out; // coup non reconnu : on arrête le replay ici (prudence)
    setG({ board, stacks, lastMoved, lastPush, lastMovedByColor, simulating: true });
    const won = execMove(parsed.fr, parsed.fc, parsed.tr, parsed.tc, mv);
    const g = getG();
    lastMoved = g.lastMoved; lastPush = g.lastPush; lastMovedByColor = g.lastMovedByColor;
    out.push({
      board: cloneBoard(board), stacks: cloneBoard(stacks),
      lastMoved: lastMoved ? Object.assign({}, lastMoved) : null,
      lastPush: lastPush,
      lastMovedByColor: cloneLMBC(lastMovedByColor),
      sideJustMoved: parsed.color, won,
    });
  }
  return out;
}

// Recherche ET/OU d'un mat forcé en <= budget coups du camp `side`.
// Renvoie { move, replyLine } où replyLine est null (mat immédiat) ou
// { oppMove, sub } (une ligne de réplique adverse, elle-même perdante).
function solveMate(board, stacks, lastMoved, lastPush, lastMovedByColor, side, budget) {
  const moves = allMoves(side, board, stacks, lastMoved, lastPush, lastMovedByColor);
  for (const mv of moves) {
    const b2 = cloneBoard(board), s2 = cloneBoard(stacks);
    setG({ board: b2, stacks: s2, lastMoved, lastPush, lastMovedByColor: cloneLMBC(lastMovedByColor), simulating: true });
    const won = execMove(mv.fr, mv.fc, mv.tr, mv.tc, mv.action);
    const g1 = getG();
    const nLM = g1.lastMoved, nLP = g1.lastPush, nLMBC = g1.lastMovedByColor;
    if (won) return { move: mv, replyLine: null };
    if (budget <= 1) continue;
    const opp = side === "white" ? "black" : "white";
    const oppMoves = allMoves(opp, b2, s2, nLM, nLP, nLMBC);
    if (!oppMoves.length) continue; // cas ambigu (plus aucun coup adverse) : on écarte par prudence
    let forced = true, chosenReply = null;
    for (const omv of oppMoves) {
      const b3 = cloneBoard(b2), s3 = cloneBoard(s2);
      setG({ board: b3, stacks: s3, lastMoved: nLM, lastPush: nLP, lastMovedByColor: cloneLMBC(nLMBC), simulating: true });
      const oppWon = execMove(omv.fr, omv.fc, omv.tr, omv.tc, omv.action);
      if (oppWon) { forced = false; break; }
      const g2 = getG();
      const sub = solveMate(b3, s3, g2.lastMoved, g2.lastPush, g2.lastMovedByColor, side, budget - 1);
      if (!sub) { forced = false; break; }
      if (!chosenReply) chosenReply = { oppMove: omv, sub }; // 1re réplique testée = celle qu'on scripte
    }
    if (forced) return { move: mv, replyLine: chosenReply };
  }
  return null;
}

// Convertit une position + solution ET/OU en objet "leçon" (même format
// que les leçons de campagne écrites à la main : setup + steps scriptés).
function boardToSetup(board) {
  const setup = [];
  for (let r = 0; r < 5; r++) for (let c = 0; c < 5; c++) {
    const p = board[r][c];
    if (p) setup.push({ type: p.type, color: p.color, r, c });
  }
  return setup;
}
function solutionToSteps(solution, mateDepth) {
  const steps = [];
  let node = solution, depth = mateDepth;
  while (node) {
    steps.push({ by: "player", fr: node.move.fr, fc: node.move.fc, tr: node.move.tr, tc: node.move.tc,
      success: depth === 1 ? "Le coup gagnant !" : "Bien vu — continuez la poursuite !" });
    if (!node.replyLine) break;
    steps.push({ by: "opponent", fr: node.replyLine.oppMove.fr, fc: node.replyLine.oppMove.fc,
      tr: node.replyLine.oppMove.tr, tc: node.replyLine.oppMove.tc });
    node = node.replyLine.sub;
    depth--;
  }
  return steps;
}

// Auto-test hors-ligne (aucun accès réseau) : rejoue une courte notation
// connue et vérifie qu'une position de mat en 1 fabriquée à la main est bien
// détectée — sert à valider le câblage moteur avant de lancer une vraie
// extraction. `node scripts/mine-puzzles.mjs --selftest`.
function selftest() {
  const start = buildStandardStartBoard();
  console.log("Position de départ : ", start[0].map(p => p ? p.type[0] : ".").join(""));
  const emptyStacks = Array.from({ length: 5 }, () => Array(5).fill(null));
  const moves0 = allMoves("white", start, emptyStacks, null, null, { white: null, black: null });
  console.log("Coups légaux Blancs au départ :", moves0.length, "(attendu > 0)");
  // Position fabriquée : Combattant noir isolé en (4,2), épée blanche prête à
  // capturer sans échappatoire (juste pour valider le câblage execMove/won).
  const board = Array.from({ length: 5 }, () => Array(5).fill(null));
  board[3][2] = { type: "sword", color: "white" };
  board[4][2] = { type: "epeiste", color: "black" };
  const stacks = Array.from({ length: 5 }, () => Array(5).fill(null));
  const sol = solveMate(board, stacks, null, null, { white: null, black: null }, "white", 1);
  console.log("Mat en 1 détecté :", !!sol, sol ? JSON.stringify(sol.move) : "(rien trouvé — vérifier le câblage)");
}
if (process.argv.includes("--selftest")) { selftest(); process.exit(0); }

async function main() {
  if (!SUPABASE_URL || !SERVICE_KEY) { console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY manquants."); process.exit(1); }
  const supa = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: games, error } = await supa.from("game_history")
    .select("id,winner,moves_notation").in("winner", ["white", "black"])
    .not("moves_notation", "is", null);
  if (error) { console.error(error); process.exit(1); }
  console.log("Parties décisives:", games.length);

  const found = [];
  let numCounter = 1;
  for (const g of games) {
    const positions = replay(g.moves_notation);
    if (!positions.length) continue;
    // On ne cherche que dans les 8 derniers coups (les mats forcés y sont
    // les plus probables ; ça borne aussi le temps de calcul).
    const start = Math.max(0, positions.length - 9);
    for (let i = start; i < positions.length - 1; i++) {
      const pos = positions[i];
      const side = pos.sideJustMoved === "white" ? "black" : "white"; // au trait après ce coup
      if (side !== g.winner) continue; // on ne s'intéresse qu'aux positions où le VAINQUEUR est au trait
      for (const depth of [2, 3]) {
        const sol = solveMate(pos.board, pos.stacks, pos.lastMoved, pos.lastPush, pos.lastMovedByColor, side, depth);
        if (sol) {
          const steps = solutionToSteps(sol, depth);
          const lesson = {
            num: numCounter, title: "Défi miné n°" + numCounter,
            briefing: "Une vraie partie, une faille réelle. À vous de la trouver — mat en " + depth + " coup" + (depth > 1 ? "s" : "") + ".",
            setup: boardToSetup(pos.board),
          };
          lesson.steps = steps;
          found.push({ lesson, mate_depth: depth, source_game_id: g.id });
          numCounter++;
          break; // un seul défi par position (on essaie 2 avant 3, le plus court gagne)
        }
      }
    }
  }
  console.log("Défis trouvés:", found.length);
  if (DRY || !found.length) { console.log(JSON.stringify(found.slice(0, 3), null, 2)); return; }

  const rows = found.map(f => ({ lesson: f.lesson, mate_depth: f.mate_depth, difficulty: f.mate_depth + 1, source_game_id: f.source_game_id }));
  const { error: insErr } = await supa.from("mined_puzzles").insert(rows);
  if (insErr) { console.error("Insertion échouée:", insErr); process.exit(1); }
  console.log("Insérés:", rows.length);
}

main();
