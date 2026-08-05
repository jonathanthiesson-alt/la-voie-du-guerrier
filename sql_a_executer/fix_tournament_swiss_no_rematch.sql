-- ══════════════════════════════════════════════════════════════════
-- FIX — appariement suisse : ÉVITER LES REVANCHES
--
-- Bug : tournament_start_next_round triait par (score, wins) et appariait
-- bêtement les voisins du classement (1-2, 3-4, …), SANS vérifier qui avait
-- déjà joué contre qui → on pouvait retomber sur le même adversaire à chaque
-- ronde (vécu : Wurmz vs 12-Daimyo aux rondes 1, 2 et 3).
--
-- Correctif : appariement glouton dans l'ordre du classement, mais on choisit
-- pour chaque joueur le PREMIER adversaire disponible qu'il N'A PAS ENCORE
-- affronté. Si tous les restants ont déjà été joués (petits tournois, rondes
-- nombreuses), on autorise la revanche en dernier recours (fallback). Le bye
-- (joueur surnuméraire) ne survient que pour un effectif impair.
-- Idempotent. Ne touche QUE la logique d'appariement (étape 4).
-- ══════════════════════════════════════════════════════════════════

create or replace function public.tournament_start_next_round(p_tournament_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare t record; rnd int; arr uuid[]; used boolean[]; i int; j int; a uuid; b uuid; wid uuid; bid uuid;
        existing int; nb int; prm jsonb; needed int; cap_rounds int; n int; partner int; fallback int;
begin
  select * into t from tournaments where id = p_tournament_id for update;
  if t is null then raise exception 'tournament not found'; end if;
  if t.status = 'finished' then return jsonb_build_object('ok', false, 'reason', 'finished'); end if;

  -- 1. On solde d'abord les parties non terminées de la ronde en cours.
  perform tournament_resolve_timeouts(p_tournament_id);

  -- 2. Toutes les parties de la ronde courante sont-elles conclues ?
  if t.current_round > 0 then
    select count(*) into existing from tournament_pairings
      where tournament_id = p_tournament_id and round = t.current_round and result is null;
    if existing > 0 then
      return jsonb_build_object('ok', false, 'reason', 'round_in_progress',
                                'pending', existing, 'deadline', t.round_deadline);
    end if;
  end if;

  rnd := t.current_round + 1;
  select count(*) into existing from tournament_pairings
    where tournament_id = p_tournament_id and round = rnd;
  if existing > 0 then return jsonb_build_object('ok', true, 'round', rnd, 'already', true); end if;

  -- 3. Au lancement de la 1re ronde : on FIGE le nombre de rondes.
  if rnd = 1 then
    select count(*) into nb from tournament_participants where tournament_id = p_tournament_id;
    if nb < 2 then return jsonb_build_object('ok', false, 'reason', 'not_enough_players'); end if;
    prm := tournament_cadence_params(t.timer_seconds);
    cap_rounds := (prm->>'max_rounds')::int;
    needed := greatest(2, ceil(log(2, nb::numeric))::int);
    if needed > cap_rounds then needed := cap_rounds; end if;
    update tournaments set total_rounds = needed where id = p_tournament_id;
    t.total_rounds := needed;
  end if;

  if rnd > t.total_rounds then
    update tournaments set status = 'finished', round_deadline = null where id = p_tournament_id;
    perform tournament_award_podium(p_tournament_id);
    return jsonb_build_object('ok', true, 'finished', true);
  end if;

  -- 4. Appariement suisse AVEC évitement des revanches — abandonnistes exclus.
  select array_agg(player_id order by score desc, wins desc) into arr
    from tournament_participants
    where tournament_id = p_tournament_id and abandoned = false;
  if arr is null or array_length(arr,1) < 2 then
    update tournaments set status = 'finished', round_deadline = null where id = p_tournament_id;
    perform tournament_award_podium(p_tournament_id);
    return jsonb_build_object('ok', true, 'finished', true, 'reason', 'not_enough_active');
  end if;

  n := array_length(arr,1);
  used := array_fill(false, array[n]);
  for i in 1..n loop
    if used[i] then continue; end if;
    a := arr[i];
    partner := null; fallback := null;
    -- Cherche le 1er adversaire libre encore JAMAIS affronté (fallback = 1er libre).
    for j in i+1..n loop
      if used[j] then continue; end if;
      if fallback is null then fallback := j; end if;
      if not exists (
        select 1 from tournament_pairings pp
        where pp.tournament_id = p_tournament_id
          and coalesce(pp.result,'') <> 'bye'
          and ((pp.white_id = a and pp.black_id = arr[j])
            or (pp.white_id = arr[j] and pp.black_id = a))
      ) then partner := j; exit; end if;
    end loop;
    if partner is null then partner := fallback; end if;  -- revanche inévitable
    if partner is null then
      -- effectif impair : dernier joueur non apparié → bye
      used[i] := true;
      insert into tournament_pairings(tournament_id, round, white_id, black_id, result)
        values (p_tournament_id, rnd, a, null, 'bye');
      update tournament_participants set score = score + 1, byes = byes + 1
        where tournament_id = p_tournament_id and player_id = a;
    else
      used[i] := true; used[partner] := true;
      b := arr[partner];
      if (rnd % 2) = 1 then wid := a; bid := b; else wid := b; bid := a; end if;
      insert into tournament_pairings(tournament_id, round, white_id, black_id)
        values (p_tournament_id, rnd, wid, bid);
    end if;
  end loop;

  -- 5. Délai limite de la ronde.
  update tournaments set
    current_round = rnd,
    status = 'running',
    round_deadline = now() + (coalesce(t.round_minutes,4) || ' minutes')::interval
    where id = p_tournament_id;

  return jsonb_build_object('ok', true, 'round', rnd, 'total_rounds', t.total_rounds,
                            'deadline_minutes', coalesce(t.round_minutes,4));
end $function$;
