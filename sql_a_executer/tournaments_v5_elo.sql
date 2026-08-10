-- ═══════════════════════════════════════════════════════════════════
-- TOURNOIS V5 — Classement par Élo
-- ───────────────────────────────────────────────────────────────────
-- Le brief « Refonte Tournois » demande un CLASSEMENT PAR ÉLO. Les
-- tournois restent au système suisse (points de match par ronde), mais :
--   • chaque ligne du classement expose désormais l'Élo du joueur pour
--     la cadence du tournoi (elo_3s / elo_5s / elo_10s) ;
--   • l'Élo sert de DÉPARTAGE après les points puis les victoires
--     (deux joueurs à égalité de points sont départagés au plus fort Élo).
--
-- Idempotent : simple `create or replace`. Aucun changement de type de
-- retour (on ajoute juste une clé `elo` dans chaque objet), donc pas de
-- `drop` nécessaire.
--
-- Cadence → colonne Élo : ≤3s ⇒ elo_3s, ≥10s ⇒ elo_10s, sinon elo_5s
-- (cadence par défaut). Un tournoi à cadence exotique retombe sur 5s.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.tournament_standings(p_tournament_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare rows jsonb; tinfo jsonb; nb int; tsec int;
begin
  perform tournament_resolve_timeouts(p_tournament_id);

  select timer_seconds into tsec from tournaments where id = p_tournament_id;

  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into rows from (
    select pr.pseudo, tp.player_id, tp.score, tp.wins, tp.abandoned,
           -- Élo du joueur pour la cadence du tournoi (départage & affichage).
           case
             when coalesce(tsec,5) <= 3  then coalesce(pr.elo_3s, 1000)
             when coalesce(tsec,5) >= 10 then coalesce(pr.elo_10s, 1000)
             else coalesce(pr.elo_5s, 1000)
           end as elo
    from tournament_participants tp join profiles pr on pr.id = tp.player_id
    where tp.tournament_id = p_tournament_id
    -- Points d'abord, puis victoires, puis Élo (départage par Élo).
    order by tp.abandoned asc, tp.score desc, tp.wins desc,
             case
               when coalesce(tsec,5) <= 3  then coalesce(pr.elo_3s, 1000)
               when coalesce(tsec,5) >= 10 then coalesce(pr.elo_10s, 1000)
               else coalesce(pr.elo_5s, 1000)
             end desc
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

-- Vérif rapide (facultatif) :
--   select (tournament_standings(<id>)->'standings');
