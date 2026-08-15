#!/usr/bin/env node
// ════════════════════════════════════════════════════════════════════════
//  Carte du site — générateur
//
//  Lit index.html et régénère docs/SITEMAP.md : qui mène où, qui n'est
//  atteignable par personne, qui est atteignable par deux chemins, et quel
//  écran le bouton « retour » ramène.
//
//  Pourquoi un générateur plutôt qu'un doc écrit à la main : une carte tenue
//  à la main ment au bout de trois commits. Celle-ci est DÉRIVÉE du code, donc
//  toujours vraie au moment où on la relance.
//
//  Usage :  node scripts/sitemap.mjs           → réécrit docs/SITEMAP.md
//           node scripts/sitemap.mjs --check   → ne réécrit rien, sort en
//                                                 code 1 si la carte est
//                                                 périmée (utile en garde-fou)
// ════════════════════════════════════════════════════════════════════════
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const HTML = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const OUT  = path.join(ROOT, 'docs', 'SITEMAP.md');

// ─── 1. Les écrans et leur zone HTML ───────────────────────────────────
// Zone = du <div id="screen-X"> jusqu'à son </div> fermant (comptage de
// profondeur). Sert à attribuer un onclick à l'écran qui le contient.
function screenZones(){
  const zones = [];
  const re = /<div id="screen-([a-z0-9-]+)"/g;
  let m;
  while((m = re.exec(HTML))){
    const start = m.index;
    let d = 0, i = start;
    while(i < HTML.length){
      if(HTML.startsWith('<div', i)){ d++; i += 4; continue; }
      if(HTML.startsWith('</div', i)){ d--; i += 5; if(d === 0) break; continue; }
      i++;
    }
    zones.push({ id: m[1], start, end: i, html: HTML.slice(start, i) });
  }
  return zones;
}

// ─── 2. Le village (source de vérité des entrées joueur) ───────────────
function villageBuildings(){
  const start = HTML.indexOf('var VILLAGE_BUILDINGS = [');
  const end   = HTML.indexOf('\n];', start);
  const block = HTML.slice(start, end);
  const out = [];
  // Un bâtiment par « { id:'xxx', ... items:[ ... ] }` ; on découpe sur id:
  const parts = block.split(/\n\s*\{ id:'/).slice(1);
  for(const p of parts){
    const id    = p.slice(0, p.indexOf("'"));
    const label = (p.match(/label:'([^']*)'/) || [,''])[1];
    const bOnline = /^[^[]*online:true/.test(p);
    const bDev    = /^[^[]*dev:true/.test(p);
    const items = [];
    const itemsBlock = p.slice(p.indexOf('items:['));
    for(const im of itemsBlock.matchAll(/\{label:'([^']*)'[^}]*\}/g)){
      const raw = im[0];
      items.push({
        label:  im[1],
        screen: (raw.match(/screen:'([^']*)'/) || [,null])[1],
        fn:     (raw.match(/fn:'([^']*)'/)     || [,null])[1],
        arg:    (raw.match(/arg:'([^']*)'/)    || [,null])[1],
        soon:   /soon:true/.test(raw),
        dev:    /dev:true/.test(raw),
        online: /online:true/.test(raw)
      });
    }
    out.push({ id, label, online: bOnline, dev: bDev, items });
  }
  return out;
}

const zones = screenZones();
const ids   = [...new Set(zones.map(z => z.id))].sort();
const build = villageBuildings();

// ─── 3. Les arêtes ─────────────────────────────────────────────────────
// parents[cible] = [{from, kind}] — d'où on peut arriver sur cet écran.
const parents = {}; ids.forEach(i => parents[i] = []);
const push = (to, from, kind) => { if(parents[to]) parents[to].push({ from, kind }); };

for(const b of build)
  for(const it of b.items)
    if(it.screen) push(it.screen, 'village/' + b.id, it.dev ? 'village-dev' : 'village');

// Liens écran → écran (onclick statiques uniquement : c'est ce que le joueur voit).
const backOf = {};
for(const z of zones){
  // Le bouton retour = premier .tuto-nav-btn de la barre de nav.
  const nav = z.html.match(/class="tuto-nav-btn"[^>]*onclick="showScreen\('([a-z0-9-]+)'\)"/);
  if(nav) backOf[z.id] = nav[1];
  for(const m of z.html.matchAll(/showScreen\('([a-z0-9-]+)'\)/g)){
    if(m[1] === z.id) continue;
    if(backOf[z.id] === m[1] && z.html.indexOf(m[0]) === z.html.indexOf('showScreen(\'' + m[1] + '\')')) continue; // le retour n'est pas un lien
    push(m[1], z.id, 'ecran');
  }
}

// Appels depuis le JS (hors zone d'écran) : navigation programmatique.
const inZone = off => zones.some(z => off >= z.start && off < z.end);
for(const m of HTML.matchAll(/showScreen\('([a-z0-9-]+)'\)/g))
  if(!inZone(m.index)) push(m[1], 'code', 'code');

const uniq = arr => [...new Set(arr)];
const playerParents = id => uniq(parents[id].filter(p => p.kind !== 'code' && p.kind !== 'village-dev').map(p => p.from));

// ─── 4. Les diagnostics ────────────────────────────────────────────────
const DEV_PREFIX = /^(dev-|devparam|devrewards|proto)/;
const orphans    = ids.filter(i => parents[i].length === 0);
const multi      = ids.filter(i => playerParents(i).length >= 2);
// villageInterceptBack() rattrape les retours vers un ANCIEN HUB d'onglet et
// les remplace par le retour village. Un retour vers un hub n'est donc PAS un
// défaut : seuls les retours « contextuels » (vers une page précise) échappent
// à l'interception et peuvent téléporter le joueur. On lit la liste dans le
// code pour que la carte reste vraie si elle change.
const HUBS = (HTML.match(/var HUBS = \[([^\]]*)\]/) || [,''])[1]
  .split(',').map(s => s.trim().replace(/['"]/g, '')).filter(Boolean);
const badBack = ids.filter(i =>
  backOf[i] && HUBS.indexOf(backOf[i]) === -1 &&
  playerParents(i).length > 0 && !playerParents(i).includes(backOf[i]));

// Doublons de libellés dans le village (même intitulé à deux endroits).
const labelSeen = {};
for(const b of build) for(const it of b.items){
  const k = it.label.toLowerCase().replace(/[^a-zà-ÿ]/g, '');
  (labelSeen[k] = labelSeen[k] || []).push(b.id + ' › ' + it.label);
}
const dupLabels = Object.values(labelSeen).filter(v => v.length > 1);

// ─── 5. Rendu ──────────────────────────────────────────────────────────
const L = [];
L.push('# Carte du site — La Voie du Guerrier');
L.push('');
L.push('> ⚠️ **Fichier généré. Ne pas éditer à la main.**');
L.push('> `node scripts/sitemap.mjs` le régénère depuis `index.html`.');
L.push('> Le skill `ui-optimiser` le régénère à chaque modification de menu.');
L.push('');
L.push(`Écrans : **${ids.length}** · bâtiments : **${build.length}** · orphelins : **${orphans.length}** · entrées multiples : **${multi.length}**`);
L.push('');
L.push('## 1. Le village (entrées joueur)');
L.push('');
for(const b of build){
  const tags = [b.online ? 'online' : '', b.dev ? 'DEV' : ''].filter(Boolean).join(', ');
  L.push(`### ${b.label || b.id} \`${b.id}\`${tags ? ' — *' + tags + '*' : ''}`);
  L.push('');
  L.push('| Item | Cible | État |');
  L.push('|---|---|---|');
  for(const it of b.items){
    const cible = it.soon ? '—' : it.screen ? '`screen-' + it.screen + '`' : it.fn ? '`' + it.fn + (it.arg ? "('" + it.arg + "')" : '()') + '`' : '?';
    const et = [it.soon ? 'bientôt' : '', it.dev ? 'DEV' : '', it.online ? 'online' : ''].filter(Boolean).join(' · ') || 'actif';
    L.push(`| ${it.label} | ${cible} | ${et} |`);
  }
  L.push('');
}
L.push('## 2. Les écrans');
L.push('');
L.push('| Écran | Atteignable depuis | Retour ↩ |');
L.push('|---|---|---|');
for(const id of ids){
  const p = uniq(parents[id].map(x => x.from));
  L.push(`| \`${id}\` | ${p.length ? p.join(', ') : '**—**'} | ${backOf[id] ? '`' + backOf[id] + '`' : '—'} |`);
}
L.push('');
L.push('## 3. Diagnostics');
L.push('');
L.push('### 🕳 Écrans sans aucun appelant');
L.push('');
L.push(orphans.length ? orphans.map(o => `- \`${o}\`${DEV_PREFIX.test(o) ? ' *(dev)*' : ''}`).join('\n') : '_Aucun._');
L.push('');
L.push('### 🔁 Écrans à entrées multiples (candidats doublon)');
L.push('');
L.push('Deux chemins vers le même écran ne sont pas toujours un défaut (raccourci');
L.push('volontaire), mais chacun doit être justifié.');
L.push('');
L.push(multi.length ? multi.map(i => `- \`${i}\` ← ${playerParents(i).join(', ')}`).join('\n') : '_Aucun._');
L.push('');
L.push('### ↩ Retours incohérents');
L.push('');
L.push('Le bouton retour ramène ailleurs que d\'où on vient — le joueur est');
L.push('« téléporté » dans une branche qu\'il n\'a pas ouverte. Les retours vers un');
L.push('ancien hub (`' + HUBS.join('`, `') + '`) ne sont pas listés :');
L.push('`villageInterceptBack()` les détourne déjà vers le retour village.');
L.push('');
L.push(badBack.length ? badBack.map(i => `- \`${i}\` : retour vers \`${backOf[i]}\`, mais on y arrive par ${playerParents(i).join(', ')}`).join('\n') : '_Aucun._');
L.push('');
L.push('### 🏷 Libellés identiques à deux endroits du village');
L.push('');
L.push(dupLabels.length ? dupLabels.map(v => '- ' + v.join(' · ')).join('\n') : '_Aucun._');
L.push('');
L.push(`_Généré le ${new Date().toISOString().slice(0, 10)}._`);

const md = L.join('\n') + '\n';

if(process.argv.includes('--check')){
  const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
  const norm = s => s.replace(/_Généré le .*_/, '');
  if(norm(cur) !== norm(md)){ console.error('❌ docs/SITEMAP.md est périmé — relancer node scripts/sitemap.mjs'); process.exit(1); }
  console.log('✅ Carte à jour.');
} else {
  fs.writeFileSync(OUT, md, 'utf8');
  console.log(`✅ docs/SITEMAP.md — ${ids.length} écrans, ${build.length} bâtiments, ${orphans.length} orphelins, ${multi.length} entrées multiples, ${badBack.length} retours incohérents.`);
}
