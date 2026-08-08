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

| Lot | Contenu | Où | Risque |
|---|---|---|---|
| **2b-①** | Schéma `battlefield_games` + RLS + realtime + RPC `battlefield_bot_fill` | `sql_a_executer/battlefield_online.sql` | **prod → relecture Jonathan** |
| **2b-②** | Client : bouton **carrousel** + « partie rapide » (toi + 5 bots) → valide tout le pipeline online 6 sièges | `index.html` | client |
| **2b-③** | Client : **inviter des amis** dans ton équipe (party) + matchmaking équipe vs équipe d'ELO proche (table `battlefield_queue`, lot SQL séparé) | `index.html` + SQL | prod |
| **2b-④** | **Worker** (GitHub Actions) : piloter les sièges bots (deux camps) + imposer `turn_deadline` (timeout = forfait) | dépôt worker | worker |
| **2b-⑤** | Tests en conditions réelles avec la bot army | — | — |

Le 2b-② (un humain + 5 bots) valide de bout en bout la synchro realtime, la
rotation, le timeout et le pilotage bot **avant** d'ajouter la complexité des
équipes 100 % humaines (2b-③).

## Notes worker (2b-④, dépôt séparé — pas encore fait)

- Détecter les parties à jouer : `battlefield_games` `active` où
  `(seats->seat_idx->>'is_bot')::bool` est vrai → jouer le coup du bot (moteur JS
  extrait, agnostique aux dimensions — cf. Laboratoire) et écrire `game_state`,
  `seat_idx` suivant, `turn`, `turn_deadline`, `winner`.
- Imposer le timeout : siège actif **humain** dont `turn_deadline < now()` →
  forfait de son combattant (élimination) et rotation.
