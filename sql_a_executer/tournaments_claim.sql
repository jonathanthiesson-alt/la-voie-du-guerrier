-- ══════════════════════════════════════════════════════════════════
-- TOURNOIS — RÉSERVATION ATOMIQUE DU CRÉATEUR DE PARTIE
--
-- Bug constaté : les DEUX joueurs cliquaient « Jouer la partie », donc
-- DEUX parties étaient créées. Chacun attendait son adversaire dans sa
-- propre partie → blocage mutuel, plateau masqué à vie.
--
-- Correction : on décide QUI crée AVANT de créer quoi que ce soit.
-- Un seul joueur reçoit le rôle « create » ; l'autre reçoit « wait »
-- puis « join » dès que la partie existe.
--
-- Idempotent. À exécuter après tournaments_notify.sql.
-- ══════════════════════════════════════════════════════════════════

alter table tournament_pairings
  add column if not exists creator_claimed_by uuid references profiles(id) on delete set null;

-- Réserve le droit de créer la partie. Verrou de ligne → un seul gagnant,
-- même si les deux joueurs cliquent exactement au même instant.
drop function if exists tournament_claim_creation(bigint);
create or replace function tournament_claim_creation(p_pairing_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); pr record; t record;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- FOR UPDATE : sérialise les deux clics concurrents.
  select * into pr from tournament_pairings where id = p_pairing_id for update;
  if pr is null then raise exception 'pairing not found'; end if;
  if uid not in (pr.white_id, pr.black_id) then
    return jsonb_build_object('ok', false, 'reason', 'not_your_game');
  end if;
  if pr.result is not null then
    return jsonb_build_object('ok', false, 'reason', 'already_played');
  end if;

  select * into t from tournaments where id = pr.tournament_id;

  -- 1. La partie existe déjà → tout le monde la rejoint.
  if pr.online_game_id is not null then
    return jsonb_build_object('ok', true, 'role', 'join',
                              'game_id', pr.online_game_id,
                              'white_id', pr.white_id, 'black_id', pr.black_id,
                              'timer_seconds', t.timer_seconds);
  end if;

  -- 2. Personne n'a encore réservé → je deviens le créateur.
  if pr.creator_claimed_by is null then
    update tournament_pairings set creator_claimed_by = uid where id = p_pairing_id;
    return jsonb_build_object('ok', true, 'role', 'create',
                              'white_id', pr.white_id, 'black_id', pr.black_id,
                              'timer_seconds', t.timer_seconds);
  end if;

  -- 3. C'est moi qui avais réservé (re-clic après un échec) → je recrée.
  if pr.creator_claimed_by = uid then
    return jsonb_build_object('ok', true, 'role', 'create',
                              'white_id', pr.white_id, 'black_id', pr.black_id,
                              'timer_seconds', t.timer_seconds);
  end if;

  -- 4. L'adversaire a réservé et n'a pas encore fini → j'attends.
  return jsonb_build_object('ok', true, 'role', 'wait',
                            'white_id', pr.white_id, 'black_id', pr.black_id,
                            'timer_seconds', t.timer_seconds);
end $$;

-- Si le créateur désigné n'a pas créé la partie au bout de 30 s (onglet
-- fermé, plantage…), la réservation est libérée : l'autre peut prendre
-- le relais au lieu d'attendre indéfiniment.
drop function if exists tournament_release_stale_claim(bigint);
create or replace function tournament_release_stale_claim(p_pairing_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pr record;
begin
  select * into pr from tournament_pairings where id = p_pairing_id for update;
  if pr is null then return jsonb_build_object('ok', false); end if;
  if pr.online_game_id is not null then
    return jsonb_build_object('ok', true, 'game_id', pr.online_game_id);
  end if;
  -- La réservation est libérée quelle que soit son ancienneté : l'appelant
  -- ne demande à la libérer qu'après avoir patienté côté client.
  update tournament_pairings set creator_claimed_by = null where id = p_pairing_id;
  return jsonb_build_object('ok', true, 'released', true);
end $$;

-- Consulter l'état d'un appariement (pour le sondage d'attente).
drop function if exists tournament_pairing_state(bigint);
create or replace function tournament_pairing_state(p_pairing_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pr record;
begin
  select * into pr from tournament_pairings where id = p_pairing_id;
  if pr is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true,
    'online_game_id', pr.online_game_id,
    'result', pr.result,
    'claimed_by', pr.creator_claimed_by);
end $$;
