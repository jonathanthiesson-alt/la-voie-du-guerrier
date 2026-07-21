-- ══════════════════════════════════════════════════════════════════
-- LIGUE — divisions + promotion/relégation hebdomadaire
--
-- league_weekly.sql (2026-07-21) avait reconstruit les RPC manquantes
-- mais avec un modèle simplifié : saison mensuelle, pool générique de
-- 100 joueurs, tier toujours à 0. Or le texte de règles déjà affiché
-- au joueur (MODE_INFO.league, écran ⓘ) promet TOUT AUTRE CHOSE :
--   - Cycle HEBDOMADAIRE, reset le dimanche
--   - Groupes d'~50 joueurs de LA MÊME DIVISION
--   - Divisions Bois → Pierre → Bronze → Argent → Or → Jade → Dragon
--   - Les 3 premiers du groupe montent, les 3 derniers descendent
-- Le client (LEAGUE_TIERS, banner par tier, league_week_label) était
-- déjà câblé pour ce système — seul le serveur ne le faisait pas.
--
-- Ce script remplace le modèle mensuel par le modèle hebdomadaire
-- documenté, avec la division stockée sur profiles (persiste d'une
-- semaine à l'autre, contrairement aux points qui repartent à 0).
--
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════

alter table profiles add column if not exists league_division smallint not null default 0;
alter table league_pools add column if not exists division smallint not null default 0;
alter table league_seasons add column if not exists resolved boolean not null default false;

-- La seule saison de test créée avant ce script avait des bornes
-- mensuelles (ancien modèle) : on les réaligne sur la semaine en
-- cours pour que "reset dimanche" soit vrai dès maintenant.
update league_seasons
  set starts_at = date_trunc('week', current_date)::date,
      ends_at   = (date_trunc('week', current_date) + interval '6 days')::date
  where ends_at > current_date + interval '7 days';

-- ── Résout les semaines terminées mais pas encore traitées : classe
-- chaque pool, promeut le top 3, relègue le bottom 3. Pools de moins
-- de 6 joueurs ignorés (top 3 et bottom 3 se chevaucheraient).
drop function if exists league_resolve_pending_weeks();
create or replace function league_resolve_pending_weeks()
returns void language plpgsql security definer set search_path=public as $$
declare se record; p record; r record; rk int; total int;
begin
  for se in select * from league_seasons where ends_at < current_date and resolved = false loop
    for p in select * from league_pools where season_id = se.id loop
      select count(*) into total from league_members where pool_id = p.id;
      if total >= 6 then
        rk := 0;
        for r in select player_id from league_members where pool_id = p.id order by points desc loop
          rk := rk + 1;
          if rk <= 3 then
            update profiles set league_division = least(6, league_division + 1) where id = r.player_id;
          elsif rk > total - 3 then
            update profiles set league_division = greatest(0, league_division - 1) where id = r.player_id;
          end if;
        end loop;
      end if;
    end loop;
    update league_seasons set resolved = true where id = se.id;
  end loop;
end $$;

-- ── Saison en cours (semaine ISO : lundi → dimanche). Résout les
-- semaines en attente avant d'en ouvrir une nouvelle.
drop function if exists league_current_season();
create or replace function league_current_season()
returns table(id uuid, ends_at date)
language plpgsql security definer set search_path=public as $$
declare s record; today date := current_date;
begin
  select * into s from league_seasons
    where starts_at <= today and ends_at >= today
    order by starts_at desc limit 1;
  if s is null then
    perform league_resolve_pending_weeks();
    insert into league_seasons(starts_at, ends_at)
    values (
      date_trunc('week', today)::date,
      (date_trunc('week', today) + interval '6 days')::date
    )
    returning * into s;
  end if;
  return query select s.id, s.ends_at;
end $$;

-- ── Jointure paresseuse : pool de MÊME DIVISION, plafonné à 50.
drop function if exists league_ensure_membership();
create or replace function league_ensure_membership()
returns uuid
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); sid uuid; pid uuid; mid uuid; cnt int; pr record; mydiv smallint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select id into sid from league_current_season();
  select coalesce(league_division, 0) into mydiv from profiles where id = uid;

  select lm.id into mid from league_members lm
    join league_pools lp on lp.id = lm.pool_id
    where lp.season_id = sid and lm.player_id = uid limit 1;
  if mid is not null then return mid; end if;

  for pr in select id from league_pools where season_id = sid and division = mydiv loop
    select count(*) into cnt from league_members where pool_id = pr.id;
    if cnt < 50 then
      insert into league_members(pool_id, player_id, points) values (pr.id, uid, 0) returning id into mid;
      return mid;
    end if;
  end loop;

  insert into league_pools(season_id, division) values (sid, mydiv) returning id into pid;
  insert into league_members(pool_id, player_id, points) values (pid, uid, 0) returning id into mid;
  return mid;
end $$;

-- ── Classement de mon pool : tier = la vraie division du pool.
drop function if exists get_my_league_standings();
create or replace function get_my_league_standings()
returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); mid uuid; pid uuid; eat date; div smallint; rows jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  mid := league_ensure_membership();
  select pool_id into pid from league_members where id = mid;
  select ls.ends_at, lp.division into eat, div from league_pools lp
    join league_seasons ls on ls.id = lp.season_id where lp.id = pid;

  select coalesce(jsonb_agg(row_to_json(x) order by x.points desc), '[]'::jsonb) into rows from (
    select lm.player_id, lm.points, p.pseudo
    from league_members lm join profiles p on p.id = lm.player_id
    where lm.pool_id = pid
  ) x;

  return jsonb_build_object('tier', div, 'ends_at', eat, 'members', rows);
end $$;

-- award_league_points n'a pas besoin de changer : il appelle déjà
-- league_ensure_membership, qui est maintenant conscient de la
-- division. Recréée quand même pour rester groupée avec le reste.
drop function if exists award_league_points(int);
create or replace function award_league_points(p_timer_seconds int)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); mid uuid; pts int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  pts := case p_timer_seconds when 3 then 3 when 5 then 2 when 10 then 1 else 1 end;
  mid := league_ensure_membership();
  update league_members set points = points + pts where id = mid;
  return jsonb_build_object('ok', true, 'added', pts);
end $$;

-- ── Contrôle ──────────────────────────────────────────────────────
select
  to_regproc('public.league_resolve_pending_weeks')::text as fn_resolve,
  to_regproc('public.get_my_league_standings')::text      as fn_standings,
  (select count(*) from information_schema.columns
     where table_name='profiles' and column_name='league_division')   as col_division,
  (select count(*) from information_schema.columns
     where table_name='league_pools' and column_name='division')      as col_pool_division,
  (select count(*) from information_schema.columns
     where table_name='league_seasons' and column_name='resolved')    as col_resolved;
