# Migrations SQL

Tous les scripts sont **idempotents** : on peut les rejouer sans risque.

---

### ✅ Exécuté (Modes PUZZLE + INVASION/Monban — socle V0.93.0)

**Exécutés via MCP le 2026-08-16.** Vérifié : 8 tables créées avec le bon
nombre de colonnes (`puzzles` 19, `puzzle_attempts` 6, `puzzle_completions` 5,
`puzzle_creator_daily` 3, `puzzle_reports` 6, `monban_profiles` 5,
`monban_stats` 4, `invasion_history` 8). Voir `docs/ROADMAP_PUZZLE_INVASION.md`
pour le cadrage complet.

| # | Script | Contenu |
|---|---|---|
| ✅ | `puzzles_core.sql` | Tables `puzzles`, `puzzle_attempts`, `puzzle_completions`, `puzzle_creator_daily`, `puzzle_reports` + colonnes `profiles.puzzle_coin_balance`/`puzzle_slots` + RLS + RPC `puzzle_upsert`/`puzzle_set_solution`/`puzzle_publish`/`puzzle_unpublish`/`puzzle_record_attempt`/`puzzle_rate`/`puzzle_report`/`puzzle_admin_hide`. |
| ✅ | `monban_core.sql` | Tables `monban_profiles`, `monban_stats`, `invasion_history` + colonnes `profiles.shield_until`/`last_invasion_at` + RLS + RPC `monban_learn_from_game`/`monban_mark_trained`/`monban_buy_shield`. |
| ✅ | `invasion_engine.sql` | Colonnes `online_games.is_invasion`/`invasion_attacker_id`/`invasion_defender_id`/`invasion_resolved` + `invasion_history.game_id` + table `invasion_requests` (file d'acceptation 15s) + RLS + RPC `invasion_authorize`/`invasion_attach_game`/`invasion_respond`/`invasion_resolve` (service_role only)/`invasion_resolve_internal` (interne, EXECUTE révoqué pour authenticated)/`invasion_forfeit`/`invasion_candidates`. Pilotage serveur (Monban + résolution) dans `scripts/bot-army.mjs` (`driveInvasions`), toujours actif indépendamment de la directive `bot_army_control`. |
| ✅ | `puzzle_moderation_economy.sql` | Exécuté via MCP le 2026-08-16. RPC `puzzle_buy_slot` (achat d'un emplacement de publication supplémentaire, coût croissant ×15/emplacement possédé — P6/P7, seul déblocable de création concret décidé à ce jour) + `admin_get_puzzle_reports`/`puzzle_admin_dismiss_report` (volet admin des signalements de puzzles, P8, même patron que les signalements de joueurs). |
| ✅ | `guild_war_notifications.sql` | Exécuté via MCP le 2026-08-17. Réécrit `guild_challenge_respond`/`guild_challenges_cleanup` (guilds_v3.sql) pour insérer des notifications à TOUS les membres des deux guildes : `guild_war_accepted` (défi accepté, la guerre commence), `guild_war_won`/`guild_war_lost`/`guild_war_draw` (clôture des 48h). Comble le trou relevé au bilan du mode Guilde (aucun signal hors consultation manuelle de l'écran). |
| ✅ | `tournaments_guild_register.sql` | Exécuté via MCP le 2026-08-17. Réécrit `tournament_register` (tournaments_v4_admin.sql) : les tournois `kind='guild'` refusaient TOUJOURS l'inscription (« Lot C guilde » jamais terminé) et aucune autre RPC ne permettait d'y entrer — coquille vide découverte en écrivant le point info du mode. Inscription individuelle désormais ouverte à tout membre d'une guilde (n'importe laquelle), même mécanique de tournoi (suisse) que le mode individuel ensuite. |
| ✅ | `invasion_admin_unlimited.sql` | Exécuté via MCP le 2026-08-17. Réécrit `invasion_authorize` (invasion_engine.sql) — décision AD du cadrage Combat de guilde (`docs/ROADMAP_GUILD_BATTLE.md`) : Wurmz/Musashi (via `profiles.is_admin`) sautent le cooldown 24h attaquant et/ou le cooldown 72h du couple attaquant/défenseur, dans les deux sens (attaquant admin OU défenseur admin). Le bouclier (`shield_until`) reste toujours respecté. Prérequis de test pour le lot G0 (Monban réactif) du chantier Combat de guilde. |

### ✅ Exécuté (Journal du joueur — V0.87.0)

`player_journal.sql` — **confirmé par Jonathan le 2026-08-16.** Table
`player_journal` (id, user_id, created_at, event_type, message) + RLS
(lecture/écriture limitées à `auth.uid()=user_id`).

| # | Script | Contenu |
|---|---|---|
| ✅ | `player_journal.sql` | Table `player_journal` + index `(user_id, created_at desc)` + RLS select/insert own. |

## ⚠️ Pièges Supabase à connaître avant de toucher au SQL

### L'éditeur exécute tout dans UNE transaction
Si la **dernière** instruction échoue, **tout est annulé** — y compris les
`alter table` du début. C'est déjà arrivé : le script `tournaments_v2.sql` a
planté sur la vue (erreur 42P16) et **aucune colonne n'avait été créée**, alors
que tout le reste semblait valide.

**Après une erreur, toujours revérifier** que les colonnes existent vraiment.

### L'onglet actif
Le bouton « Run » exécute **l'onglet actif**, pas celui où on vient de coller.
Vérifier avant de lancer.

### `create or replace view` — erreur 42P16
Ne peut ni réordonner ni renommer les colonnes d'une vue existante.
→ `drop view if exists ma_vue;` **avant** de recréer.

### `create or replace function` — changement de type de retour
→ `drop function if exists ma_fonction(types);` **avant**.

### `cron.schedule` — erreur 22023 « invalid schedule »
L'intervalle en secondes n'est accepté que de **1 à 59**. `'60 seconds'` est
refusé. Pour une minute pile, utiliser le format cron : `'* * * * *'`.
Vécu sur `guilds_v2.sql` — et comme l'échec était sur la **dernière**
instruction, tout le script avait été annulé.

### Wrapper les opérations conditionnelles
```sql
do $$
begin
  if to_regclass('public.ma_table') is not null then
    execute 'alter table ...';
  end if;
end $$;
```

---

## Ordre d'exécution

### ✅ Déjà exécutés (confirmés par Jonathan)

| # | Script | Contenu |
|---|---|---|
| 1 | `economy_multimode` | Monnaies par mode |
| 2 | `daily_loop` | Défi du jour, quêtes, streak |
| 3 | `training_mode` | Défis, rating de défi, Rush |
| 4 | `ai_opponents` | Galerie IA, sceaux |
| 5 | `league_weekly` | Ligue, groupes, points — ⚠ **entrée fausse** : les tables/RLS existaient mais les RPC `get_my_league_standings`/`award_league_points` n'ont JAMAIS été créées (script jamais retrouvé dans le dépôt, jamais commité). D'où « Ligue indisponible » en jeu. **Reconstruit et exécuté via MCP le 2026-07-21** — voir entrée 32. |
| 6 | `tournaments_part1_tables` | Tables tournois |
| 7 | `tournaments_part2_functions` | Fonctions tournois v1 |
| 8 | `guilds` | Guildes |
| 9 | `enable_rls_security` | RLS |
| 10 | `seasons_and_milestones` | Saisons, paliers |
| 11 | `analytics_dashboard` | Télémétrie, rétention |
| 12 | `economy_fix_shiitake` | Shiitake + Koku jamais gagné |
| 13 | `admin_panel` | Panneau admin (récompenses/conversion/événements) |
| 14 | `game_administration` | Joueurs, modération, live-ops, audit |
| 15 | **`fix_rls_gameplay`** | 🔑 A réparé le matchmaking (RLS bloquait `matchmaking_queue`) |
| 16 | `tournaments_v2` | Plafonds par cadence, rondes adaptatives, délais, forfaits |
| 17 | `wurmz_skin_sync` | Colonne `wurmz_skin` + RPC protégé |
| 18 | `tournaments_v3.sql` | **Parties réelles** + nettoyage des tournois zombies |
| 19 | `tournaments_notify.sql` | Notification de partie prête à l'adversaire |
| 20 | `tournaments_claim.sql` | **Réservation atomique du créateur** (évite la double création) |
| 21 | `tournaments_attach_fix.sql` | Attachement à toute épreuve (notification isolée) |
| 22 | `tournaments_fix_uuid_mismatch.sql` | 🔑 **A réparé le lancement des parties de tournoi** — `online_games.id` (uuid) vs `tournament_pairings.online_game_id` (bigint) : cast systématiquement en échec, l'attachement n'aboutissait jamais. Voir `TESTING.md`. |
| 23 | `tournaments_auto.sql` | **Automatisation serveur** : `tournament_close_registration` (créateur seul), révocation de `tournament_start_next_round` aux clients, grâce 90 s avant double-forfait, `tournament_round_matches`, tick `pg_cron` toutes les 20 s |
| 24 | `tournaments_claim_race.sql` | Réservation de création durcie : `creator_claimed_at`, libération refusée par le serveur avant 10 s (fin de la double création de partie) |
| 25 | `friend_challenges.sql` | Défis entre amis : colonnes `challenges.mode`/`ranked`, `online_games.ranked`, `arena_matches.ranked` ; `record_arena_round_win` ne verse plus de Koku en Arène amicale |
| 26 | `guilds_v2.sql` | Supprime la faille `guild_contribute_ryu` (montant libre client), ajoute `guild_report_win` (serveur-autoritaire, +2 Ryu par victoire classée), défis inter-guildes chef-seulement sur 48 h + tick `pg_cron`. ⚠ A d'abord échoué sur `cron.schedule('...','60 seconds')` → erreur 22023 (voir piège ci-dessus) |
| 27 | `wurmz_easter_egg.sql` | Easter egg « Trouver Wurmz » : colonne `profiles.wurmz_found` + RPC `claim_wurmz_egg()` — **aucun montant transmis par le client** (400 Koku en dur côté serveur, un seul versement par compte, `for update`) |
| 28 | `sumo_event.sql` | **Événement SUMO (jusqu'au 31 août)** : colonnes `mode`/`elo` sur les tables Arène (le SUMO réutilise toute l'infra Arène), monnaie Fame 心 (`profiles.fame_balance` + `sumo_wins`/`sumo_losses`), RPC `record_sumo_round_win` (montants en dur serveur : +2/+1, coupés après le 31 août), vue `sumo_leaderboard` (score = fame × (1 + ratio de victoires × min(parties,35)/35)). **Exécuté le 2026-07-18.** |
| 29 | `guilds_v3.sql` | **Défis inter-guildes avec acceptation** : le défi part en `pending` (aucun point ne compte), le chef DÉFIÉ accepte (`guild_challenge_respond`, 48 h à partir de l'acceptation) ou refuse ; expiration auto des défis sans réponse. **Exécuté le 2026-07-18.** |
| 30 | `guild_chat.sql` | **Chat de guilde** (refonte UI phase B) : table `guild_channel_messages` (lecture/écriture directe client, calquée sur `league_channel_messages`), RLS membre-seulement (2 politiques). Double accès côté client : menu Guilde (JOUER) + Messagerie (SOCIAL). **Appliqué via MCP le 2026-07-18.** |
| 31 | `tournaments_no_draw_ranked_rewards.sql` | **Retire la nulle des tournois** (le jeu ne peut résoudre que par victoire/défaite) : `tournament_report_from_game` n'accepte plus que `white`/`black`. `tournament_award_podium` ne paie plus seulement le podium (20/12/6 Mon) mais **tout le classement final**, du dernier (3 Mon) au premier (20 Mon), au prorata linéaire du rang. En appliquant, a aussi supprimé une **vieille surcharge zombie** `tournament_report_from_game(uuid, text)` (paramètre `p_game_id` en `uuid`, antérieure au fix `tournaments_fix_uuid_mismatch.sql` — ne recevait plus jamais d'appel mais contenait encore la logique « nulle »). **Appliqué via MCP le 2026-07-20.** |
| 32 | `league_weekly.sql` (reconstruit) | **Corrige l'entrée 5, qui était fausse** : les tables `league_seasons/pools/members/channel_messages` + RLS existaient bel et bien, mais **aucune des RPC** que le client appelle (`get_my_league_standings`, `award_league_points`) n'avait jamais été créée — le script d'origine n'a jamais été commité. Recrée les trois fonctions (`league_current_season`, `league_ensure_membership` en interne, + les deux RPC publiques). Modèle initial simplifié : saison mensuelle, pool générique de 100, tier toujours 0. **Appliqué via MCP le 2026-07-21**, puis remplacé le jour même par l'entrée 33. |
| 33 | `league_divisions.sql` | **Ajoute les divisions + promotion/relégation**, comme le texte de règles déjà affiché au joueur (écran ⓘ) le promettait mais que l'entrée 32 ne faisait pas encore : cycle **hebdomadaire** (lundi→dimanche), pools d'**~50 joueurs de la même division**, top 3 promus / bottom 3 relégués. Colonnes neuves : `profiles.league_division` (persiste d'une semaine à l'autre), `league_pools.division`, `league_seasons.resolved`. Nouvelle fonction `league_resolve_pending_weeks()` (déclenchée à la volée par `league_current_season()` quand la semaine précédente est terminée) — pools de moins de 6 joueurs ignorés pour éviter le chevauchement top3/bottom3. A réaligné la saison de test existante (bornes mensuelles) sur la semaine ISO en cours. **Appliqué via MCP le 2026-07-21.** |
| 34 | `league_divisions.sql` (correctif `league_current_season`) | **Corrige un bug latent qui cassait la Ligue** dès qu'aucune saison ne couvrait le jour courant : la table de retour `returns table(id uuid, ends_at date)` déclare une colonne OUT `ends_at` qui rendait **AMBIGU** (42702, variable PL/pgSQL vs colonne) tout `ends_at` non qualifié dans le `select`/`returning` du corps. La fonction plantait donc **au moment précis** où elle devait créer la semaine courante → `get_my_league_standings` remontait l'exception → écran « Ligue indisponible » (repéré en jeu le 2026-08-04, les 2 saisons de test ayant expiré fin juillet). Fix : qualifier toutes les colonnes par leur table (`ls.` / `league_seasons.`). **Appliqué via MCP le 2026-08-04**, fichier `league_divisions.sql` corrigé en conséquence. Vérifié : semaine courante 03→09/08 créée, anciennes saisons résolues. |
| 38 | `fix_tournament_bots_never_abandon.sql` | **Tournoi robuste aux pannes de worker.** Quand le worker tombait, les parties bot-vs-bot se figeaient → à l'échéance, `tournament_resolve_timeouts` les soldait en forfait ET marquait les 2 bots `abandoned=true` → après quelques minutes tout le peloton était exclu et le tournoi dégénérait à 2 joueurs (rematch forcé, cf #37 « pas d'alternative »). Fix : (1) un **bot n'est JAMAIS marqué abandonniste** (IA toujours dispo), seuls les humains absents abandonnent ; (2) si la partie s'est en fait **terminée mais non reportée** (worker momentanément absent), on enregistre le **vrai résultat** via `tournament_report_from_game` au lieu d'un forfait. **Appliqué via MCP le 2026-08-05.** |
| 37 | `fix_tournament_swiss_no_rematch.sql` | **Appariement suisse : évite les revanches.** `tournament_start_next_round` triait par (score, wins) et appariait les voisins (1-2, 3-4…) sans vérifier les affrontements passés → on retombait sur le même adversaire à chaque ronde (vécu : Wurmz vs 12-Daimyo rondes 1-2-3). Nouvel appariement glouton : pour chaque joueur, on prend le 1er adversaire libre **jamais affronté** ; revanche seulement en dernier recours (fallback) ; bye si effectif impair. **Appliqué via MCP le 2026-08-05.** |
| 36 | `fix_tournament_report_uuid.sql` | **FIX CRITIQUE tournoi.** `tournament_report_from_game` avait une signature `(p_game_id BIGINT,…)` alors que `online_games.id`/`tournament_pairings.online_game_id` sont **UUID**. Le client (`reportTournamentGameEnd`) et le worker (`tournamentTick`) passaient un uuid → appel impossible → échec **silencieux** (catch vide) → **aucun résultat de tournoi jamais enregistré** : paires bloquées `result=null`, parties « en cours » à vie, puis double-forfait au timeout de ronde et clôture prématurée. La surcharge uuid (correcte) avait été supprimée par erreur (cf. #31 « surcharge zombie »). Rétablie en `uuid`, variante bigint retirée. **Appliqué via MCP le 2026-08-05** (repéré en test tournoi live). |
| 40 | `tournaments_v5_elo.sql` | **Tournois : classement par Élo.** Redéfinit `tournament_standings` pour exposer l'`elo` de chaque joueur (colonne selon la cadence : `elo_3s`/`elo_5s`/`elo_10s`, ≤3s⇒3s, ≥10s⇒10s, sinon 5s) et l'utiliser comme **départage** après points puis victoires. `create or replace` idempotent, pas de changement de type de retour. **Appliqué via MCP le 2026-08-11.** |
| 39 | `tournaments_v4_admin.sql` | **Refonte Tournois pilotée admin (P4 Lot A).** Colonnes neuves sur `tournaments` : `audience` (all/subscriber/freemium), `kind` (individual/guild), `game_mode`, `starts_at`, `registration_opens_at/closes_at`, `presentation`, `rewards` (jsonb {rang:montant}), `reward_currency` (préfixe d'une colonne `<cur>_balance`). RPC admin-only (`is_admin_user()`) `tournament_admin_create`/`tournament_admin_update` ; `tournament_create(text,int)` refuse désormais les non-admins (les joueurs ne créent plus). `tournament_register` respecte le public (abonné/freemium) + la fenêtre d'inscription. `tournament_award_podium` honore le barème `rewards`+`reward_currency` (fallback ancien barème linéaire Mon). `tournament_list` expose les nouveaux champs. Helper `tournament_reward_currency_ok`. **Appliqué via MCP le 2026-08-10.** |
| 35 | `bots_arena_tournament.sql` | **Les bots jouent partout.** (1) **Arène** : ajoute `want_backfill/backfill_after/backfill_random/backfill_max_elo` à `arena_matchmaking_queue` → un joueur d'arène qui poireaute est rejoint par un bot d'Elo voisin en match **amical** (le worker crée l'`arena_matches` `ranked=false` + manche 1 ; le client humain pilote la progression du BO3 face à un bot). (2) **Tournoi** : RPC `tournament_fill_with_bots(bigint)` (créateur/admin, statut `open` uniquement) qui complète les slots vides avec les **15 fragments** (01→15, jamais le Rōnin 00) ; les bots jouent ensuite réellement leurs rondes (worker : création/pilotage/report des paires contenant un bot, via `tournament_report_from_game`). **Appliqué via MCP le 2026-08-04.** Vérifié : remplissage 8/8 fragments sans Rōnin, gardes `forbidden`/`already_started`/`full` OK, insert arène avec colonnes backfill accepté. |

### ⏳ À exécuter par Jonathan (Champ de bataille online — V0.41.0)

Ordre : `battlefield_online.sql` **puis** `battlefield_lobby.sql` (le second
dépend de la table `battlefield_games` du premier). Tous deux idempotents,
additifs, sans effet sur `online_games`/1v1. Contrôle en fin de chaque script.

| # | Script | Contenu |
|---|---|---|
| A | `battlefield_online.sql` | Table `battlefield_games` (6 sièges dans `seats` jsonb) + trigger `updated_at` + RLS (3 politiques) + realtime + RPC `battlefield_bot_fill(elo,count)`. |
| B | `battlefield_lobby.sql` | Lobby d'équipe : `battlefield_teams` (3 slots), `battlefield_solo_queue`, `battlefield_invites` (dédiée — **pas** `challenges`) ; RLS (10 politiques) + realtime ; RPC `battlefield_join_open_slot`, `battlefield_accept_invite`, `battlefield_matchmake(team,format,timer)`, `battlefield_solo_place()`. |

Après exécution : activer le worker (`bot-army.yml`, directive `enabled`) pour
que les sièges bots jouent et que les timeouts s'appliquent.

### ✅ Exécuté (Identité de guilde — V0.44.0)

`guild_identity.sql` — **déployé** (vérifié 2026-08-10 : colonnes présentes,
`guild_update_identity`/`guild_identity` existent, la guilde « Rottens » a déjà
une bannière + devise). Additif et idempotent.

| # | Script | Contenu |
|---|---|---|
| ✅ | `guild_identity.sql` | 3 colonnes sur `guilds` (`banner` jsonb, `devise`, `info_message` + `info_message_at`) ; `get_my_guild()` étendu ; RPC `guild_update_identity(devise,banner,info)` (chef uniquement) ; RPC public `guild_identity(id)`. |

### ⏳ À exécuter par Jonathan (Administration de guilde — V0.48.0)

`guild_admin.sql` — additif et idempotent (aucune colonne neuve : réutilise
`profiles.last_seen`/`is_online` existants). Contrôle en fin de script.

| # | Script | Contenu |
|---|---|---|
| — | `guild_admin.sql` | RPC `guild_kick(p_player_id)` (le chef retire un membre ; pas soi-même, pas un autre chef) ; RPC public `guild_roster(p_guild_id)` (roster + présence d'une guilde, pour consulter les autres guildes). |

Tant que non exécuté : le bouton ✕ « retirer » et le 👁 « voir le roster » se
dégradent proprement (toast d'erreur, aucun crash).

### ✅ Exécuté (Bot-Army : rencontre en chaîne — V0.85.0)

`add_backfill_target_bot.sql` — **déployé** (vérifié 2026-08-15 : colonne
`backfill_target_bot` présente sur `matchmaking_queue` et
`arena_matchmaking_queue`). Additif et idempotent.

| # | Script | Contenu |
|---|---|---|
| ✅ | `add_backfill_target_bot.sql` | Colonne `backfill_target_bot` sur `matchmaking_queue` et `arena_matchmaking_queue` : le client y envoie la clé du **prochain bot non vaincu** de la chaîne 01→15→00 (au lieu du plafond d'Elo seul) ; le worker (`bot-army.mjs`) fait rejoindre CE bot précis plutôt que le plus proche d'Elo — sauf « aléatoire » coché. |

---

## Diagnostic RLS

Une table avec **RLS activée et ZÉRO politique** est **totalement bloquée**, en
lecture comme en écriture, **silencieusement**. Le bouton « Run and enable RLS »
de Supabase a déjà cassé le matchmaking de cette façon.

```sql
select
  c.relname as table_name,
  c.relrowsecurity as rls_active,
  (select count(*) from pg_policies p
     where p.schemaname='public' and p.tablename=c.relname) as nb_policies,
  case
    when c.relrowsecurity and (select count(*) from pg_policies p
        where p.schemaname='public' and p.tablename=c.relname) = 0
      then '⚠ BLOQUÉE (RLS sans politique)'
    when c.relrowsecurity then 'RLS + politiques'
    else 'pas de RLS'
  end as etat
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relkind='r'
order by 4 desc, 1;
```

### ✅ Exception normale
**`admin_audit_log` est en « RLS sans politique » PAR CONCEPTION.**
On n'y accède que via des RPC `SECURITY DEFINER`. **Ne pas « corriger ».**

---

## Requête de contrôle des tournois

```sql
select
  to_regproc('public.tournament_create')          as fn_create,
  to_regproc('public.tournament_claim_creation')  as fn_claim,
  to_regproc('public.tournament_attach_game')     as fn_attach,
  to_regproc('public.tournament_cleanup')         as fn_cleanup,
  to_regproc('public.tournament_claim_forfeit')   as fn_forfeit,
  (select count(*) from information_schema.columns
     where table_name='tournaments'
       and column_name in ('max_players','round_deadline','round_minutes')) as cols_tournaments,
  (select count(*) from information_schema.columns
     where table_name='tournament_pairings'
       and column_name in ('online_game_id','creator_claimed_by')) as cols_pairings;
```

Attendu : toutes les fonctions nommées, `cols_tournaments = 3`, `cols_pairings = 2`.

---

## Requête de contrôle des guildes & de l'easter egg

```sql
select
  to_regproc('public.claim_wurmz_egg')::text      as fn_wurmz,
  to_regproc('public.guild_challenge')::text      as fn_guild_challenge,
  to_regproc('public.guild_report_win')::text     as fn_guild_report,
  to_regproc('public.guild_contribute_ryu')::text as faille_doit_etre_null,
  (select count(*) from information_schema.columns
     where table_name='profiles' and column_name='wurmz_found')       as col_wurmz_found,
  (select count(*) from information_schema.columns
     where table_name='online_games' and column_name='guild_counted') as col_guild_counted,
  (select count(*) from cron.job where jobname='guild_challenges_tick')   as tick_guildes,
  (select count(*) from cron.job where jobname='tournament_cleanup_tick') as tick_tournois;
```

Attendu : les 3 fonctions nommées, **`faille_doit_etre_null` à `null`**, les
deux colonnes à 1, les deux ticks à 1.
*Vérifié en base le 2026-07-17 : tout au vert.*

---

## Sécurité — principes

- Le rôle admin vient de **`profiles.is_admin`** (colonne en base), **pas** d'une
  liste de pseudos en dur (usurpable si un compte change de nom).
- **Tous les RPC d'administration appellent `is_admin_user()`** côté serveur.
  Trafiquer le client ne sert à rien.
- Le drapeau `wurmz_skin` est refusé par le serveur à tout compte dont le pseudo
  n'est pas `Wurmz` (RPC `set_wurmz_skin`).
- Toute action admin est tracée dans **`admin_audit_log`**.
