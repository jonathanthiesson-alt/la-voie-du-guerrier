-- ══════════════════════════════════════════════════════════════════
-- TOURNOIS — CORRECTION DU DÉCALAGE DE TYPE bigint / uuid
--
-- Cause racine du blocage "plateau vide, en attente de l'adversaire" :
-- online_games.id est de type uuid, mais tournament_pairings.online_game_id
-- (et les paramètres p_game_id de tournament_attach_game /
-- tournament_report_from_game) étaient déclarés en bigint.
--
-- Résultat : tournament_attach_game(p_pairing_id, p_game_id) recevait un
-- uuid pour un paramètre bigint → échec de cast systématique côté
-- PostgREST, la fonction n'était même jamais exécutée. La partie était
-- bien créée dans online_games, mais jamais rattachée à l'appariement
-- (online_game_id restait null pour toujours) → l'adversaire ne la
-- trouvait jamais et attendait indéfiniment.
--
-- Confirmé en base : tous les appariements de tournoi passés (y compris
-- ceux résolus par "timeout") ont online_game_id = null.
--
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════

-- La colonne est entièrement à null en production (aucun rattachement
-- n'a jamais réussi) : conversion sans risque de perte de données.
alter table tournament_pairings
  alter column online_game_id type uuid using (online_game_id::text)::uuid;

-- ── Rattacher une partie en ligne à un appariement (p_game_id en uuid) ──
drop function if exists tournament_attach_game(bigint, bigint);
drop function if exists tournament_attach_game(bigint, uuid);
create or replace function tournament_attach_game(p_pairing_id bigint, p_game_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); pr record; opp uuid; me text; tname text; notified boolean := false;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into pr from tournament_pairings where id = p_pairing_id for update;
  if pr is null then raise exception 'pairing not found'; end if;
  if uid not in (pr.white_id, pr.black_id) then
    return jsonb_build_object('ok', false, 'reason', 'not_your_game');
  end if;

  -- Course : l'adversaire a déjà attaché une partie → la sienne fait foi.
  if pr.online_game_id is not null then
    return jsonb_build_object('ok', true, 'game_id', pr.online_game_id, 'existing', true);
  end if;

  -- ── L'ESSENTIEL, en premier et sans rien qui puisse le faire échouer ──
  update tournament_pairings set online_game_id = p_game_id where id = p_pairing_id;

  -- ── Le confort : prévenir l'adversaire. Isolé : si ça casse, tant pis,
  --    l'attachement reste acquis (le client sonde de toute façon).
  begin
    opp := case when uid = pr.white_id then pr.black_id else pr.white_id end;
    if opp is not null then
      select pseudo into me from profiles where id = uid;
      select name into tname from tournaments where id = pr.tournament_id;
      insert into notifications(user_id, type, title, body, read, payload)
      values (
        opp, 'tournament_game', '⚔ Partie de tournoi prête',
        coalesce(me,'Votre adversaire') || ' vous attend — ' || coalesce(tname,'Tournoi') || ', ronde ' || pr.round,
        false,
        jsonb_build_object('tournament_id', pr.tournament_id, 'pairing_id', pr.id,
                           'game_id', p_game_id, 'round', pr.round, 'opponent', me)
      );
      notified := true;
    end if;
  exception when others then
    notified := false;   -- on avale l'erreur : la partie est rattachée, c'est ce qui compte
  end;

  return jsonb_build_object('ok', true, 'game_id', p_game_id, 'existing', false, 'notified', notified);
end $$;

-- ── Report automatique du résultat (p_game_id en uuid) ──────────────
drop function if exists tournament_report_from_game(bigint, text);
drop function if exists tournament_report_from_game(uuid, text);
create or replace function tournament_report_from_game(p_game_id uuid, p_winner text)
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
