# Champ de bataille — online 6 sièges (Passe 2b)

> Conception de la couche online du mode 3v3. **Rien n'est exécuté sur la prod
> tant que Jonathan n'a pas relu et lancé le SQL** (`sql_a_executer/`, cf.
> `docs/SQL_MIGRATIONS.md`). Le moteur local + la rotation 6 sièges (Passe 1 +
> 2a) sont déjà livrés côté client.

## Décisions produit (2026-08-08)

- **Amical** : aucune modification d'ELO persistant. L'**ELO d'équipe** (moyenne
  des 3 combattants) sert **uniquement au matchmaking**. Zéro impact saison/Ligue.
- **Déconnexion d'un humain** = son **combattant est forfait = éliminé** (réutilise
  la mécanique d'élimination : escouade retirée, rotation saute le siège, joueur
  spectateur). Pas de reprise par un bot.
- **Avec cadences** (comme le 1v1) : chaque siège a une **échéance** ; dépasser le
  temps = **forfait du combattant** (même effet que la déconnexion). L'échéance est
  stockée (`turn_deadline`) et **imposée par le worker** (JS), pas par du SQL —
  éviter de manipuler le plateau en plpgsql.
- **Équipes ad hoc par match** ; ELO d'équipe figé à la constitution. Si trop peu
  d'humains, la **bot army (équipe des 15)** complète les deux camps.

## Pourquoi une nouvelle table (et pas `online_games`)

`online_games` est câblée pour **exactement 2 joueurs** (`white_player_id`,
`black_player_id`, `turn` couleur, RLS « je suis l'un des deux »). Le 6 sièges a
besoin de **6 propriétaires** et d'une **rotation par siège**. On isole donc dans
`battlefield_games`, sans toucher au 1v1 (règle CLAUDE.md : ne jamais fragiliser
un chemin critique existant).

## Modèle de données

### `battlefield_games` (la partie + realtime)

| colonne | type | rôle |
|---|---|---|
| `id` | uuid pk | identifiant |
| `status` | text | `active` \| `finished` |
| `format` | jsonb | le format `champDeBataille` (le client rend sans coder en dur) |
| `game_state` | jsonb | `{board,stacks,lastMoved,lastMovedByColor,eliminatedUnits}` |
| `seats` | jsonb | **6 sièges dans l'ordre de rotation** (voir ci-dessous) |
| `seat_idx` | int | index du siège **actif** dans `seats` (0..5) |
| `turn` | text | couleur du siège actif (parité avec le client) |
| `timer_seconds` | int | cadence |
| `turn_deadline` | timestamptz | échéance du siège actif (timeout → forfait, imposé worker) |
| `team_a_elo` / `team_b_elo` | int | trace du matchmaking (blanc = A, noir = B) |
| `winner` | text | `white` \| `black` \| null |
| `created_at` / `updated_at` | timestamptz | |

**`seats`** = tableau ordonné (rotation `Blanc1→Noir1→Blanc2→Noir2→Blanc3→Noir3`)
de 6 objets :

```json
{ "seat":0, "color":"white", "unit":1,
  "player_id":"<uuid profil (humain ou bot)>", "is_bot":false,
  "bot_key":null, "name":"Wurmz", "eliminated":false }
```

Le siège actif = `seats[seat_idx]`. `turn` = `seats[seat_idx].color`. Un siège
`eliminated:true` est sauté par la rotation (déjà géré côté client par
`bfSeatEliminated`, ici on persiste l'info dans `seats`).

### RLS (calquée sur `online_games`)

- **SELECT** : `using(true)` — ouvert (spectateur), comme `og_read`.
- **INSERT** : le créateur doit être **un siège humain** de la partie
  (`auth.uid()` présent dans `seats[].player_id`). Le service_role (worker) passe
  outre pour les parties bot-only.
- **UPDATE** : tout **participant humain** peut pousser l'état (modèle de confiance
  identique au 1v1 amical). Le worker (service_role) pilote les bots et les timeouts.
- Pas de DELETE (parties conservées).
- Table **ajoutée à la publication `supabase_realtime`** (comme `online_games`).

### RPC `battlefield_bot_fill(p_elo int, p_count int)`

Renvoie jusqu'à `p_count` bots **provisionnés** (`bot_roster.profile_id` non null)
d'ELO proche de `p_elo`, **hors Rōnin caché** (`tier <> 'hidden'`), pour remplir les
sièges vides. Sélection serveur = cohérente et respecte les règles de galerie.

## Découpage en sous-lots

| Lot | Contenu | Où | État |
|---|---|---|---|
| **2b-①** | Schéma `battlefield_games` + RLS + realtime + RPC `battlefield_bot_fill` | `sql_a_executer/battlefield_online.sql` | écrit — **prod → à exécuter** |
| **2b-②③** | Lobby d'équipe (3 slots), matchmaking ELO cumulé, les 3 voies (salon/code/file solo), invitations, synchro partie | `sql_a_executer/battlefield_lobby.sql` + `index.html` | **livré** (SQL prod à exécuter) |
| **2b-④** | **Worker** : pilote les sièges bots (deux camps), impose `turn_deadline` (timeout=forfait), remplit la file solo | `scripts/bot-army.mjs` | **livré** |
| **2b-⑤** | Tests en conditions réelles avec la bot army | — | à faire (après SQL) |

## Lobby d'équipe (livré)

- **Créer / rejoindre** : `battlefield_teams` (3 slots jsonb, `elo_sum`,
  `invite_code`, `open_to_random`). Le chef occupe le slot 0.
- **Les 3 voies pour un slot ouvert** : (a) **salon** — équipes `forming` +
  `open_to_random` listées, on clique pour rejoindre ; (b) **code** — n'importe
  qui avec `invite_code` prend un slot ouvert ; (c) **file solo** —
  `battlefield_solo_queue`, le worker (`battlefield_solo_place`) glisse les
  joueurs dans les slots ouverts d'ELO proche.
- **Contrôles chef par slot** : inviter un ami (`battlefield_invites`, table
  dédiée — PAS `challenges`), placer un bot (`battlefield_bot_fill`), ouvrir.
- **Matchmaking** : `battlefield_matchmake(team, format, timer)` — file `queued`,
  apparie l'ELO cumulé le plus proche, crée la partie (6 sièges interleavés
  `W1,B1,W2,B2,W3,B3`). Le caller = équipe A (blanc) écrit le plateau initial ;
  l'adversaire découvre `game_id` par realtime. Sans adversaire humain : bouton
  « compléter par des bots ».

## Synchro de partie (client, livré)

`enterBattlefieldGame` réutilise `initGame` (plateau custom) puis bascule ONLINE :
sièges du serveur (avec `player_id`), abonnement realtime `battlefield_games`.
Chaque humain ne pilote QUE son siège (verrou `pieceInputLocked` hors de son
tour). `bfOnlineSync` pousse l'état après mon coup ; `applyRemoteBattlefieldState`
est l'unique voie de transition de tour (mon écho compris). `switchTurn` et la
branche victoire d'`executeDrop` branchent sur `bfOnlineSync`.

## Notes worker (2b-④, dépôt séparé — pas encore fait)

- Détecter les parties à jouer : `battlefield_games` `active` où
  `(seats->seat_idx->>'is_bot')::bool` est vrai → jouer le coup du bot (moteur JS
  extrait, agnostique aux dimensions — cf. Laboratoire) et écrire `game_state`,
  `seat_idx` suivant, `turn`, `turn_deadline`, `winner`.
- Imposer le timeout : siège actif **humain** dont `turn_deadline < now()` →
  forfait de son combattant (élimination) et rotation.
