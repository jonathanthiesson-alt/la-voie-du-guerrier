-- ════════════════════════════════════════════════════════════════════════
-- dev_balance_games — anti-doublon des simulations d'équilibre
-- ════════════════════════════════════════════════════════════════════════
-- Une partie bot vs bot est ENTIÈREMENT déterminée par sa séquence de coups
-- (l'ouverture est tirée au hasard, la suite est du minimax déterministe).
-- Deux parties identiques fausseraient l'analyse : elles gonfleraient la
-- significativité (σ trop optimiste) et pourraient biaiser le taux. On stocke
-- donc une SIGNATURE (hash de la séquence de coups) par partie DÉCISIVE, avec
-- une contrainte UNIQUE : le worker insère en « ignore-duplicates » et ne
-- compte que les parties INÉDITES. La clé inclut la profondeur (une même
-- ouverture en prof. 4 vs 5 = deux parties différentes, pas un doublon).
--
-- RLS activée SANS politique (comme admin_audit_log) : table réservée au
-- backend. Le worker écrit avec le service_role, qui contourne la RLS.

create table if not exists public.dev_balance_games (
  id           bigint generated always as identity primary key,
  test_label   text not null,
  eval_label   text not null,
  depth_white  integer not null,
  depth_black  integer not null,
  sig          text not null,           -- sha1 de la séquence de coups
  winner       text,                    -- 'white' | 'black' (décisives seulement)
  plies        integer,
  created_at   timestamptz not null default now(),
  constraint dev_balance_games_uniq unique (test_label, eval_label, depth_white, depth_black, sig)
);

alter table public.dev_balance_games enable row level security;
-- Pas de politique volontairement → aucun accès anon/authenticated ; seul le
-- service_role (worker serveur) écrit/lit. Voir CLAUDE.md (exception RLS).
