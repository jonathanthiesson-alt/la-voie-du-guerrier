#!/usr/bin/env node
// Convertit tous les sprites de images/skins/<skin>/*.png en .webp à côté
// (les PNG restent en place, on ajoute juste le .webp). Le client choisit au
// runtime : voir la tâche « chargement paresseux » du pipeline d'assets.
//
// Usage : node scripts/convert-skins-webp.mjs
// Nécessite : npm install sharp (devDependency locale, absente du runtime jeu)

import { readdirSync, statSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKINS_DIR = join(__dirname, '..', 'images', 'skins');

const skinDirs = readdirSync(SKINS_DIR, { withFileTypes: true })
  .filter(d => d.isDirectory())
  .map(d => d.name);

let done = 0, skipped = 0, pngBytes = 0, webpBytes = 0;

for (const skin of skinDirs) {
  const dir = join(SKINS_DIR, skin);
  const files = readdirSync(dir).filter(f => extname(f).toLowerCase() === '.png');
  for (const f of files) {
    const src = join(dir, f);
    const dst = src.replace(/\.png$/i, '.webp');
    try {
      const srcSize = statSync(src).size;
      await sharp(src).webp({ quality: 85 }).toFile(dst);
      const dstSize = statSync(dst).size;
      pngBytes += srcSize; webpBytes += dstSize;
      done++;
    } catch (e) {
      console.warn(`Échec ${skin}/${f} :`, e.message);
      skipped++;
    }
  }
}

console.log(`Converti : ${done} fichiers, ${skipped} échecs`);
console.log(`PNG total : ${(pngBytes / 1024 / 1024).toFixed(1)} Mo -> WebP total : ${(webpBytes / 1024 / 1024).toFixed(1)} Mo`);
