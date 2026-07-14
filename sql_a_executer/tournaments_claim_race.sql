-- ═══════════════════════════════════════════════════════════════════
-- Durcit la réservation de création de partie de tournoi
-- (tournament_pairings.creator_claimed_by) : le serveur vérifie
-- lui-même qu'un délai minimal s'est écoulé avant de la libérer, au
-- lieu de faire confiance au client (qui pouvait la libérer trop tôt
-- sur un réseau lent — l'adversaire n'avait alors pas fini de créer sa
-- partie que le second client en recréait déjà une, provoquant un
-- va-et-vient de « je crée / j'attends / je reprends la main »).
--
-- À exécuter en une fois dans l'éditeur SQL Supabase, APRÈS
-- tournaments_auto.sql.
-- ═══════════════════════════════════════════════════════════════════

alter table public.tournament_pairings
  add column if not exists creator_claimed_at timestamptz;

create or replace function public.tournament_claim_creation(p_pairing_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
    update tournament_pairings set creator_claimed_by = uid, creator_claimed_at = now() where id = p_pairing_id;
    return jsonb_build_object('ok', true, 'role', 'create',
                              'white_id', pr.white_id, 'black_id', pr.black_id,
                              'timer_seconds', t.timer_seconds);
  end if;

  -- 3. C'est moi qui avais réservé (re-clic après un échec) → je recrée,
  --    et je rafraîchis l'horodatage pour ne pas me faire déposséder par
  --    l'adversaire au milieu de ma propre tentative.
  if pr.creator_claimed_by = uid then
    update tournament_pairings set creator_claimed_at = now() where id = p_pairing_id;
    return jsonb_build_object('ok', true, 'role', 'create',
                              'white_id', pr.white_id, 'black_id', pr.black_id,
                              'timer_seconds', t.timer_seconds);
  end if;

  -- 4. L'adversaire a réservé et n'a pas encore fini → j'attends.
  return jsonb_build_object('ok', true, 'role', 'wait',
                            'white_id', pr.white_id, 'black_id', pr.black_id,
                            'timer_seconds', t.timer_seconds);
end $function$;

create or replace function public.tournament_release_stale_claim(p_pairing_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare pr record;
begin
  select * into pr from tournament_pairings where id = p_pairing_id for update;
  if pr is null then return jsonb_build_object('ok', false); end if;
  if pr.online_game_id is not null then
    return jsonb_build_object('ok', true, 'game_id', pr.online_game_id);
  end if;
  if pr.creator_claimed_by is null then
    return jsonb_build_object('ok', true, 'released', true);
  end if;
  -- Le serveur vérifie lui-même l'ancienneté réelle de la réservation
  -- (10 s) : un client impatient ne peut plus la libérer prématurément
  -- pendant que l'autre est encore légitimement en train de créer sa
  -- partie (réseau lent, insertion + attachement en plusieurs allers-
  -- retours).
  if pr.creator_claimed_at is not null and now() - pr.creator_claimed_at < interval '10 seconds' then
    return jsonb_build_object('ok', false, 'reason', 'not_stale_yet');
  end if;
  update tournament_pairings set creator_claimed_by = null, creator_claimed_at = null where id = p_pairing_id;
  return jsonb_build_object('ok', true, 'released', true);
end $function$;
