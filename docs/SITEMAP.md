# Carte du site — La Voie du Guerrier

> ⚠️ **Fichier généré. Ne pas éditer à la main.**
> `node scripts/sitemap.mjs` le régénère depuis `index.html`.
> Le skill `ui-optimiser` le régénère à chaque modification de menu.

Écrans : **62** · bâtiments : **12** · orphelins : **2** · entrées multiples : **16**

## 1. Le village (entrées joueur)

### Château `chateau` — *online*

| Item | Cible | État |
|---|---|---|
| Campagne | — | bientôt |
| Quêtes du jour | — | bientôt |
| Événements & saisons | `screen-events` | online |

### soleil `soleil` — *DEV*

| Item | Cible | État |
|---|---|---|
| Menu DEV | `screen-dev-hub` | DEV |

### cascade `cascade`

| Item | Cible | État |
|---|---|---|
| Armée des 15 | `showBotGallery()` | actif |

### Maison `maison`

| Item | Cible | État |
|---|---|---|
| Mon Combattant | `screen-profile` | actif |
| Apparence | `screen-piece-skins` | actif |
| Réglages | `screen-settings` | actif |
| Menu DEV | `screen-dev-hub` | DEV |

### Auberge `auberge`

| Item | Cible | État |
|---|---|---|
| Notifications | `openNotificationsModal()` | online |
| Amis | `screen-amis` | online |
| Messagerie | `screen-messaging` | online |
| Forums | — | bientôt |
| News | — | bientôt |
| DevLog (mises à jour) | `screen-devlog` | actif |

### Archives `archives`

| Item | Cible | État |
|---|---|---|
| Statistiques | `screen-profile-stats` | actif |
| Records | `screen-profile-records` | actif |
| Succès | `screen-profile-achievements` | actif |
| Classements | `screen-leaderboard` | online |
| Lore & citations | `screen-citations` | actif |
| Série de connexion | `screen-play` | online |
| Journal d’activité | `screen-play` | online |

### Dojo `dojo` — *online*

| Item | Cible | État |
|---|---|---|
| Défi du jour | `startDailyChallenge()` | actif |
| Adversaires | `screen-opponents` | actif |
| Adversaires notables | `openLocalMode('ai-notable')` | actif |
| Tuto (règles & La Voie du Bousier) | `screen-rules` | actif |
| Karakuri (entraînement) | `screen-training-bot` | actif |

### Arène `arene` — *online*

| Item | Cible | État |
|---|---|---|
| Modes de combat | `screen-play` | online |
| Joueurs en ligne | `screen-online-menu` | online |

### Guilde `guilde` — *online*

| Item | Cible | État |
|---|---|---|
| Guilde | `screen-guild` | online |

### Marché `marche` — *online*

| Item | Cible | État |
|---|---|---|
| Boutique | `screen-shop` | online |

### Port `port`

| Item | Cible | État |
|---|---|---|
| Changer de village | — | bientôt |

### Quitter le village `chariot`

| Item | Cible | État |
|---|---|---|
| Quitter le village | `quitVillageToHome()` | actif |

## 2. Les écrans

| Écran | Atteignable depuis | Retour ↩ |
|---|---|---|
| `account-privacy` | settings | `settings` |
| `amis` | village/auberge | — |
| `arena` | code | — |
| `bot-gallery` | code | `play` |
| `campaign-dojo` | code | `campaigns` |
| `campaign-intro` | code | `campaigns` |
| `campaigns` | local-hub | — |
| `citations` | village/archives | `settings` |
| `clock` | home, local-hub | — |
| `coinflip` | **—** | — |
| `dev-balance` | dev-repertoire | `dev-repertoire` |
| `dev-bots` | dev-hub | `dev-hub` |
| `dev-hub` | village/soleil, village/maison, code | `menu` |
| `dev-lab` | dev-hub | `dev-hub` |
| `dev-learn` | code | — |
| `dev-lore` | dev-hub | `dev-hub` |
| `dev-openings` | dev-repertoire | `dev-repertoire` |
| `dev-repertoire` | **—** | `dev-hub` |
| `dev-tactics` | dev-repertoire | `dev-repertoire` |
| `devlog` | village/auberge, menu, dev-hub, code | `menu` |
| `devparam` | code | — |
| `devparam-v2` | code | — |
| `devrewards` | dev-hub | `dev-hub` |
| `display` | settings | `settings` |
| `events` | village/chateau, menu | `menu` |
| `events-mode` | code | `menu` |
| `fighter-skins` | piece-skins | `piece-skins` |
| `game` | code | — |
| `guild` | village/guilde | `menu` |
| `home` | devlog, code | — |
| `home-logo-cfg` | piece-skins | `piece-skins` |
| `identite` | profile | `profile` |
| `language` | settings | `settings` |
| `leaderboard` | village/archives, online-menu | `play` |
| `league` | village | `play` |
| `local` | code | `menu` |
| `local-hub` | code | — |
| `matchmaking` | code | — |
| `menu` | game, profile, code | `home` |
| `messaging` | village/auberge, code | `menu` |
| `msg-composer` | profile | `profile` |
| `online-auth` | village, code | `home` |
| `online-menu` | village/arene, code | `play` |
| `opponents` | village/dojo, local-hub | — |
| `piece-skins` | village/maison, profile | — |
| `play` | village/archives, village/arene, code | — |
| `profile` | village/maison, home, play, code | — |
| `profile-achievements` | village/archives, profile | `profile` |
| `profile-records` | village/archives, profile | `profile` |
| `profile-stats` | village/archives, profile | `profile` |
| `proto` | home | `home` |
| `proto-rig` | proto | `proto` |
| `public-profile` | code | `online-menu` |
| `reset-password` | code | — |
| `rules` | village/dojo, local-hub, code | `local-hub` |
| `settings` | village/maison, menu | `menu` |
| `shinai` | code | — |
| `shop` | village/marche, menu, code | — |
| `sumo` | events-mode, code | — |
| `tournament` | code | `menu` |
| `training-bot` | village/dojo, local-hub | — |
| `village` | code | — |

## 3. Diagnostics

### 🕳 Écrans sans aucun appelant

- `coinflip`
- `dev-repertoire` *(dev)*

### 🔁 Écrans à entrées multiples (candidats doublon)

Deux chemins vers le même écran ne sont pas toujours un défaut (raccourci
volontaire), mais chacun doit être justifié.

- `clock` ← home, local-hub
- `devlog` ← village/auberge, menu, dev-hub
- `events` ← village/chateau, menu
- `leaderboard` ← village/archives, online-menu
- `menu` ← game, profile
- `opponents` ← village/dojo, local-hub
- `piece-skins` ← village/maison, profile
- `play` ← village/archives, village/arene
- `profile` ← village/maison, home, play
- `profile-achievements` ← village/archives, profile
- `profile-records` ← village/archives, profile
- `profile-stats` ← village/archives, profile
- `rules` ← village/dojo, local-hub
- `settings` ← village/maison, menu
- `shop` ← village/marche, menu
- `training-bot` ← village/dojo, local-hub

### ↩ Retours incohérents

Le bouton retour ramène ailleurs que d'où on vient — le joueur est
« téléporté » dans une branche qu'il n'a pas ouverte. Les retours vers un
ancien hub (`menu`, `play`, `settings`, `local-hub`, `online-menu`, `events-mode`) ne sont pas listés :
`villageInterceptBack()` les détourne déjà vers le retour village.

- `menu` : retour vers `home`, mais on y arrive par game, profile
- `online-auth` : retour vers `home`, mais on y arrive par village

### 🏷 Libellés identiques à deux endroits du village

- soleil › Menu DEV · maison › Menu DEV

_Généré le 2026-08-15._
