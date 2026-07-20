-- ══════════════════════════════════════════════════════════════════
-- TOURNOIS — plus de nulle (impossible dans le jeu) + recompenses
-- par classement final (tout le monde touche du Mon, pas seulement
-- le podium)
--
-- Le jeu se resout TOUJOURS par une victoire ou une defaite : la
-- branche "draw" de tournament_report_from_game ne pouvait jamais se
-- declencher realistement, elle est retiree.
--
-- tournament_award_podium ne payait que les 3 premiers (20/12/6 Mon).
-- Desormais TOUS les participants non-abandonnistes sont payes, du
-- dernier (3 Mon) au premier (20 Mon), au prorata de leur rang.
--
-- Idempotent. A executer apres tournaments_v3.sql.
-- ══════════════════════════════════════════════════════════════════

drop function if exists tournament_report_from_game(bigint, text);
create or replace function tournament_report_from_game(p_game_id bigint, p_winner text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pr record; res text; amt int; win_id uuid;
begin
  select * into pr from tournament_pairings
    where online_game_id = p_game_id limit 1;
  if pr is null then return jsonb_build_object('ok', false, 'reason', 'not_a_tournament_game'); end if;
  if pr.result is not null then return jsonb_build_object('ok', true, 'already', true); end if;

  -- Le jeu ne produit jamais de nulle : seul un vainqueur blanc ou noir
  -- est un resultat valide ici.
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
end $$;

-- ── Recompense finale : classement complet, pas seulement le podium ──
-- Du dernier (min_r) au premier (max_r), au prorata lineaire du rang.
-- Un seul participant (tournoi annule tres tot) touche le maximum.
drop function if exists tournament_award_podium(bigint);
create or replace function tournament_award_podium(p_tournament_id bigint)
returns void language plpgsql security definer set search_path=public as $$
declare r record; rank int := 0; total int; reward int;
        max_r int := 20; min_r int := 3;
begin
  select count(*) into total from tournament_participants
    where tournament_id = p_tournament_id and abandoned = false;
  if total = 0 then return; end if;

  for r in
    select player_id from tournament_participants
    where tournament_id = p_tournament_id and abandoned = false
    order by score desc, wins desc
  loop
    rank := rank + 1;
    if total = 1 then
      reward := max_r;
    else
      reward := round(min_r + (max_r - min_r) * (total - rank)::numeric / (total - 1));
    end if;
    update profiles set mon_balance = mon_balance + reward where id = r.player_id;
  end loop;
end $$;

-- ── Controle ──────────────────────────────────────────────────────
select
  to_regproc('public.tournament_report_from_game')::text as fn_report,
  to_regproc('public.tournament_award_podium')::text     as fn_podium;
