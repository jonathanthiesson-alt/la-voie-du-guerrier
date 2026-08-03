-- ══════════════════════════════════════════════════════════════════
-- ARMÉE DE BOTS — fondation (Phase 1)  ·  cf. docs/BOT_ARMY_PLAN.md
--
-- Outil DEV : déployer jusqu'à ~100 bots (sessions ANONYMES) pour tester
-- le online seul. Ce script pose : le flag is_bot, la table de contrôle,
-- la table de rapport, les RPC admin (directive / rapport / purge), et
-- l'EXCLUSION des bots de la ligue (le classement persistant principal).
--
-- ⚠ PRÉ-REQUIS avant/à côté :
--   • Activer l'AUTH ANONYME dans Supabase (Auth → Providers → Anonymous).
--   • Exécuter ce fichier APRÈS league_weekly.sql (il redéfinit 3 de ses
--     fonctions en y ajoutant le garde is_bot — il les SUPERSÈDE).
--   • Le worker (GitHub Actions) supprime les COMPTES bots via l'API admin
--     service_role ; ici on ne nettoie que les artefacts applicatifs.
--
-- Idempotent. Accès aux tables : via RPC SECURITY DEFINER + worker
-- service_role uniquement (RLS activée, zéro politique client — même
-- motif que admin_audit_log).
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Flag is_bot sur les profils ────────────────────────────────
alter table profiles add column if not exists is_bot boolean not null default false;
create index if not exists idx_profiles_is_bot on profiles(is_bot) where is_bot;

-- ── 2. Table de contrôle (ligne unique, écrite par le menu dev) ────
create table if not exists bot_army_control (
  id         int primary key default 1,
  enabled    boolean     not null default false,
  count      int         not null default 0,
  mode       text        not null default 'matchmaking',  -- matchmaking|arena|tournament|free
  target_id  uuid,                                          -- arène/tournoi ciblé (facultatif)
  updated_by uuid,
  updated_at timestamptz not null default now(),
  constraint bot_army_control_singleton check (id = 1)
);
insert into bot_army_control(id) values (1) on conflict (id) do nothing;
alter table bot_army_control enable row level security;

-- ── 3. Table de rapport (écrite par le worker, lue par le menu dev) ─
create table if not exists bot_army_report (
  mode         text primary key,           -- un agrégat courant par mode
  bots_active  int  not null default 0,
  games_played int  not null default 0,
  wins         int  not null default 0,
  losses       int  not null default 0,
  errors       int  not null default 0,
  note         text,
  updated_at   timestamptz not null default now()
);
alter table bot_army_report enable row level security;

-- ── 4. RPC admin : poser la directive (déployer / arrêter) ─────────
drop function if exists bot_army_set_directive(boolean, int, text, uuid);
create or replace function bot_army_set_directive(
  p_enabled boolean, p_count int, p_mode text, p_target uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not is_admin_user() then raise exception 'not authorized'; end if;
  if p_mode not in ('matchmaking','arena','tournament','free') then
    raise exception 'mode invalide: %', p_mode;
  end if;
  update bot_army_control
     set enabled    = p_enabled,
         count      = greatest(0, least(coalesce(p_count,0), 100)),  -- cap dur à 100
         mode       = p_mode,
         target_id  = p_target,
         updated_by = auth.uid(),
         updated_at = now()
   where id = 1;
  return jsonb_build_object('ok', true);
end $$;

-- ── 5. RPC admin : lire l'état + le rapport (pour le menu dev) ─────
drop function if exists bot_army_get_report();
create or replace function bot_army_get_report()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not is_admin_user() then raise exception 'not authorized'; end if;
  return jsonb_build_object(
    'control',  (select row_to_json(c) from bot_army_control c where c.id = 1),
    'report',   coalesce((select jsonb_agg(row_to_json(r) order by r.mode)
                          from bot_army_report r), '[]'::jsonb),
    'bot_count',(select count(*) from profiles where is_bot)
  );
end $$;

-- ── 6. RPC admin : purge des artefacts applicatifs des bots ────────
--    NB : la suppression des comptes auth.users (+ profiles) est faite
--    par le worker via l'API admin service_role. Ici on retire ce qui
--    ne casque pas forcément (membres de ligue), on vide le rapport et
--    on coupe la directive.
drop function if exists bot_army_purge();
create or replace function bot_army_purge()
returns jsonb language plpgsql security definer set search_path=public as $$
declare n_lm int;
begin
  if not is_admin_user() then raise exception 'not authorized'; end if;
  delete from league_members lm using profiles p
    where p.id = lm.player_id and p.is_bot;
  get diagnostics n_lm = row_count;
  delete from bot_army_report;
  update bot_army_control set enabled = false, count = 0, updated_at = now() where id = 1;
  return jsonb_build_object('ok', true, 'league_members_removed', n_lm);
end $$;

-- ══════════════════════════════════════════════════════════════════
-- 7. EXCLUSION DES BOTS DE LA LIGUE
--    Redéfinit 3 fonctions de league_weekly.sql en y ajoutant le garde
--    is_bot. À exécuter APRÈS league_weekly.sql (supersède ces versions).
--    (a) un bot ne rejoint JAMAIS un pool  → league_ensure_membership
--    (b) un bot ne gagne JAMAIS de points  → award_league_points
--    (c) filet de sécurité à l'affichage    → get_my_league_standings
-- ══════════════════════════════════════════════════════════════════

drop function if exists league_ensure_membership();
create or replace function league_ensure_membership()
returns uuid
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); sid uuid; pid uuid; mid uuid; cnt int; pr record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  -- 🤖 garde bots : pas d'inscription en ligue (ni pool, ni points, ni classement)
  if exists (select 1 from profiles where id = uid and is_bot) then return null; end if;
  select id into sid from league_current_season();

  select lm.id into mid from league_members lm
    join league_pools lp on lp.id = lm.pool_id
    where lp.season_id = sid and lm.player_id = uid limit 1;
  if mid is not null then return mid; end if;

  for pr in select id from league_pools where season_id = sid loop
    select count(*) into cnt from league_members where pool_id = pr.id;
    if cnt < 100 then
      insert into league_members(pool_id, player_id, points) values (pr.id, uid, 0) returning id into mid;
      return mid;
    end if;
  end loop;

  insert into league_pools(season_id) values (sid) returning id into pid;
  insert into league_members(pool_id, player_id, points) values (pid, uid, 0) returning id into mid;
  return mid;
end $$;

drop function if exists award_league_points(int);
create or replace function award_league_points(p_timer_seconds int)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); mid uuid; pts int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  -- 🤖 garde bots : aucun point de ligue
  if exists (select 1 from profiles where id = uid and is_bot) then
    return jsonb_build_object('ok', true, 'added', 0, 'bot', true);
  end if;
  pts := case p_timer_seconds when 3 then 3 when 5 then 2 when 10 then 1 else 1 end;
  mid := league_ensure_membership();
  update league_members set points = points + pts where id = mid;
  return jsonb_build_object('ok', true, 'added', pts);
end $$;

drop function if exists get_my_league_standings();
create or replace function get_my_league_standings()
returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); mid uuid; pid uuid; eat date; rows jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  mid := league_ensure_membership();
  select pool_id into pid from league_members where id = mid;
  select ls.ends_at into eat from league_pools lp
    join league_seasons ls on ls.id = lp.season_id where lp.id = pid;

  select coalesce(jsonb_agg(row_to_json(x) order by x.points desc), '[]'::jsonb) into rows from (
    select lm.player_id, lm.points, p.pseudo
    from league_members lm join profiles p on p.id = lm.player_id
    where lm.pool_id = pid and not p.is_bot   -- 🤖 filet : jamais de bot au classement
  ) x;

  return jsonb_build_object('tier', 0, 'ends_at', eat, 'members', rows);
end $$;

-- ── Contrôle ──────────────────────────────────────────────────────
select
  to_regproc('public.bot_army_set_directive')::text as fn_directive,
  to_regproc('public.bot_army_get_report')::text    as fn_report,
  to_regproc('public.bot_army_purge')::text         as fn_purge,
  (select count(*) from information_schema.columns
     where table_name='profiles' and column_name='is_bot')      as has_is_bot;
