-- ═══════════════════════════════════════════════════════════════════
-- CONFRONTATION AMICALE — lot G6, docs/ROADMAP_GUILD_BATTLE.md § 7
--
-- Réutilise le moteur du Tournoi interne (G2→G5) avec DEUX guildes au lieu
-- d'une : déclaration par le chef A, acceptation du chef B, planification
-- à 48h max (décision T). « Même cérémonial que l'attaque — seule la
-- conséquence change » : ici, aucune (décision H, toujours vrai).
--
-- Différence structurelle avec le Tournoi interne : l'équipe n'est PAS
-- répartie par le chef (autobalance) — elle est fixée par l'appartenance
-- de guilde dès l'inscription (guild_a → équipe A, guild_b → équipe B).
-- Seul l'ORDRE de passage reste dérivé de l'Elo (décision A), calculé
-- automatiquement à la clôture des inscriptions.
-- ═══════════════════════════════════════════════════════════════════

-- guild_events.status gagne un état supplémentaire : la proposition
-- attend la réponse du chef adverse avant que quoi que ce soit ne
-- s'ouvre (pas de 'scheduled' tant que ce n'est pas accepté).
alter table public.guild_events drop constraint if exists guild_events_status_check;
alter table public.guild_events add constraint guild_events_status_check
  check (status in ('pending_acceptance','scheduled','registration_closed','checkin','running','finished','cancelled'));

-- ── Proposer une Confrontation amicale (chef uniquement) ────────────────
-- registration_closes_at est TOUJOURS starts_at - 5 min (même marge que le
-- check-in, décision K) : fixé une fois pour toutes à la proposition, pas
-- de second paramètre à faire coïncider avec une acceptation à venir.
create or replace function public.guild_event_propose_friendly(p_target_guild_id bigint, p_cadence int, p_starts_at timestamptz)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; myrole text; already int; eid bigint;
  v_pseudo text; my_name text; target_name text; v_closes timestamptz;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if p_target_guild_id = gid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  if not exists (select 1 from guilds where id = p_target_guild_id) then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if p_cadence not in (3,5,10) then return jsonb_build_object('ok', false, 'reason', 'bad_cadence'); end if;
  if p_starts_at < now() + interval '15 minutes' then return jsonb_build_object('ok', false, 'reason', 'too_soon'); end if;
  if p_starts_at > now() + interval '48 hours' then return jsonb_build_object('ok', false, 'reason', 'too_far'); end if;

  -- Un seul amical en vie (en attente ou en cours) impliquant l'une des
  -- deux guildes — décision D (verrous séparés par type), transposée à
  -- « un seul amical à la fois » comme pour le Tournoi interne (S).
  select count(*) into already from guild_events
    where kind = 'friendly' and status not in ('finished','cancelled')
      and (guild_a in (gid, p_target_guild_id) or guild_b in (gid, p_target_guild_id));
  if already > 0 then return jsonb_build_object('ok', false, 'reason', 'busy'); end if;

  v_closes := p_starts_at - interval '5 minutes';
  insert into guild_events(kind, guild_a, guild_b, cadence, starts_at, registration_closes_at, created_by, status)
    values ('friendly', gid, p_target_guild_id, p_cadence, p_starts_at, v_closes, uid, 'pending_acceptance')
    returning id into eid;

  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  select name into my_name from guilds where id = gid;
  select name into target_name from guilds where id = p_target_guild_id;

  insert into notifications(user_id, type, title, body, read, payload)
  select gm2.player_id, 'guild_event_challenge_received', '🤝 Confrontation amicale proposée',
    coalesce(my_name,'Une guilde') || ' (chef ' || coalesce(v_pseudo,'?') || ') propose une confrontation amicale le ' || to_char(p_starts_at, 'DD/MM à HH24:MI') || ' — aucun enjeu, juste l''honneur.',
    false, jsonb_build_object('event_id', eid)
  from guild_members gm2 where gm2.guild_id = p_target_guild_id and gm2.role = 'leader';

  perform guild_journal_log(gid, 'guild_event_challenge_sent', uid, null, '🤝 Confrontation amicale proposée à ' || coalesce(target_name,'une guilde') || ' pour le ' || to_char(p_starts_at, 'DD/MM à HH24:MI') || '.');
  return jsonb_build_object('ok', true, 'event_id', eid);
end $$;
grant execute on function public.guild_event_propose_friendly(bigint, int, timestamptz) to authenticated;

-- ── Répondre à une proposition (chef de la guilde ciblée) ───────────────
create or replace function public.guild_event_respond_friendly(p_event_id bigint, p_accept boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; myrole text; name_a text; name_b text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id for update;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select role into myrole from guild_members where guild_id = ev.guild_b and player_id = uid;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if ev.status is distinct from 'pending_acceptance' then return jsonb_build_object('ok', false, 'reason', 'not_pending'); end if;

  select name into name_a from guilds where id = ev.guild_a;
  select name into name_b from guilds where id = ev.guild_b;

  if p_accept then
    if now() >= ev.registration_closes_at then
      return jsonb_build_object('ok', false, 'reason', 'too_late');
    end if;
    update guild_events set status = 'scheduled', updated_at = now() where id = p_event_id;

    insert into notifications(user_id, type, title, body, read, payload)
    select gm.player_id, 'guild_event_announced', '🤝 Confrontation amicale confirmée !',
      coalesce(name_a,'Votre guilde') || ' affronte ' || coalesce(name_b,'la guilde adverse') || ' le ' || to_char(ev.starts_at, 'DD/MM à HH24:MI') || ' — inscrivez-vous !',
      false, jsonb_build_object('event_id', ev.id)
    from guild_members gm where gm.guild_id in (ev.guild_a, ev.guild_b);

    perform guild_journal_log(ev.guild_a, 'guild_event_announced', uid, null, '🤝 Confrontation amicale contre ' || coalesce(name_b,'la guilde adverse') || ' confirmée pour le ' || to_char(ev.starts_at, 'DD/MM à HH24:MI') || '.');
    perform guild_journal_log(ev.guild_b, 'guild_event_announced', uid, null, '🤝 Confrontation amicale contre ' || coalesce(name_a,'la guilde adverse') || ' confirmée pour le ' || to_char(ev.starts_at, 'DD/MM à HH24:MI') || '.');
  else
    update guild_events set status = 'cancelled', cancelled_by = uid, updated_at = now() where id = p_event_id;

    insert into notifications(user_id, type, title, body, read, payload)
    select gm.player_id, 'guild_event_challenge_declined', '🚫 Confrontation déclinée',
      coalesce(name_b,'La guilde ciblée') || ' a décliné votre proposition de confrontation amicale.',
      false, jsonb_build_object('event_id', ev.id)
    from guild_members gm where gm.guild_id = ev.guild_a and gm.role = 'leader';

    perform guild_journal_log(ev.guild_a, 'guild_event_challenge_declined', uid, null, '🚫 ' || coalesce(name_b,'La guilde ciblée') || ' a décliné la confrontation amicale.');
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept);
end $$;
grant execute on function public.guild_event_respond_friendly(bigint, boolean) to authenticated;

-- ── S'inscrire : étendu aux deux guildes, équipe fixée par appartenance ──
-- (kind='internal' inchangé : team reste null, réparti au lot G3 par le
-- chef ; kind='friendly'/'attack' : team dérive de la guilde d'origine,
-- aucune répartition manuelle possible — décision D.)
create or replace function public.guild_event_register(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; my_guild bigint; my_elo int; my_team text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select guild_id into my_guild from guild_members where player_id = uid;
  if my_guild is distinct from ev.guild_a and my_guild is distinct from ev.guild_b then
    return jsonb_build_object('ok', false, 'reason', 'not_in_guild');
  end if;
  if ev.status <> 'scheduled' then return jsonb_build_object('ok', false, 'reason', 'registration_closed'); end if;
  if now() >= ev.registration_closes_at then return jsonb_build_object('ok', false, 'reason', 'registration_closed'); end if;
  select case when ev.cadence <= 3 then coalesce(elo_3s,1200) when ev.cadence >= 10 then coalesce(elo_10s,1200) else coalesce(elo_5s,1200) end
    into my_elo from profiles where id = uid;
  my_team := case when ev.kind = 'internal' then null when my_guild = ev.guild_a then 'A' else 'B' end;
  insert into guild_event_participants(event_id, player_id, elo, team) values (p_event_id, uid, my_elo, my_team)
    on conflict (event_id, player_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_register(bigint) to authenticated;

-- ── Annuler : le chef de N'IMPORTE LAQUELLE des deux guildes impliquées ──
-- (Tournoi interne : guild_b est null, seul le chef de guild_a peut donc
-- agir — comportement inchangé.)
create or replace function public.guild_event_cancel(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; myrole text; v_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select role into myrole from guild_members where player_id = uid and guild_id in (ev.guild_a, ev.guild_b);
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if ev.status in ('running','finished','cancelled') then return jsonb_build_object('ok', false, 'reason', 'too_late'); end if;
  update guild_events set status = 'cancelled', cancelled_by = uid, updated_at = now() where id = p_event_id;
  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  perform guild_journal_log(ev.guild_a, 'guild_event_cancelled', uid, null, '🚫 ' || (case when ev.kind='internal' then 'Tournoi interne' else 'Confrontation amicale' end) || ' annulé(e) par ' || coalesce(v_pseudo,'un chef') || '.');
  if ev.guild_b is not null then
    perform guild_journal_log(ev.guild_b, 'guild_event_cancelled', uid, null, '🚫 Confrontation amicale annulée par ' || coalesce(v_pseudo,'un chef') || '.');
  end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_cancel(bigint) to authenticated;

-- ── Lecture : événements DES DEUX guildes possibles + infos adverses ────
create or replace function public.guild_event_list_mine()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id into gid from guild_members where player_id = uid;
  if gid is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', ev.id, 'kind', ev.kind, 'status', ev.status, 'cadence', ev.cadence,
      'starts_at', ev.starts_at, 'registration_closes_at', ev.registration_closes_at,
      'created_by', ev.created_by, 'guild_a', ev.guild_a, 'guild_b', ev.guild_b,
      'opponent_guild_name', (select name from guilds where id = (case when ev.guild_a = gid then ev.guild_b else ev.guild_a end)),
      'registered_count', (select count(*) from guild_event_participants gep where gep.event_id = ev.id),
      'i_am_registered', exists(select 1 from guild_event_participants gep where gep.event_id = ev.id and gep.player_id = uid)
    ) order by ev.starts_at asc)
    from guild_events ev
    where ev.kind = 'internal' and ev.guild_a = gid and ev.status not in ('finished','cancelled')
       or ev.kind <> 'internal' and (ev.guild_a = gid or ev.guild_b = gid) and ev.status not in ('finished','cancelled')
  ), '[]'::jsonb);
end $$;
grant execute on function public.guild_event_list_mine() to authenticated;

-- ── Tick d'inscriptions : ordre par Elo auto pour l'amical/l'attaque ─────
-- (le Tournoi interne garde son étape manuelle d'autobalance — G3 — car il
-- répartit un seul vivier en deux équipes ; l'amical n'a rien à répartir,
-- l'équipe est déjà fixée par appartenance de guilde depuis l'inscription.)
create or replace function public.guild_events_registration_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare ev record; n int := 0;
begin
  for ev in select * from guild_events where status = 'scheduled' and now() >= registration_closes_at loop
    update guild_events set status = 'registration_closed', updated_at = now() where id = ev.id;

    if ev.kind <> 'internal' then
      update guild_event_participants gep set seat = ranked.rk
        from (
          select player_id, row_number() over (partition by team order by elo asc, player_id) as rk
          from guild_event_participants where event_id = ev.id
        ) ranked
        where gep.event_id = ev.id and gep.player_id = ranked.player_id;
    end if;

    insert into notifications(user_id, type, title, body, read, payload)
    select gep.player_id, 'guild_event_registration_closed', '⏳ Inscriptions closes',
      'Les inscriptions au ' || (case when ev.kind='internal' then 'tournoi interne' else 'combat amical' end) || ' sont closes (' || (select count(*) from guild_event_participants where event_id = ev.id) || ' inscrit(s)).',
      false, jsonb_build_object('event_id', ev.id)
    from guild_event_participants gep where gep.event_id = ev.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('closed', n);
end $$;

-- ── Tick de check-in : gagne un contrôle d'effectif minimum (décision O) ─
-- Remplace le simple « exists(team is not null) » par un comptage par
-- équipe : couvre à la fois le Tournoi interne (chef inactif → team tout
-- null → 0<3) et l'amical/l'attaque (une des deux guildes n'a pas atteint
-- 3 inscrits) — dans les deux cas, le combat ne peut pas avoir lieu.
create or replace function public.guild_events_checkin_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare ev record; opened int := 0; started int := 0; noshow int; cnt_a int; cnt_b int;
begin
  for ev in
    select * from guild_events
    where status = 'registration_closed' and now() >= starts_at - interval '5 minutes'
  loop
    select count(*) filter (where team = 'A'), count(*) filter (where team = 'B')
      into cnt_a, cnt_b from guild_event_participants where event_id = ev.id;
    if cnt_a < 3 or cnt_b < 3 then
      update guild_events set status = 'cancelled', updated_at = now() where id = ev.id;
      continue;
    end if;

    update guild_events set status = 'checkin', updated_at = now() where id = ev.id;
    insert into notifications(user_id, type, title, body, read, payload)
    select gep.player_id, 'guild_event_starting', '🚪 Check-in ouvert !',
      'Le ' || (case when ev.kind='internal' then 'tournoi interne' else 'combat amical' end) || ' commence dans 5 minutes — confirme ta présence maintenant.',
      false, jsonb_build_object('event_id', ev.id)
    from guild_event_participants gep where gep.event_id = ev.id;
    opened := opened + 1;
  end loop;

  for ev in select * from guild_events where status = 'checkin' and now() >= starts_at loop
    delete from guild_event_participants where event_id = ev.id and checked_in = false;
    get diagnostics noshow = row_count;
    update guild_event_participants gep set seat = ranked.rk
      from (
        select player_id, row_number() over (partition by team order by seat asc) as rk
        from guild_event_participants where event_id = ev.id
      ) ranked
      where gep.event_id = ev.id and gep.player_id = ranked.player_id;

    if not exists (select 1 from guild_event_participants where event_id = ev.id and team = 'A')
       or not exists (select 1 from guild_event_participants where event_id = ev.id and team = 'B') then
      update guild_events set status = 'cancelled', updated_at = now() where id = ev.id;
    else
      update guild_events set status = 'running', current_seat_a = 1, current_seat_b = 1, updated_at = now() where id = ev.id;
    end if;
    started := started + 1;
  end loop;

  return jsonb_build_object('opened', opened, 'started', started);
end $$;

-- ── État détaillé : gagne kind + identité des deux guildes ──────────────
-- (reprend intégralement current_match/matches ajoutés au lot G4.)
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
      'id', ev.id, 'kind', ev.kind, 'status', ev.status, 'cadence', ev.cadence, 'starts_at', ev.starts_at,
      'registration_closes_at', ev.registration_closes_at, 'created_by', ev.created_by,
      'guild_a', ev.guild_a, 'guild_b', ev.guild_b,
      'guild_a_name', (select name from guilds where id = ev.guild_a),
      'guild_b_name', (select name from guilds where id = ev.guild_b),
      'winner_team', ev.winner_team, 'current_seat_a', ev.current_seat_a, 'current_seat_b', ev.current_seat_b,
      'streak_count', ev.streak_count
    ),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'player_id', gep.player_id, 'pseudo', p.pseudo, 'team', gep.team, 'seat', gep.seat,
        'elo', gep.elo, 'checked_in', gep.checked_in, 'eliminated_at', gep.eliminated_at, 'wins', gep.wins
      ) order by gep.team, gep.seat nulls last, p.pseudo)
      from guild_event_participants gep join profiles p on p.id = gep.player_id
      where gep.event_id = ev.id
    ), '[]'::jsonb),
    'current_match', (
      select jsonb_build_object(
        'game_id', gem.game_id, 'player_a', gem.player_a, 'player_a_pseudo', pa.pseudo,
        'player_b', gem.player_b, 'player_b_pseudo', pb.pseudo,
        'white_player_id', og.white_player_id, 'black_player_id', og.black_player_id
      )
      from guild_event_matches gem
      join profiles pa on pa.id = gem.player_a
      join profiles pb on pb.id = gem.player_b
      left join online_games og on og.id = gem.game_id
      where gem.event_id = ev.id and gem.game_id = ev.current_game_id
      limit 1
    ),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'seq', gem.seq, 'player_a', gem.player_a, 'player_a_pseudo', pa.pseudo,
        'player_b', gem.player_b, 'player_b_pseudo', pb.pseudo,
        'winner', gem.winner, 'started_at', gem.started_at, 'ended_at', gem.ended_at
      ) order by gem.seq desc)
      from guild_event_matches gem
      join profiles pa on pa.id = gem.player_a
      join profiles pb on pb.id = gem.player_b
      where gem.event_id = ev.id and gem.winner is not null
    ), '[]'::jsonb)
  );
end $$;
grant execute on function public.guild_event_state(bigint) to authenticated;

-- ── Lecture : propositions en attente de MA réponse (chef ciblé) ────────
create or replace function public.guild_event_pending_for_me()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; myrole text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id, role into gid, myrole from guild_members where player_id = uid;
  if gid is null or myrole is distinct from 'leader' then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', ev.id, 'starts_at', ev.starts_at, 'cadence', ev.cadence,
      'from_guild_name', (select name from guilds where id = ev.guild_a)
    ) order by ev.created_at desc)
    from guild_events ev
    where ev.kind = 'friendly' and ev.guild_b = gid and ev.status = 'pending_acceptance'
  ), '[]'::jsonb);
end $$;
grant execute on function public.guild_event_pending_for_me() to authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'guild_events_registration_tick') then
    perform cron.unschedule('guild_events_registration_tick');
  end if;
end $$;
select cron.schedule('guild_events_registration_tick', '20 seconds', $$select public.guild_events_registration_tick();$$);

do $$
begin
  if exists (select 1 from cron.job where jobname = 'guild_events_checkin_tick') then
    perform cron.unschedule('guild_events_checkin_tick');
  end if;
end $$;
select cron.schedule('guild_events_checkin_tick', '20 seconds', $$select public.guild_events_checkin_tick();$$);

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regproc('public.guild_event_propose_friendly')::text as fn_propose,   -- attendu non-null
  to_regproc('public.guild_event_respond_friendly')::text as fn_respond,   -- attendu non-null
  to_regproc('public.guild_event_pending_for_me')::text as fn_pending,     -- attendu non-null
  (select count(*) from cron.job where jobname = 'guild_events_registration_tick') as cron_reg, -- attendu 1
  (select count(*) from cron.job where jobname = 'guild_events_checkin_tick') as cron_checkin,  -- attendu 1
  'guild_events_g6_friendly OK' as status;
