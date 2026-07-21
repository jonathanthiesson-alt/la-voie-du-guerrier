-- ══════════════════════════════════════════════════════════════════
-- LIGUE — RPC manquantes (reconstruites le 2026-07-21)
--
-- Constat : les tables league_seasons/league_pools/league_members/
-- league_channel_messages existaient déjà en base, RLS + politiques
-- comprises — mais AUCUNE des deux fonctions RPC dont le client a
-- besoin (get_my_league_standings, award_league_points) n'existait.
-- Le script original qui devait les créer n'a jamais été retrouvé
-- dans le dépôt (jamais commité, comme tournament_award_podium avant
-- lui) : "Ligue indisponible" est le message d'erreur EXACT que le
-- client affiche quand get_my_league_standings() échoue.
--
-- Saison = mois calendaire (le client attend ends_at = fin de mois,
-- voir ensureCurrentLeagueSeason côté JS). Pool = groupe de ~100
-- joueurs, jointure paresseuse au premier appel.
--
-- ⚠ Pas de colonne "division/tier" persistée nulle part : le système
-- de divisions (Bois → Dragon) et la promotion/relégation hebdo
-- décrits dans ROADMAP.md ne sont PAS implémentés ici — seuls le
-- classement par pool et les points le sont. tier renvoie 0 (Bois)
-- pour tout le monde en attendant.
--
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════

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
    insert into league_seasons(starts_at, ends_at)
    values (
      date_trunc('month', today)::date,
      (date_trunc('month', today) + interval '1 month' - interval '1 day')::date
    )
    returning * into s;
  end if;
  return query select s.id, s.ends_at;
end $$;

-- Jointure paresseuse : renvoie l'id de membership du joueur courant
-- pour la saison en cours, en le créant (et en créant un pool si
-- besoin) s'il n'est pas encore inscrit.
drop function if exists league_ensure_membership();
create or replace function league_ensure_membership()
returns uuid
language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); sid uuid; pid uuid; mid uuid; cnt int; pr record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
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

-- ── Classement de mon pool (appelle la jointure paresseuse si besoin) ──
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
    where lm.pool_id = pid
  ) x;

  return jsonb_build_object('tier', 0, 'ends_at', eat, 'members', rows);
end $$;

-- ── Points de victoire (jamais de défaite) : 3s=3, 5s=2, 10s=1 ──
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
  to_regproc('public.get_my_league_standings')::text as fn_standings,
  to_regproc('public.award_league_points')::text     as fn_award,
  to_regproc('public.league_ensure_membership')::text as fn_membership;
