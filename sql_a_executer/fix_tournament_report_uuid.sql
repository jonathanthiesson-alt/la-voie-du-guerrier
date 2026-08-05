-- ══════════════════════════════════════════════════════════════════
-- FIX CRITIQUE — tournament_report_from_game : p_game_id doit être UUID
--
-- Régression : la fonction avait une signature (p_game_id BIGINT, ...) alors
-- que online_games.id ET tournament_pairings.online_game_id sont des UUID.
-- L'appel (client reportTournamentGameEnd + worker tournamentTick) passait un
-- uuid → PostgREST/plpgsql ne pouvait pas coercer → l'appel échouait en
-- SILENCE (catch vide côté client). Conséquence : AUCUN résultat de tournoi
-- n'était jamais enregistré → toutes les paires restaient result=null →
-- parties « en cours » indéfiniment → à l'échéance de ronde, le résolveur de
-- timeouts marquait tout en double-forfait et clôturait le tournoi.
--
-- La surcharge uuid avait été supprimée par erreur (voir SQL_MIGRATIONS #31,
-- « surcharge zombie uuid »). On la RÉTABLIT (seule la variante uuid est
-- correcte) et on retire la variante bigint inutilisable.
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════

drop function if exists public.tournament_report_from_game(bigint, text);

create or replace function public.tournament_report_from_game(p_game_id uuid, p_winner text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare pr record; res text; amt int; win_id uuid;
begin
  select * into pr from tournament_pairings where online_game_id = p_game_id limit 1;
  if pr is null then return jsonb_build_object('ok', false, 'reason', 'not_a_tournament_game'); end if;
  if pr.result is not null then return jsonb_build_object('ok', true, 'already', true); end if;

  if p_winner = 'white' then res := 'white';
  elsif p_winner = 'black' then res := 'black';
  else return jsonb_build_object('ok', false, 'reason', 'invalid_winner'); end if;

  update tournament_pairings set result = res where id = pr.id;

  select amount into amt from reward_config where mode='tournament' and event_key='win';
  amt := coalesce(amt, 2);

  win_id := case when res='white' then pr.white_id else pr.black_id end;
  update tournament_participants set score = score + 1, wins = wins + 1
    where tournament_id = pr.tournament_id and player_id = win_id;
  update profiles set mon_balance = mon_balance + amt where id = win_id;

  return jsonb_build_object('ok', true, 'result', res, 'tournament_id', pr.tournament_id);
end $function$;

grant execute on function public.tournament_report_from_game(uuid, text) to authenticated;
