-- ════════════════════════════════════════════════════════════════════════
-- dev_worker_config — pilotage du worker serveur depuis le Laboratoire
-- ════════════════════════════════════════════════════════════════════════
-- Une seule ligne (id=1). Le Labo (navigateur) la lit/écrit via des RPC admin ;
-- l'Action GitHub la lit chaque heure avec le service_role (accès direct, la
-- RLS étant contournée) et fait avancer le cycle de profondeur. « Activer/
-- désactiver » = le drapeau `enabled` que l'Action vérifie.

create table if not exists public.dev_worker_config (
  id               int primary key default 1,
  enabled          boolean not null default false,
  mode             text    not null default 'cycle',     -- 'fixed' | 'cycle'
  fixed_depth      int     not null default 4,            -- si mode='fixed'
  cycle_min        int     not null default 4,            -- si mode='cycle'
  cycle_max        int     not null default 6,
  cycle_current    int     not null default 4,            -- avancé par l'Action
  format           text    not null default 'standard',
  eval_key         text    not null default 'symmetric',
  opening          int     not null default 6,
  games            int     not null default 100,          -- cible de parties/run
  time_budget_sec  int     not null default 600,          -- plafond de temps/run
  updated_at       timestamptz not null default now(),
  constraint dev_worker_config_singleton check (id = 1)
);
insert into public.dev_worker_config (id) values (1) on conflict (id) do nothing;

alter table public.dev_worker_config enable row level security;
-- Pas de politique → navigateur passe par les RPC ci-dessous ; l'Action lit en
-- service_role (contourne la RLS).

-- Lecture (navigateur, admin uniquement).
create or replace function public.dev_get_worker_config()
returns public.dev_worker_config
language plpgsql security definer set search_path to 'public' as $$
declare r public.dev_worker_config;
begin
  if not is_admin_user() then raise exception 'admin only'; end if;
  select * into r from public.dev_worker_config where id = 1;
  return r;
end; $$;

-- Écriture (navigateur, admin uniquement). cycle_current n'est PAS piloté ici
-- (c'est l'Action qui l'avance) mais on le reclippe dans [min,max] après coup.
create or replace function public.dev_set_worker_config(
  p_enabled boolean, p_mode text, p_fixed_depth int,
  p_cycle_min int, p_cycle_max int, p_format text,
  p_eval_key text, p_opening int, p_games int, p_time_budget_sec int
) returns public.dev_worker_config
language plpgsql security definer set search_path to 'public' as $$
declare r public.dev_worker_config;
begin
  if not is_admin_user() then raise exception 'admin only'; end if;
  update public.dev_worker_config set
    enabled         = coalesce(p_enabled, enabled),
    mode            = coalesce(p_mode, mode),
    fixed_depth     = greatest(1, least(6, coalesce(p_fixed_depth, fixed_depth))),
    cycle_min       = greatest(1, least(6, coalesce(p_cycle_min, cycle_min))),
    cycle_max       = greatest(1, least(6, coalesce(p_cycle_max, cycle_max))),
    format          = coalesce(p_format, format),
    eval_key        = coalesce(p_eval_key, eval_key),
    opening         = greatest(0, least(10, coalesce(p_opening, opening))),
    games           = greatest(1, least(2000, coalesce(p_games, games))),
    time_budget_sec = greatest(30, least(3000, coalesce(p_time_budget_sec, time_budget_sec))),
    updated_at      = now()
  where id = 1;
  -- reclippe le curseur de cycle dans la nouvelle plage
  update public.dev_worker_config
     set cycle_current = least(greatest(cycle_current, cycle_min), cycle_max)
   where id = 1;
  select * into r from public.dev_worker_config where id = 1;
  return r;
end; $$;
