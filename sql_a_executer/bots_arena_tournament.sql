-- ══════════════════════════════════════════════════════════════════
-- BOT-ARMY — les bots jouent partout : ARÈNE (backfill amical) + TOURNOI
-- (le créateur complète les slots vides avec l'armée des bots, qui jouent
-- réellement leurs matchs). Complète bot_team15.sql / add_backfill_random.sql.
-- Idempotent. À exécuter en une fois.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Arène : file de matchmaking d'arène apte au backfill ─────────
-- Mêmes préférences que la file classique (add_backfill_random.sql), pour
-- qu'un joueur d'arène qui poireaute puisse être rejoint par un bot d'Elo
-- voisin. `elo` existe déjà sur cette table. Backfill = parties AMICALES
-- (le worker crée un arena_matches ranked=false).
alter table arena_matchmaking_queue add column if not exists want_backfill  boolean not null default false;
alter table arena_matchmaking_queue add column if not exists backfill_after  integer;
alter table arena_matchmaking_queue add column if not exists backfill_random boolean not null default false;
alter table arena_matchmaking_queue add column if not exists backfill_max_elo integer;

-- ── 2. Tournoi : le créateur complète les slots vides avec des bots ──
-- Réservé au créateur (ou admin), uniquement tant que les inscriptions sont
-- ouvertes ('open'). On n'ajoute QUE les 15 fragments (01→15) : le Rōnin (00)
-- reste hors-tournoi (boss caché). Les bots jouent ensuite réellement leurs
-- rondes — le worker pilote les parties des paires qui en contiennent un et
-- reporte le résultat (tournament_report_from_game, sans garde auth.uid()).
create or replace function public.tournament_fill_with_bots(p_tournament_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare uid uuid := auth.uid(); t record; adm boolean; slots int; added int := 0; b record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into t from tournaments where id = p_tournament_id;
  if t is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select coalesce(is_admin,false) into adm from profiles where id = uid;
  if t.created_by <> uid and not coalesce(adm,false) then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;
  if t.status <> 'open' then
    return jsonb_build_object('ok', false, 'reason', 'already_started');
  end if;
  slots := t.max_players - (select count(*) from tournament_participants where tournament_id = p_tournament_id);
  if slots <= 0 then return jsonb_build_object('ok', true, 'added', 0, 'reason', 'full'); end if;

  for b in
    select br.profile_id
    from bot_roster br
    where br.num between '01' and '15'          -- fragments seulement, pas le Rōnin (00)
      and br.profile_id is not null
      and not exists (
        select 1 from tournament_participants tp
        where tp.tournament_id = p_tournament_id and tp.player_id = br.profile_id
      )
    order by br.sort
    limit slots
  loop
    insert into tournament_participants(tournament_id, player_id, score, wins, byes, abandoned, missed)
      values (p_tournament_id, b.profile_id, 0, 0, 0, false, 0);
    added := added + 1;
  end loop;

  return jsonb_build_object('ok', true, 'added', added, 'slots', slots);
end $function$;

grant execute on function public.tournament_fill_with_bots(bigint) to authenticated;

-- Contrôle : la fonction existe, colonnes d'arène présentes.
select
  (select count(*) from information_schema.columns
     where table_schema='public' and table_name='arena_matchmaking_queue' and column_name='want_backfill') as arena_want_backfill,
  (select count(*) from pg_proc where proname='tournament_fill_with_bots') as fill_fn;
