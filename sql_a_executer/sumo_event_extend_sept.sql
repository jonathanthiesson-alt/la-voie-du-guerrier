-- ═══════════════════════════════════════════════════════════════════
-- SUMO — prolongation de l'événement jusqu'à fin septembre 2026
-- Décision Wurmz 2026-08-22. Seule la date en dur dans event_live change ;
-- reste du barème (BO3, +2/+1 Fame) inchangé. create or replace suffit
-- (signature et type de retour identiques à sumo_event.sql).
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.record_sumo_round_win(p_arena_match_id uuid, p_winner_color text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  m record; new_ww integer; new_wb integer; done boolean;
  wid uuid; lid uuid; new_round integer; fame integer := 0;
  event_live boolean := (now() < timestamptz '2026-10-01 00:00:00+02');
begin
  select * into m from arena_matches where id = p_arena_match_id for update;
  if m is null then raise exception 'Match SUMO introuvable'; end if;
  if coalesce(m.mode,'arena') <> 'sumo' then raise exception 'Ce match n''est pas un match SUMO'; end if;
  if auth.uid() is distinct from m.white_player_id and auth.uid() is distinct from m.black_player_id then
    raise exception 'not a participant';
  end if;

  if p_winner_color = 'white' then
    new_ww := m.wins_white + 1; new_wb := m.wins_black; wid := m.white_player_id; lid := m.black_player_id;
  else
    new_ww := m.wins_white; new_wb := m.wins_black + 1; wid := m.black_player_id; lid := m.white_player_id;
  end if;

  done := (new_ww >= 2 or new_wb >= 2);
  new_round := case when done then m.round_number else m.round_number + 1 end;

  if done and event_live then
    fame := 2;
    update profiles set fame_balance = fame_balance + 2, sumo_wins   = sumo_wins   + 1 where id = wid;
    update profiles set fame_balance = fame_balance + 1, sumo_losses = sumo_losses + 1 where id = lid;
  end if;

  update arena_matches set
    wins_white = new_ww, wins_black = new_wb,
    status     = case when done then 'finished' else status end,
    winner_id  = case when done then wid else winner_id end,
    round_number = new_round,
    ready_white = false, ready_black = false
  where id = p_arena_match_id;

  return jsonb_build_object('wins_white', new_ww, 'wins_black', new_wb,
    'match_done', done, 'fame_awarded', fame, 'winner_id', wid, 'round_number', new_round);
end $function$;

grant execute on function public.record_sumo_round_win(uuid, text) to authenticated;

select 'sumo_event_extend_sept OK' as status;
