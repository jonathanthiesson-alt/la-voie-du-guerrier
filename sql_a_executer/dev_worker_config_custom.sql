-- ════════════════════════════════════════════════════════════════════════
-- dev_worker_config — support d'un FORMAT PERSONNALISÉ pour le worker serveur
-- ════════════════════════════════════════════════════════════════════════
-- Le mode 'custom' construit dans l'éditeur visuel du Labo n'existe PAS dans
-- index.html → l'Action GitHub ne peut pas le retrouver par son id. On stocke
-- donc son descripteur JSON complet ici, que le worker lit quand format='custom'
-- (scripts/balance-worker.mjs). Migration ADDITIVE et réversible.

alter table public.dev_worker_config add column if not exists custom_format jsonb;

-- La signature de dev_set_worker_config gagne un argument → on DROP avant de
-- recréer (un simple create or replace créerait une SURCHARGE, rendant l'appel
-- par paramètres nommés du navigateur ambigu). dev_get_worker_config, lui, rend
-- la ligne entière (select *) → il récupère la nouvelle colonne sans changement.
drop function if exists public.dev_set_worker_config(boolean,text,int,int,int,text,text,int,int,int);

create or replace function public.dev_set_worker_config(
  p_enabled boolean, p_mode text, p_fixed_depth int,
  p_cycle_min int, p_cycle_max int, p_format text,
  p_eval_key text, p_opening int, p_games int, p_time_budget_sec int,
  p_custom_format jsonb default null
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
    custom_format   = coalesce(p_custom_format, custom_format),
    updated_at      = now()
  where id = 1;
  -- reclippe le curseur de cycle dans la nouvelle plage
  update public.dev_worker_config
     set cycle_current = least(greatest(cycle_current, cycle_min), cycle_max)
   where id = 1;
  select * into r from public.dev_worker_config where id = 1;
  return r;
end; $$;
