-- ═══════════════════════════════════════════════════════════════════
-- CONSTITUTION DES ÉQUIPES + SALLE D'ATTENTE — lot G3
-- docs/ROADMAP_GUILD_BATTLE.md § 7
--
-- Prend le relais du lot G2 (planification + inscriptions) : répartition
-- des inscrits en deux équipes, salle d'attente + check-in. S'ARRÊTE au
-- statut 'running' avec current_seat_a/b = 1 — le lot G4 prendra le relais
-- pour jouer réellement les duels.
--
-- Décisions appliquées :
--  A — l'Elo (figé à l'inscription, lot G2) sert DEUX fois : il équilibre
--      les équipes (serpentin) ET fixe l'ordre de passage (le plus faible
--      ouvre, le plus fort ferme la marche en « boss »). Le serveur calcule
--      TOUJOURS l'ordre depuis l'Elo — le GM ne choisit que la répartition
--      en équipes (glisser-déposer), jamais l'ordre de passage.
--  K — la salle d'attente/check-in ouvre 5 min avant le début ; qui ne
--      confirme pas est absent au lancement.
--  L — un absent au check-in est retiré de la composition, son équipe
--      continue avec un joueur de moins (décision G : tailles asymétriques
--      autorisées).
--  O — minimum 3 joueurs par équipe pour lancer un tournoi interne.
-- ═══════════════════════════════════════════════════════════════════

-- ── Répartition automatique en serpentin (GM) ──────────────────────────
-- Trie les inscrits par Elo décroissant, distribue en serpentin (A,B,B,A,
-- A,B,B,A…) pour équilibrer la force totale des deux équipes, PUIS fixe le
-- seat de chacun = son rang croissant d'Elo AU SEIN de son équipe (1 = le
-- plus faible ouvre, N = le plus fort ferme en boss — décision A).
create or replace function public.guild_event_autobalance_teams(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  uid uuid := auth.uid(); ev record; myrole text; total int;
  r record; idx int := 0; side text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select role into myrole from guild_members where guild_id = ev.guild_a and player_id = uid;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if ev.status <> 'registration_closed' then return jsonb_build_object('ok', false, 'reason', 'wrong_status'); end if;

  select count(*) into total from guild_event_participants where event_id = p_event_id;
  if total < 6 then return jsonb_build_object('ok', false, 'reason', 'not_enough_players', 'total', total); end if;

  -- Serpentin : parcourt les inscrits par Elo décroissant, alterne le côté
  -- qui pioche en premier à chaque paire (A,B puis B,A puis A,B…).
  for r in select player_id from guild_event_participants where event_id = p_event_id order by elo desc, player_id loop
    side := case
      when idx % 4 = 0 then 'A'
      when idx % 4 = 1 then 'B'
      when idx % 4 = 2 then 'B'
      else 'A'
    end;
    update guild_event_participants set team = side where event_id = p_event_id and player_id = r.player_id;
    idx := idx + 1;
  end loop;

  -- Ordre de passage : rang croissant d'Elo au sein de CHAQUE équipe.
  update guild_event_participants gep set seat = ranked.rk
    from (
      select player_id, row_number() over (partition by team order by elo asc, player_id) as rk
      from guild_event_participants where event_id = p_event_id
    ) ranked
    where gep.event_id = p_event_id and gep.player_id = ranked.player_id;

  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_autobalance_teams(bigint) to authenticated;

-- ── Déplacer un joueur d'équipe (GM, glisser-déposer) ──────────────────
-- Recalcule ensuite le seat des DEUX équipes touchées — l'ordre de passage
-- reste toujours dérivé de l'Elo, jamais choisi à la main (décision A).
create or replace function public.guild_event_move_player(p_event_id bigint, p_player_id uuid, p_team text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; myrole text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_team not in ('A','B') then return jsonb_build_object('ok', false, 'reason', 'bad_team'); end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select role into myrole from guild_members where guild_id = ev.guild_a and player_id = uid;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if ev.status <> 'registration_closed' then return jsonb_build_object('ok', false, 'reason', 'wrong_status'); end if;
  if not exists (select 1 from guild_event_participants where event_id = p_event_id and player_id = p_player_id) then
    return jsonb_build_object('ok', false, 'reason', 'not_registered');
  end if;

  update guild_event_participants set team = p_team where event_id = p_event_id and player_id = p_player_id;

  update guild_event_participants gep set seat = ranked.rk
    from (
      select player_id, row_number() over (partition by team order by elo asc, player_id) as rk
      from guild_event_participants where event_id = p_event_id and team is not null
    ) ranked
    where gep.event_id = p_event_id and gep.player_id = ranked.player_id;

  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_move_player(bigint, uuid, text) to authenticated;

-- ── Check-in (le joueur confirme sa présence) ──────────────────────────
create or replace function public.guild_event_checkin(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if ev.status <> 'checkin' then return jsonb_build_object('ok', false, 'reason', 'wrong_status'); end if;
  if not exists (select 1 from guild_event_participants where event_id = p_event_id and player_id = uid) then
    return jsonb_build_object('ok', false, 'reason', 'not_registered');
  end if;
  update guild_event_participants set checked_in = true where event_id = p_event_id and player_id = uid;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_checkin(bigint) to authenticated;

-- ── Lecture détaillée d'un événement (roster complet, équipes, check-in) ──
create or replace function public.guild_event_state(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; ev record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id into gid from guild_members where player_id = uid;
  select * into ev from guild_events where id = p_event_id and (guild_a = gid or guild_b = gid);
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  return jsonb_build_object(
    'ok', true,
    'event', jsonb_build_object(
      'id', ev.id, 'status', ev.status, 'cadence', ev.cadence, 'starts_at', ev.starts_at,
      'registration_closes_at', ev.registration_closes_at, 'created_by', ev.created_by,
      'winner_guild', ev.winner_guild, 'current_seat_a', ev.current_seat_a, 'current_seat_b', ev.current_seat_b,
      'streak_count', ev.streak_count
    ),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'player_id', gep.player_id, 'pseudo', p.pseudo, 'team', gep.team, 'seat', gep.seat,
        'elo', gep.elo, 'checked_in', gep.checked_in, 'eliminated_at', gep.eliminated_at, 'wins', gep.wins
      ) order by gep.team, gep.seat nulls last, p.pseudo)
      from guild_event_participants gep join profiles p on p.id = gep.player_id
      where gep.event_id = ev.id
    ), '[]'::jsonb)
  );
end $$;
grant execute on function public.guild_event_state(bigint) to authenticated;

-- ── Tick pg_cron : ouverture puis clôture du check-in ──────────────────
create or replace function public.guild_events_checkin_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare ev record; opened int := 0; started int := 0; noshow int;
begin
  -- Ouverture 5 min avant le début (décision K). Un événement dont les
  -- équipes n'ont jamais été formées (GM inactif) reste en
  -- 'registration_closed' — on n'ouvre le check-in QUE si des équipes
  -- existent, sinon l'événement est silencieusement abandonné au tick
  -- suivant (rien à annoncer sans composition).
  for ev in
    select * from guild_events
    where status = 'registration_closed' and now() >= starts_at - interval '5 minutes'
      and exists (select 1 from guild_event_participants where event_id = guild_events.id and team is not null)
  loop
    update guild_events set status = 'checkin', updated_at = now() where id = ev.id;
    insert into notifications(user_id, type, title, body, read, payload)
    select gep.player_id, 'guild_event_starting', '🚪 Check-in ouvert !',
      'Le tournoi interne commence dans 5 minutes — confirme ta présence maintenant.',
      false, jsonb_build_object('event_id', ev.id)
    from guild_event_participants gep where gep.event_id = ev.id;
    opened := opened + 1;
  end loop;

  -- Clôture à l'heure dite : les non-confirmés sont retirés (décision L),
  -- puis lancement (le lot G4 prend le relais depuis status='running').
  for ev in select * from guild_events where status = 'checkin' and now() >= starts_at loop
    delete from guild_event_participants where event_id = ev.id and checked_in = false;
    get diagnostics noshow = row_count;
    -- Renumérote le seat de chaque équipe après le retrait des absents (le
    -- premier présent hérite du seat 1, sans trou dans la séquence).
    update guild_event_participants gep set seat = ranked.rk
      from (
        select player_id, row_number() over (partition by team order by seat asc) as rk
        from guild_event_participants where event_id = ev.id
      ) ranked
      where gep.event_id = ev.id and gep.player_id = ranked.player_id;

    if not exists (select 1 from guild_event_participants where event_id = ev.id and team = 'A')
       or not exists (select 1 from guild_event_participants where event_id = ev.id and team = 'B') then
      -- Une équipe s'est vidée : le tournoi ne peut pas se jouer.
      update guild_events set status = 'cancelled', updated_at = now() where id = ev.id;
    else
      update guild_events set status = 'running', current_seat_a = 1, current_seat_b = 1, updated_at = now() where id = ev.id;
    end if;
    started := started + 1;
  end loop;

  return jsonb_build_object('opened', opened, 'started', started);
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'guild_events_checkin_tick') then
    perform cron.unschedule('guild_events_checkin_tick');
  end if;
end $$;
select cron.schedule('guild_events_checkin_tick', '20 seconds', $$select public.guild_events_checkin_tick();$$);

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regproc('public.guild_event_autobalance_teams')::text as fn_autobalance, -- attendu non-null
  to_regproc('public.guild_event_move_player')::text as fn_move,              -- attendu non-null
  to_regproc('public.guild_event_checkin')::text as fn_checkin,               -- attendu non-null
  to_regproc('public.guild_event_state')::text as fn_state,                   -- attendu non-null
  to_regproc('public.guild_events_checkin_tick')::text as fn_tick,            -- attendu non-null
  (select count(*) from cron.job where jobname = 'guild_events_checkin_tick') as cron_scheduled, -- attendu 1
  'guild_events_g3 OK' as status;
