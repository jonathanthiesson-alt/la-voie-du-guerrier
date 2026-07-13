# Design du jeu — règles & économie

---

## Le jeu lui-même

Plateau **5×5**, mode « Rempart V2 ».

**Pièces** :
- **Épéiste / Combattant** — la pièce à protéger
- **Pion Épée**
- **Bouclier**

**Cadences** : 3s / 5s / 10s **par coup** (le minuteur se réinitialise à chaque
tour). **Chaque cadence a son propre ELO** (`elo_3s`, `elo_5s`, `elo_10s`) —
être fort en 10s ne classe pas en 3s.

---

## 💰 ÉCONOMIE — la règle centrale

> ### 🔴 Le Koku (石) ne se gagne JAMAIS en jouant.

C'est la **monnaie premium**. Elle n'entre au portefeuille que par :
1. La **conversion de fin de saison** (tous les 3 mois)
2. Les **achats intégrés**

Vérifié : zéro crédit de Koku dans le code de gameplay. **Ne pas réintroduire.**

## Les monnaies

| Monnaie | Mode | Gains |
|---|---|---|
| 🌿 **Shiso** | Matchmaking | Victoire +2 · Défaite +1 |
| ⚔ **Tamashii** | Arène | 4 / 3 / 2 selon la cadence (3s / 5s / 10s) |
| 🏮 **Mon** | Tournoi | Victoire +2 · Nulle +1 · Podium 20/12/6 |
| 🐉 **Ryu** | Guilde | Contribution collective |
| 🌸 **Hanafuda** | Événements | Selon l'événement |
| 🍄 **Shiitake** | **Transverse — le quotidien** | Défi du jour +2 · Chaque quête +1 · 1re victoire du jour +1 |
| 石 **Koku** | **Premium** | ⛔ Jamais en jouant |

Le **Shiitake** (« le champignon des moines », cultivé dans les monastères)
récompense la **constance**, pas la performance. C'est la monnaie de la boucle
de rétention.

`shopState = { koku, ownedPacks, shiso, tamashii, mon, ryu, hanafuda, shiitake }`
`CURRENCY_LORE` contient l'origine historique de chaque monnaie.

## Saisons

Tous les **3 mois** : chaque monnaie de mode est convertie en Koku selon **son
propre taux** (paramétrable depuis le panneau admin), puis remise à zéro.

## Paliers

Sur chaque barre de progression de mode : **30 / 75 / 150** (paramétrables).
Une fois atteints, ils deviennent **cliquables** (halo doré) → réclamation →
bonus **dans la monnaie du mode** (jamais du Koku) + éventuel déblocage de
contenu.
Fonctions : `renderModeProgressBar()`, `claimMilestone()`, `_claimedMilestones`.

---

## 🏆 TOURNOIS — règles complètes

### Format : système suisse
Pas d'élimination. **Tout le monde joue toutes les rondes.**

### Appariement
À chaque ronde, les joueurs sont triés par **score décroissant** (départage :
nombre de victoires) et appariés **entre voisins** : 1er vs 2e, 3e vs 4e…
Plus le tournoi avance, plus on affronte des joueurs de son niveau réel.

### Nombre de rondes — ADAPTATIF
`ceil(log₂(N))` où N = nombre d'inscrits, plafonné par la cadence.
8 inscrits → 3 rondes. Figé au lancement de la 1re ronde.

### Plafonds par cadence
Calibrés pour **~20 min** de tournoi (au-delà, les joueurs décrochent).
**Les rondes se jouent en parallèle** → la durée dépend du nombre de RONDES,
pas du nombre de joueurs.

| Cadence | Max joueurs | Rondes max | Délai/ronde | Durée totale |
|---|---|---|---|---|
| 3s | **64** | 6 | 3 min | ~18 min |
| 5s | **32** | 5 | 4 min | ~20 min |
| 10s | **16** | 4 | 7 min | ~28 min |

### Couleurs
Alternance par **parité de ronde** : le mieux classé de la paire a les Blancs
aux rondes impaires, les Noirs aux rondes paires.

### Bye
Nombre impair de joueurs → le **dernier du classement** est exempté et reçoit
**1 point** automatiquement.

### Score
| Résultat | Points |
|---|---|
| Victoire | 1 |
| Nulle | 0,5 |
| Défaite | 0 |
| Bye | 1 |

### Délai & abandon
- Chaque ronde a un **délai limite** (compte à rebours affiché).
- Délai écoulé + adversaire absent → **réclamer la victoire par forfait**.
- Personne ne s'est présenté → **double abandon**, 0 point.
- **Un abandonniste est exclu des rondes suivantes**, ne peut plus être apparié,
  et **ne monte pas sur le podium** (grisé au classement, mention « abandon »).
- **Le tournoi continue sans lui.** S'il ne reste plus assez de joueurs actifs,
  il se clôt proprement et distribue le podium.

### Nettoyage automatique
`tournament_cleanup()` est appelé à chaque affichage de la liste des tournois.
Il solde les rondes expirées, enchaîne la ronde suivante, clôt les tournois sans
joueurs actifs, et abandonne ceux créés il y a plus de 2 h sans être lancés.
**Pas de cron nécessaire.** (Sans ça, un tournoi tournait toute la nuit.)

---

## 🏅 LIGUE

- **Hebdomadaire**, remise à zéro le dimanche.
- Groupes d'environ **50 joueurs** de la même division.
- 7 divisions : 🪵 Bois → 🪨 Pierre → 🥉 Bronze → 🥈 Argent → 🥇 Or → 🟢 Jade → 🐉 Dragon
- **Points uniquement sur VICTOIRE** en matchmaking : 3s→3 · 5s→2 · 10s→1
- 🔴 **Une défaite ne retire JAMAIS de points.** Double anti-tanking : points
  positifs seulement **et** classement relatif au groupe. Perdre exprès ne sert
  à rien.
- Les **3 premiers montent**, les **3 derniers descendent**.

---

## 🛡 GUILDES

- Adhésion : 🔓 **ouverte** ou 🔒 **sur demande** (le chef approuve)
- **20 membres maximum**
- Rôles : **chef 👑** / membre. Si le chef part → promotion automatique du plus
  ancien membre.
- **Ryu collectif** cumulé par la guilde → classement des guildes
- **Défis inter-guildes**
- Un joueur ne peut appartenir qu'à **une seule guilde**.

---

## ⚔ ARÈNE

Match en **3 manches (BO3)**. Premier à 2 manches gagnées.
Récompenses inversement proportionnelles à la cadence : 3s→4 ⚔ · 5s→3 ⚔ · 10s→2 ⚔

---

## ⚡ MATCHMAKING

- **Fenêtre ELO élargissante** : on part à ±100, puis +100 points toutes les
  5 secondes, jusqu'à ±3000 (accepte tout le monde).
  🔴 **Une fenêtre fixe à ±100 empêchait tout appariement** entre joueurs
  éloignés — la recherche tournait dans le vide sans erreur. Cause d'un bug
  majeur, ne pas revenir en arrière.
- ELO séparé par cadence.
- Les boutons de cadence **restent cliquables** pendant la recherche (les
  désactiver rendait « Partie rapide → 10s » totalement inopérant).

---

## 🎯 ENTRAÎNEMENT

- **Défis libres** tirés des leçons de campagne → **rating de défi séparé de
  l'ELO** (progresser sans risquer son classement).
- **Défi Rush** : 3 minutes, 3 erreurs max, enchaîner un maximum de défis.
  Meilleur score enregistré + classement.

---

## 🍄 BOUCLE QUOTIDIENNE

- **Défi du jour** : une position unique, la même pour tous. 1 tentative/jour. +2 🍄
- **3 quêtes** renouvelées chaque jour. +1 🍄 chacune.
- **1re victoire du jour** (en ligne, arène ou bot) : +1 🍄
- **Série (streak)** : **48 h de grâce** — un jour manqué ne casse pas la série
  immédiatement. Record conservé.

---

## 🎭 MAÎTRES IA

6 adversaires à personnalité distincte. Les battre donne leur **sceau 🛡**
(affiché sur le profil, X/6). **Aucune monnaie** — c'est un trophée, pas un
revenu. Une victoire contre un bot compte pour la 1re victoire du jour (+1 🍄).
