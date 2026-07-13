# Architecture du code

Tout est dans `index.html` (~1,2 Mo). Pas de build. Les sections sont délimitées
par de gros commentaires en bannière (`// ═══ NOM DE SECTION ═══`).

---

## Variables globales à connaître

| Variable | Rôle | ⚠️ Piège |
|---|---|---|
| `G` | État de la partie en cours (board, stacks, turn, bottomColor…) | — |
| `currentOnlineGameId` | **LA vraie** variable d'id de partie en ligne | `G.onlineGameId` existe mais n'est **JAMAIS** assignée (uniquement remise à `null`). Ne pas s'y fier. |
| `currentUser` | `{id, pseudo}` du compte connecté | `null` si hors ligne |
| `_myPseudo` | Pseudo cloud mémorisé à la connexion | Fiable même si `currentUser` est null |
| `_isAdmin` | Rôle admin, vient de `profiles.is_admin` | — |
| `myColorOnline` | `'white'` ou `'black'` | — |
| `settings` | Réglages de partie (timerSeconds…) | — |
| `userPrefs` | Préférences persistées en localStorage | — |
| `pieceSkins` | Skins par rôle (`player1`, `onlineWhite`, `onlineBlack`…) | — |
| `shopState` | Soldes des 7 monnaies | — |

---

## Rendu des pièces — le chemin complet

```
renderBoard()
  └─ mkPiece(piece, cs, isStackBottom, topType, col)
       ├─ getSkinRole(color)            → 'player1' | 'onlineWhite' | 'onlineBlack' | 'opponent' | 'player2'
       ├─ getPieceSkin(role, type, piece, col)   ← 🔑 POINT D'ENTRÉE UNIQUE
       └─ makePieceSVG(skin, sz, piece)  → gère kanji / b64 (<img>) / svg
```

**`getPieceSkin()` est le seul endroit où un skin est résolu.** Toute
personnalisation d'apparence passe par là (c'est là qu'est branché le WurmzSkin).

---

## Partie en ligne — le flux

```
createOnlineGame(whiteId, blackId, timerSeconds)
  ├─ settings._onlineBottomColor = …
  ├─ initGame()                          ← construit G.board via le moteur LOCAL
  ├─ insert dans online_games
  └─ enterOnlineGame(...)

enterOnlineGame(gameId, whitePlayerId, gameState, turn, timerSeconds)
  ├─ closeMyOtherActiveOnlineGames(gameId)   ⚠️ ferme les autres parties actives
  ├─ currentOnlineGameId = gameId            ← 🔑 pas G.onlineGameId !
  ├─ showScreen('game')
  ├─ classList.add('board-hidden')           ← plateau MASQUÉ
  ├─ renderBoard()
  ├─ subscribeToOnlineGame(gameId)
  └─ markReadyAndWaitForOpponent(gameId)

markReadyAndWaitForOpponent(gameId)
  ├─ update online_games SET ready_white|ready_black = true
  ├─ sonde l'autre colonne toutes les 500 ms
  └─ quand les DEUX sont prêts → beginOnlineMatchStart()
                                   └─ décompte, plateau affiché, minuteur, musique
```

> 🔴 **Si le plateau reste vide avec « En attente de l'adversaire… », c'est que
> la poignée de main `ready_white`/`ready_black` n'aboutit pas.** Le plus souvent
> parce que les deux joueurs ne sont pas dans la même ligne `online_games`.

---

## Temps réel Supabase

Modèle de référence : **`subscribeToChallenges()`**. Tous les abonnements
suivent ce patron et sont poussés dans `onlineSubscriptions[]` pour être
nettoyés à la déconnexion.

Abonnements actifs :
- `subscribeToChallenges()` — défis entre joueurs
- `subscribeToTournamentGames()` — partie de tournoi prête (popup + notif)
- `subscribeToDirectMessages()` — messagerie
- `subscribeToOnlineGame(gameId)` — coups de la partie en cours

---

## Table `notifications` — schéma réel

```
user_id, type, title, body, ref_id, ref_type, read, payload (jsonb), created_at
```

⚠️ `payload` a été ajouté tardivement. Le champ `type` peut avoir une contrainte
— **ne jamais faire dépendre une opération critique de l'insertion d'une
notification** (ça a cassé l'attachement des parties de tournoi).

---

## Écrans (~46)

`showScreen(id)` bascule d'écran. Attention : il contient un **garde-fou**
(`FEATURE_SCREENS` + `guardFeature()`) qui bloque l'accès à un mode désactivé
depuis le panneau admin.

```
home · menu · play · settings · display · piece-skins (Apparence) · language
local · campaigns · game · profile · public-profile · coinflip · rules
devlog · identite · online-auth · online-hub · matchmaking · arena · amis
training · opponents · tournament · guild · events-mode · league · messaging
shop · events · online-menu · leaderboard · devrewards (panneau admin)
```

**Hooks d'affichage** : `_pieceSkinShowHook(id)` déclenche des initialisations
quand certains écrans s'ouvrent.

---

## Panneau d'administration

Écran `screen-devrewards`, bouton violet visible si `isDevUser()`.
Sections dans `ADMIN_SECTIONS`, routage par `setAdminSection(sec)`.

| Section | Fonctions clés |
|---|---|
| 📊 Stats | `renderAdminStats()` / RPC `admin_live_stats` |
| 👥 Joueurs | `renderAdminPlayers()`, `searchPlayers()`, `openPlayerAdmin()`, `grantCurrency()`, `setPlayerStat()`, `banPlayer()`, `mutePlayer()`, `resetPlayer()`, `toggleAdmin()` |
| 🚨 Modération | `renderAdminModeration()`, `resolveReport()` |
| ⚡ Live-ops | `toggleMaintenance()`, `setAnnouncement()`, `toggleFeature()`, `previewWurmzMessage()` |
| 🎁 Récompenses | `renderAdminRewards()`, `saveDevReward()`, `addDevMilestone()` |
| 💱 Conversion | `runSeasonConversion()`, `previewConversion()` |
| 📅 Événements | `saveEvent()`, `deleteEvent()` |
| 📜 Journal | `renderAdminAudit()` — traçabilité de toute action admin |

**Contrôles d'accès joueur** : `enforceAccessControls()` (appelé à la connexion)
→ bannissement (`showBlockingScreen`), maintenance, annonce globale.

---

## WurmzSkin (skin exclusif à Wurmz)

- `WURMZ_SKIN` — chemins des 9 PNG dans `images/wurmz/`
- `canUseWurmzSkin()` / `canSeeWurmzToggle()` / `isWurmzSkinActive()`
- `buildWurmzSkinFor(role, type, piece, col)` — mémorise `_wurmzRole`
- Override dans `getPieceSkin()` : rôle `player1` **et** rôles distants
  (`onlineWhite`/`onlineBlack`) si le drapeau `profiles.wurmz_skin` est vrai
- **Rotation** : 180° uniquement sur **mes propres pièces** (`_wurmzRole === 'player1'`),
  XOR avec `userPrefs.wurmzFlip` (bouton ↻ inverseur)
- **Couverture totale** : `iszFactor = 1` + classe `.wurmz-full` qui neutralise
  fond, bordure et ombre du pion standard (le médaillon **est** la pièce)
- **Avatar dev** : `showWurmzMessage(messages)` → bulle qui brise le 4e mur

---

## Boutons d'information des modes

`MODE_INFO` (objet unique, source de vérité) + `showModeInfo(key)`.
10 modes documentés. **À mettre à jour quand un mode change.**
