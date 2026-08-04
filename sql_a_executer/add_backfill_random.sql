-- ══════════════════════════════════════════════════════════════════
-- BOT-ARMY — préférences de backfill : « aléatoire » + plafond de déblocage.
--
-- • backfill_random : quand un bot rejoint un joueur qui patiente
--   (want_backfill), il est choisi AU HASARD parmi les bots débloqués plutôt
--   que par proximité d'Elo.
-- • backfill_max_elo : Elo du plus haut bot que le joueur a DÉBLOQUÉ (l'état de
--   déblocage vit en local sur l'appareil). Comme le déblocage est strictement
--   croissant en Elo, le worker ne propose que les bots base_elo <= ce plafond
--   → exactement le sous-ensemble débloqué. 0/NULL = aucun filtre (repli).
--
-- L'app pose ces champs à l'enfilement (startMatchmakingSearch) ; le worker les
-- lit dans backfillTick. Idempotent. L'app est résiliente : tant que ces
-- colonnes n'existent pas, elle réinsère sans les champs (le matchmaking ne
-- casse pas).
-- ══════════════════════════════════════════════════════════════════

alter table matchmaking_queue
  add column if not exists backfill_random  boolean not null default false;
alter table matchmaking_queue
  add column if not exists backfill_max_elo integer;

-- Contrôle : doit lister les deux colonnes.
select column_name, data_type, column_default
  from information_schema.columns
 where table_name='matchmaking_queue'
   and column_name in ('backfill_random','backfill_max_elo')
 order by column_name;
