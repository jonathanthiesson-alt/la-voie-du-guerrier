-- ═══════════════════════════════════════════════════════════════════
-- ÉTAT DÉTAILLÉ — extension pour le lot G4
-- docs/ROADMAP_GUILD_BATTLE.md § 7
--
-- Étend guild_event_state (guild_events_g3.sql) pour exposer le duel en
-- cours (avec les pseudos, pour l'écran combat) et l'historique des duels
-- déjà joués — nécessaire à l'écran G4 (qui affronte qui, bouton pour
-- rejoindre sa partie, historique).
-- ═══════════════════════════════════════════════════════════════════

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

-- ── Contrôle ───────────────────────────────────────────────────────
select to_regproc('public.guild_event_state')::text as fn_state, 'guild_events_g4_state OK' as status; -- attendu non-null
