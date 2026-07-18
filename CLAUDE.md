# La Voie du Guerrier — Contexte projet

> Ce fichier est lu automatiquement par Claude Code. Il contient le strict
> nécessaire. Les détails sont dans `docs/`.

---

## Le projet en une phrase

Jeu de plateau abstrait 5×5 de type échecs/shogi, thème samouraï féodal
teinté de cyberpunk, jouable en ligne avec comptes et multijoueur temps réel.

- **Nom** : La Voie du Guerrier (« La Voie du Bousier » en interne)
- **Version actuelle** : ONLINE alpha **V0.17.0**
- **Fichier unique** : `index.html` (~1,2 Mo, HTML + CSS + JS vanilla, tout dedans)
- **Backend** : Supabase (auth, Postgres, temps réel, RLS)
- **Pas de build, pas de framework, pas de bundler.** On édite `index.html` directement.

## L'équipe

| Qui | Rôle |
|---|---|
| **Jonathan Thiesson** (pseudo **Wurmz**) | Développement, application. Travaille chez Hermès (maroquinerie). C'est lui l'interlocuteur. |
| **Thomas Prissette** | Graphismes, direction artistique |
| **Musashi** | Second administrateur du jeu |

---

## ⚠️ CONVENTIONS DE TRAVAIL — À RESPECTER STRICTEMENT

Ces règles viennent de bugs réels qui ont coûté des heures. Ne pas les sauter.

### 1. Vérifier la syntaxe après CHAQUE édition

```bash
python3 -c "
import re
html=open('index.html',encoding='utf-8').read()
js='\n;\n'.join(re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',html,re.DOTALL))
open('/tmp/combined.js','w',encoding='utf-8').write(js)
"
node --check /tmp/combined.js
```

### 2. 🔴 VÉRIFIER LA PROFONDEUR D'ACCOLADES DES NOUVELLES FONCTIONS

**C'est LE bug récurrent du projet.** `node --check` valide une fonction
imbriquée (c'est légal en JS), mais elle devient **locale**, donc invisible
depuis le HTML (`onclick="maFonction()"` ne la trouve pas) et les gardes
`typeof maFonction === 'function'` renvoient `false` → **échec totalement muet**.

C'est arrivé deux fois : tout le système WurmzSkin s'était retrouvé enfermé
dans `toggleSetting()`, et `toggleAntiRetourHint` y était piégée depuis
longtemps (la case anti-retour ne fonctionnait pas du tout).

**Après toute nouvelle fonction, vérifier qu'elle est bien au niveau global :**

```bash
python3 -c "
import re
html=open('index.html',encoding='utf-8').read()
js='\n;\n'.join(re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',html,re.DOTALL))
for fn in ['maNouvelleFonction','uneAutre']:
    i=js.find('function '+fn+'(')
    if i<0: print(fn,'INTROUVABLE'); continue
    d=js[:i].count('{')-js[:i].count('}')
    print(fn, 'profondeur', d, '=> GLOBAL' if d<=0 else '=> IMBRIQUÉE (BUG)')
"
```

Attention en particulier à `toggleSetting(k){...}` qui s'étend sur des dizaines
de lignes : c'est un piège classique pour les insertions.

### 3. i18n — TOUJOURS le même nombre de clés

`const LANGS` contient `fr`, `en`, `ja`. **Actuellement 203 clés chacune.**
Ajouter une clé quelque part = l'ajouter dans les trois.

```bash
python3 -c "
html = open('index.html', encoding='utf-8').read()
start = html.index('const LANGS={')
def fb(name, fi):
    i=html.index(name+':{',fi); j=html.index('{',i); d=0; k=j
    while True:
        c=html[k]
        if c=='{':d+=1
        elif c=='}':
            d-=1
            if d==0:break
        k+=1
    return html[j+1:k]
import re
for lang in ['fr','en','ja']:
    print(lang, len(re.findall(r'^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:', fb(lang,start), re.MULTILINE)))
"
```

### 4. Pas de fonction dupliquée

```bash
grep -c "function maFonction(" index.html   # doit valoir 1
```

### 5. Commentaires en français

Le code est commenté en français, et les commentaires **expliquent le
pourquoi**, pas le quoi. Beaucoup de commentaires existants documentent des
pièges — ne pas les supprimer.

---

## ⚠️ PIÈGES SUPABASE (vécus)

### L'éditeur SQL exécute tout en UNE transaction
Si la **dernière** instruction échoue, **tout est annulé** — y compris les
`alter table` du début. Un script à moitié passé n'existe pas : soit tout
passe, soit rien. Toujours revérifier après une erreur.

### `create or replace view` ne peut pas réordonner les colonnes
Erreur `42P16`. Il faut `drop view if exists ... ;` **avant** de recréer.

### `create or replace function` ne peut pas changer le type de retour
Il faut `drop function if exists nom(types);` **avant**.

### 🔴 Ne jamais nommer une colonne toute neuve dans un `select` critique
**Cause d'un bug majeur** : ajouter `wurmz_skin` à la liste des colonnes du
`select` de matchmaking a cassé **tout le lancement de partie** tant que le
script SQL n'était pas exécuté (la colonne n'existait pas → requête en erreur).

**Dans les chemins critiques (matchmaking, entrée en partie, profil), utiliser
`select('*')`** : ça ne peut pas échouer sur une colonne manquante.

### RLS : une table avec RLS activée et ZÉRO politique est totalement bloquée
En lecture **et** en écriture, silencieusement. Le bouton « Run and enable RLS »
de Supabase a déjà cassé le matchmaking de cette façon.
`docs/SQL_MIGRATIONS.md` contient une requête de diagnostic.

**Exception normale** : `admin_audit_log` est en « RLS sans politique » **par
conception** — on n'y accède que via des RPC `SECURITY DEFINER`.

### Tous les RPC d'administration vérifient le rôle côté serveur
Via `is_admin_user()`. Le rôle vient de la colonne `profiles.is_admin`, **pas**
d'une liste de pseudos en dur (usurpable).

---

## Où on en est

**AXE 1 — Stabilisation et tests en conditions réelles.** ← *focus actuel*

Le programme de compétitivité (8 phases, calqué sur chess.com) est **terminé** :
navigation, boucle quotidienne, entraînement, adversaires IA, compétition
(ligue/tournois/classements/guildes), social, économie/saisons, télémétrie.

**Tournois : résolus et validés en conditions réelles (2026-07-14).**
Automatisation serveur complète (pg_cron), clôture des inscriptions réservée
au créateur, forfaits automatiques. **Prochain sujet : les guildes** (test à
2 comptes). Voir `docs/TESTING.md` pour les protocoles et les leçons apprises.

Voir `docs/ROADMAP.md` pour les 6 axes.

---

## Fichiers de référence

| Fichier | Contenu |
|---|---|
| `docs/ROADMAP.md` | Les 6 axes, qui fait quoi, où on en est |
| `docs/TESTING.md` | **Le bug tournoi en cours**, protocoles de test AXE 1 |
| `docs/ARCHITECTURE.md` | Points d'entrée du code, variables clés, écrans |
| `docs/GAME_DESIGN.md` | Règles des modes, économie, monnaies |
| `docs/SQL_MIGRATIONS.md` | Ordre des scripts, lesquels sont passés, diagnostic RLS |
