-- ══════════════════════════════════════════════════════════════════
-- FIX — tournoi : les BOTS ne sont jamais « abandonnistes » + on récupère
-- les parties finies non reportées.
--
-- Bug vécu : quand le worker tombe (run terminé / crash), les parties
-- bot-vs-bot en cours se figent → à l'échéance de ronde, tournament_resolve_
-- timeouts les soldait en forfait ET marquait les DEUX bots abandoned=true.
-- Résultat : après quelques minutes sans worker, TOUT le peloton de bots était
-- exclu et le tournoi dégénérait à 2 joueurs (Wurmz retombant sur le même bot
-- à chaque ronde faute d'alternative).
--
-- Correctifs :
--  1. Un BOT n'est JAMAIS marqué abandonniste (IA toujours disponible) — seuls
--     les HUMAINS absents abandonnent.
--  2. Si la partie s'est en réalité TERMINÉE mais n'a pas été reportée (worker
--     momentanément absent au moment du report), on enregistre le VRAI
--     résultat via tournament_report_from_game plutôt qu'un forfait.
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════

create or replace function public.tournament_resolve_timeouts(p_tournament_id bigint)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare t record; pr record; n int := 0; g record;
begin
  select * into t from tournaments where id = p_tournament_id;
  if t is null or t.round_deadline is null then return 0; end if;
  if now() < t.round_deadline + interval '90 seconds' then return 0; end if;

  for pr in
    select * from tournament_pairings
    where tournament_id = p_tournament_id and round = t.current_round and result is null
  loop
    -- 1. La partie s'est-elle en fait terminée sans être reportée ? → vrai résultat.
    g := null;
    if pr.online_game_id is not null then
      select status, winner into g from online_games where id = pr.online_game_id;
    end if;
    if g is not null and g.status = 'finished' and g.winner in ('white','black') then
      perform tournament_report_from_game(pr.online_game_id, g.winner);
      n := n + 1;
      continue;
    end if;

    -- 2. Sinon : forfait de ronde. Les BOTS ne sont JAMAIS marqués abandonnistes.
    update tournament_pairings set result = 'timeout' where id = pr.id;
    update tournament_participants tp
      set missed = missed + 1,
          abandoned = (case when pf.is_bot then tp.abandoned else true end)
      from profiles pf
      where pf.id = tp.player_id
        and tp.tournament_id = p_tournament_id
        and tp.player_id in (pr.white_id, pr.black_id);
    n := n + 1;
  end loop;
  return n;
end $function$;
