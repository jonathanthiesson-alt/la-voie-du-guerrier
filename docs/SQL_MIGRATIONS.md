# Migrations SQL

Tous les scripts sont **idempotents** : on peut les rejouer sans risque.

---

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
