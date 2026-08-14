#!/usr/bin/env node
// Génère images/skins/skins_manifest.json à partir des dossiers présents dans
// images/skins/. Voir images/skins/README.md pour la convention.
//
// Usage : node scripts/build-skins-manifest.mjs

import { readdirSync, statSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKINS_DIR = join(__dirname, '..', 'images', 'skins');
const MANIFEST_PATH = join(SKINS_DIR, 'skins_manifest.json');

// Les 15 poses obligatoires — un skin incomplet est ignoré (voir README).
const REQUIRED_POSES = [
  '01_attack_haut.png', '02_pare_haut.png',
  '03_attack_milieu.png', '04_pare_milieu.png',
  '05_attack_bas.png', '06_pare_bas.png',
  '07_esquive_haut.png', '08_esquive_milieu.png', '09_esquive_bas.png',
  '10_salut.png', '11_blesse_adversaire.png', '12_touche.png',
  '13_garde_posture.png',
  'nouveau_salut_formel.png', 'pose_blesse_par_terre.png',
];

function defaultLabel(id) {
  return id
    .replace(/[_-]+/g, ' ')
    .trim()
    .split(' ')
    .map(w => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

let existing = {};
if (existsSync(MANIFEST_PATH)) {
  try {
    const prev = JSON.parse(readFileSync(MANIFEST_PATH, 'utf-8'));
    for (const s of prev.skins || []) existing[s.id] = s.label;
  } catch (e) {
    console.warn('Manifeste existant illisible, ignoré :', e.message);
  }
}

const entries = readdirSync(SKINS_DIR, { withFileTypes: true })
  .filter(d => d.isDirectory())
  .map(d => d.name)
  .sort();

const complete = [];
const incomplete = [];

for (const id of entries) {
  const dir = join(SKINS_DIR, id);
  const missing = REQUIRED_POSES.filter(f => !existsSync(join(dir, f)));
  if (missing.length === 0) {
    complete.push({ id, label: existing[id] || defaultLabel(id) });
  } else {
    incomplete.push({ id, missing });
  }
}

const manifest = { generatedAt: new Date().toISOString(), skins: complete };
writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n', 'utf-8');

console.log(`Skins complets : ${complete.length}`);
for (const s of complete) console.log(`  - ${s.id} -> "${s.label}"`);
if (incomplete.length) {
  console.log(`\nSkins ignorés (incomplets) : ${incomplete.length}`);
  for (const s of incomplete) console.log(`  - ${s.id} : manque ${s.missing.join(', ')}`);
}
console.log(`\nÉcrit : ${MANIFEST_PATH}`);
