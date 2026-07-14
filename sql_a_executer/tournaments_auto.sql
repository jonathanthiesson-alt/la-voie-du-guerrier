-- ═══════════════════════════════════════════════════════════════════
-- Automatisation serveur des tournois (pg_cron) + clôture des
-- inscriptions réservée au créateur + liste des matchs de la ronde.
--
-- À exécuter dans l'éditeur SQL Supabase, EN UNE FOIS (transaction
-- unique : si la dernière instruction échoue, tout est annulé).
-- ═══════════════════════════════════════════════════════════════════

-- 1. Nouvelle RPC : clôture des inscriptions + lancement de la ronde 1.
--    Remplace l'usage direct de tournament_start_next_round par les
--    clients pour la ronde 1 — SEUL le créateur (ou un admin) peut
--    déclencher ce passage 'open' → 'running'.
create or replace function public.tournament_close_registration(p_tournament_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); t record; adm boolean;
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
  return tournament_start_next_round(p_tournament_id);
end $function$;

grant execute on function public.tournament_close_registration(bigint) to authenticated;

-- 2. tournament_start_next_round ne doit plus être appelable directement
--    par un client — seuls tournament_close_registration (créateur/admin,
--    ronde 1) et tournament_cleanup (rondes suivantes, moteur serveur)
--    doivent pouvoir l'invoquer. Les deux tournent en SECURITY DEFINER
--    (propriétaire = postgres), donc cette révocation ne les affecte pas :
--    seul un appel RPC direct depuis un client authentifié est bloqué.
revoke execute on function public.tournament_start_next_round(bigint) from authenticated, anon;

-- 3. tournament_resolve_timeouts : délai de grâce de 90 s après
--    l'échéance de la ronde avant de solder un match en double-forfait.
--    Ça laisse au joueur PRÉSENT le temps de cliquer « Réclamer la
--    victoire » (tournament_claim_forfeit, qui désigne correctement
--    l'absent) avant que le tick serveur ne traite les deux joueurs à
--    égalité par défaut.
create or replace function public.tournament_resolve_timeouts(p_tournament_id bigint)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare t record; pr record; n int := 0;
begin
  select * into t from tournaments where id = p_tournament_id;
  if t is null or t.round_deadline is null then return 0; end if;
  if now() < t.round_deadline + interval '90 seconds' then return 0; end if;

  for pr in
    select * from tournament_pairings
    where tournament_id = p_tournament_id and round = t.current_round and result is null
  loop
    -- Aucun des deux n'a joué / reporté → double abandon.
    update tournament_pairings set result = 'timeout' where id = pr.id;
    update tournament_participants
      set missed = missed + 1, abandoned = true
      where tournament_id = p_tournament_id
        and player_id in (pr.white_id, pr.black_id);
    n := n + 1;
  end loop;
  return n;
end $function$;

-- 4. tournament_standings : expose created_by, nécessaire côté client
--    pour n'afficher le bouton de clôture qu'au créateur.
create or replace function public.tournament_standings(p_tournament_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare rows jsonb; tinfo jsonb; nb int;
begin
  perform tournament_resolve_timeouts(p_tournament_id);

  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into rows from (
    select pr.pseudo, tp.player_id, tp.score, tp.wins, tp.abandoned
    from tournament_participants tp join profiles pr on pr.id = tp.player_id
    where tp.tournament_id = p_tournament_id
    order by tp.abandoned asc, tp.score desc, tp.wins desc
  ) x;

  select count(*) into nb from tournament_participants where tournament_id = p_tournament_id;

  select jsonb_build_object('id', id, 'name', name, 'status', status,
                            'total_rounds', total_rounds, 'current_round', current_round,
                            'timer_seconds', timer_seconds, 'max_players', max_players,
                            'round_minutes', round_minutes, 'round_deadline', round_deadline,
                            'created_by', created_by,
                            'players', nb)
    into tinfo from tournaments where id = p_tournament_id;

  return jsonb_build_object('tournament', tinfo, 'standings', rows);
end $function$;

-- 5. Nouvelle RPC : liste des matchs d'une ronde (en cours / en attente /
--    terminés), pour l'écran « état de la ronde ».
create or replace function public.tournament_round_matches(p_tournament_id bigint, p_round integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare rows jsonb;
begin
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into rows from (
    select pr.id as pairing_id, pr.result, pr.online_game_id,
           wp.pseudo as white_pseudo, bp.pseudo as black_pseudo,
           case
             when pr.result = 'bye' then 'bye'
             when pr.result is not null then 'finished'
             when pr.online_game_id is not null then 'ongoing'
             else 'pending'
           end as state
    from tournament_pairings pr
    left join profiles wp on wp.id = pr.white_id
    left join profiles bp on bp.id = pr.black_id
    where pr.tournament_id = p_tournament_id and pr.round = p_round
    order by state, pr.id
  ) x;
  return jsonb_build_object('ok', true, 'matches', coalesce(rows, '[]'::jsonb));
end $function$;

grant execute on function public.tournament_round_matches(bigint, integer) to authenticated;

-- 6. Automatisation planifiée : pg_cron exécute tournament_cleanup()
--    toutes les 20 secondes, sans dépendre d'un client connecté pour
--    faire avancer les tournois (forfaits, rondes suivantes, clôture).
create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'tournament_cleanup_tick') then
    perform cron.unschedule('tournament_cleanup_tick');
  end if;
end $$;

select cron.schedule('tournament_cleanup_tick', '20 seconds', $$select public.tournament_cleanup();$$);
