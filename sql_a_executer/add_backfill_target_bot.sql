-- ══════════════════════════════════════════════════════════════════
-- BOT-ARMY — rencontre les bots DANS L'ORDRE OÙ ON LES BAT, plus au fil de
-- l'Elo (demande Wurmz, 2026-08-15).
--
-- • backfill_target_bot : clé du PROCHAIN bot non vaincu de la chaîne
--   01→15→00 (calculée côté client, voir nextBotArmyTarget() dans
--   index.html — l'état « vaincu » vit en local sur l'appareil, comme
--   backfill_max_elo). Quand un bot rejoint un joueur qui patiente
--   (want_backfill), le worker choisit CE bot précis plutôt que le plus
--   proche d'Elo — sauf si « aléatoire » (backfill_random) est coché.
--   NULL = pas de cible (repli sur le plus proche d'Elo, comportement
--   précédent) ou chaîne terminée (les 16 vaincus).
--
-- Complète add_backfill_random.sql / bots_arena_tournament.sql. Idempotent.
-- L'app est résiliente : tant que ces colonnes n'existent pas, elle réinsère
-- sans le champ (le matchmaking ne casse pas).
-- ══════════════════════════════════════════════════════════════════

alter table matchmaking_queue
  add column if not exists backfill_target_bot text;

alter table arena_matchmaking_queue
  add column if not exists backfill_target_bot text;

-- Contrôle : doit lister la colonne sur les deux tables.
select table_name, column_name, data_type
  from information_schema.columns
 where table_name in ('matchmaking_queue','arena_matchmaking_queue')
   and column_name = 'backfill_target_bot'
 order by table_name;
