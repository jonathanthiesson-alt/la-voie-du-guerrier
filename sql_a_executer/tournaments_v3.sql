-- ══════════════════════════════════════════════════════════════════
-- TOURNOIS V3 — parties réelles + nettoyage automatique
--
-- Corrige deux défauts majeurs révélés par les tests :
--   1. Les joueurs étaient appariés mais AUCUNE partie ne se lançait.
--      → un appariement pointe désormais vers une vraie partie en ligne,
--        et le résultat est reporté AUTOMATIQUEMENT à la fin du combat.
--   2. Un tournoi restait « en cours » indéfiniment (toute la nuit) :
--      rien ne résolvait les rondes expirées si personne n'ouvrait l'écran.
--      → nettoyage automatique appelé à chaque consultation de la liste.
--
-- Idempotent. À exécuter après tournaments_v2.sql.
-- ══════════════════════════════════════════════════════════════════

-- ── Un appariement retient sa partie en ligne ───────────────────────
-- (la colonne online_game_id existait déjà, on l'indexe)
create index if not exists idx_pairings_game on tournament_pairings(online_game_id);
create index if not exists idx_pairings_lookup on tournament_pairings(tournament_id, round);

-- ── Associer une partie en ligne à un appariement ────────────────────
drop function if exists tournament_attach_game(bigint, bigint);
create or replace function tournament_attach_game(p_pairing_id bigint, p_game_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); pr record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into pr from tournament_pairings where id = p_pairing_id for update;
  if pr is null then raise exception 'pairing not found'; end if;
  if uid not in (pr.white_id, pr.black_id) then
    return jsonb_build_object('ok', false, 'reason', 'not_your_game');
  end if;
  -- Un seul des deux crée la partie : si elle existe déjà, on renvoie la sienne.
  if pr.online_game_id is not null then
    return jsonb_build_object('ok', true, 'game_id', pr.online_game_id, 'existing', true);
  end if;
  update tournament_pairings set online_game_id = p_game_id where id = p_pairing_id;
  return jsonb_build_object('ok', true, 'game_id', p_game_id, 'existing', false);
end $$;

-- ── Report AUTOMATIQUE du résultat depuis la partie terminée ─────────
-- Appelé à la fin du combat par les deux clients ; idempotent.
drop function if exists tournament_report_from_game(bigint, text);
create or replace function tournament_report_from_game(p_game_id bigint, p_winner text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pr record; res text; amt int; win_id uuid;
begin
  select * into pr from tournament_pairings
    where online_game_id = p_game_id limit 1;
  if pr is null then return jsonb_build_object('ok', false, 'reason', 'not_a_tournament_game'); end if;
  if pr.result is not null then return jsonb_build_object('ok', true, 'already', true); end if;

  if p_winner = 'white' then res := 'white';
  elsif p_winner = 'black' then res := 'black';
  else res := 'draw'; end if;

  update tournament_pairings set result = res where id = pr.id;

  select amount into amt from reward_config where mode='tournament' and event_key='win';
  amt := coalesce(amt, 2);

  if res = 'draw' then
    update tournament_participants set score = score + 0.5
      where tournament_id = pr.tournament_id and player_id in (pr.white_id, pr.black_id);
    update profiles set mon_balance = mon_balance + greatest(1, amt/2)
      where id in (pr.white_id, pr.black_id);
  else
    win_id := case when res='white' then pr.white_id else pr.black_id end;
    update tournament_participants set score = score + 1, wins = wins + 1
      where tournament_id = pr.tournament_id and player_id = win_id;
    update profiles set mon_balance = mon_balance + amt where id = win_id;
  end if;

  return jsonb_build_object('ok', true, 'result', res, 'tournament_id', pr.tournament_id);
end $$;

-- ── NETTOYAGE AUTOMATIQUE des tournois bloqués ──────────────────────
-- Résout les rondes expirées, enchaîne la ronde suivante, et clôt les
-- tournois qui n'ont plus de joueurs actifs ou qui traînent depuis trop
-- longtemps. Appelé à chaque affichage de la liste des tournois : plus
-- besoin d'un cron, et un tournoi ne peut plus « tourner toute la nuit ».
drop function if exists tournament_cleanup();
create or replace function tournament_cleanup()
returns jsonb language plpgsql security definer set search_path=public as $$
declare t record; pending int; actifs int; n_closed int := 0; n_advanced int := 0;
begin
  for t in select * from tournaments where status in ('open','running') loop

    -- (a) Tournoi jamais lancé et créé il y a plus de 2 h → abandonné.
    if t.status = 'open' and t.created_at < now() - interval '2 hours' then
      update tournaments set status = 'finished' where id = t.id;
      n_closed := n_closed + 1;
      continue;
    end if;

    if t.status <> 'running' then continue; end if;

    -- (b) Délai de la ronde écoulé → on solde les parties non jouées.
    if t.round_deadline is not null and now() >= t.round_deadline then
      perform tournament_resolve_timeouts(t.id);
    end if;

    -- (c) Toutes les parties de la ronde sont conclues → ronde suivante
    --     (ou fin du tournoi si c'était la dernière).
    select count(*) into pending from tournament_pairings
      where tournament_id = t.id and round = t.current_round and result is null;

    if pending = 0 then
      select count(*) into actifs from tournament_participants
        where tournament_id = t.id and abandoned = false;

      if actifs < 2 or t.current_round >= t.total_rounds then
        update tournaments set status = 'finished', round_deadline = null where id = t.id;
        perform tournament_award_podium(t.id);
        n_closed := n_closed + 1;
      else
        perform tournament_start_next_round(t.id);
        n_advanced := n_advanced + 1;
      end if;
    end if;
  end loop;

  return jsonb_build_object('closed', n_closed, 'advanced', n_advanced);
end $$;

-- ── Annuler un tournoi (créateur ou administrateur) ──────────────────
drop function if exists tournament_cancel(bigint);
create or replace function tournament_cancel(p_tournament_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); t record; adm boolean;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into t from tournaments where id = p_tournament_id;
  if t is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select coalesce(is_admin,false) into adm from profiles where id = uid;
  if t.created_by <> uid and not coalesce(adm,false) then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;
  delete from tournaments where id = p_tournament_id;   -- cascade sur participants/appariements
  return jsonb_build_object('ok', true);
end $$;

-- ── La liste des tournois déclenche le nettoyage ─────────────────────
drop function if exists tournament_list();
create or replace function tournament_list()
returns jsonb language plpgsql security definer set search_path=public as $$
declare rows jsonb;
begin
  perform tournament_cleanup();   -- ← plus de tournoi zombie
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into rows from (
    select t.id, t.name, t.status, t.total_rounds, t.current_round, t.timer_seconds,
           t.max_players, t.round_minutes, t.round_deadline, t.created_by,
           (select count(*) from tournament_participants tp where tp.tournament_id = t.id) as players
    from tournaments t
    where t.status in ('open','running')
    order by t.created_at desc
    limit 20
  ) x;
  return jsonb_build_object('ok', true, 'tournaments', rows);
end $$;

-- ── L'appariement expose la partie et l'adversaire ───────────────────
drop function if exists tournament_my_pairing(bigint, integer);
create or replace function tournament_my_pairing(p_tournament_id bigint, p_round integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); pr record; opp uuid; opp_name text; t record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into pr from tournament_pairings
    where tournament_id = p_tournament_id and round = p_round
      and (white_id = uid or black_id = uid) limit 1;
  if pr is null then return jsonb_build_object('found', false); end if;

  select * into t from tournaments where id = p_tournament_id;
  opp := case when uid = pr.white_id then pr.black_id else pr.white_id end;
  select pseudo into opp_name from profiles where id = opp;

  return jsonb_build_object(
    'found', true,
    'pairing_id', pr.id,
    'result', pr.result,
    'online_game_id', pr.online_game_id,
    'white_id', pr.white_id,
    'black_id', pr.black_id,
    'i_am_white', (uid = pr.white_id),
    'opponent_id', opp,
    'opponent_name', opp_name,
    'timer_seconds', t.timer_seconds,
    'deadline', t.round_deadline
  );
end $$;
