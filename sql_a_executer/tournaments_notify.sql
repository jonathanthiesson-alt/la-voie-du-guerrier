-- ══════════════════════════════════════════════════════════════════
-- TOURNOIS — NOTIFICATION DE PARTIE PRÊTE
--
-- Problème constaté : le premier joueur crée la partie, mais le second
-- n'est prévenu de rien. Il reste sur l'écran du tournoi sans savoir que
-- son adversaire l'attend.
--
-- Solution : dès qu'une partie est attachée à un appariement, l'adversaire
-- reçoit une NOTIFICATION (retrouvable dans ses notifs, comme les défis)
-- et son écran bascule tout seul via le temps réel Supabase.
--
-- Idempotent. À exécuter après tournaments_v3.sql.
-- ══════════════════════════════════════════════════════════════════

-- La table notifications existe déjà. On s'assure des colonnes utiles.
alter table notifications
  add column if not exists payload jsonb default '{}'::jsonb;

-- Réécriture : attacher la partie PRÉVIENT désormais l'adversaire.
drop function if exists tournament_attach_game(bigint, bigint);
create or replace function tournament_attach_game(p_pairing_id bigint, p_game_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); pr record; opp uuid; me text; tname text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into pr from tournament_pairings where id = p_pairing_id for update;
  if pr is null then raise exception 'pairing not found'; end if;
  if uid not in (pr.white_id, pr.black_id) then
    return jsonb_build_object('ok', false, 'reason', 'not_your_game');
  end if;

  -- Course entre les deux joueurs : si l'autre a déjà créé la partie,
  -- on renvoie la SIENNE (on ne crée jamais deux parties pour un duel).
  if pr.online_game_id is not null then
    return jsonb_build_object('ok', true, 'game_id', pr.online_game_id, 'existing', true);
  end if;

  update tournament_pairings set online_game_id = p_game_id where id = p_pairing_id;

  -- ── Prévenir l'adversaire ──
  opp := case when uid = pr.white_id then pr.black_id else pr.white_id end;
  select pseudo into me from profiles where id = uid;
  select name into tname from tournaments where id = pr.tournament_id;

  if opp is not null then
    insert into notifications(user_id, type, title, body, read, payload)
    values (
      opp,
      'tournament_game',
      '⚔ Partie de tournoi prête',
      coalesce(me,'Votre adversaire') || ' vous attend — ' || coalesce(tname,'Tournoi') || ', ronde ' || pr.round,
      false,
      jsonb_build_object(
        'tournament_id', pr.tournament_id,
        'pairing_id', pr.id,
        'game_id', p_game_id,
        'round', pr.round,
        'opponent', me
      )
    );
  end if;

  return jsonb_build_object('ok', true, 'game_id', p_game_id, 'existing', false, 'notified', opp);
end $$;

-- Politique d'insertion des notifications (au cas où la RLS bloquerait) :
-- les RPC en SECURITY DEFINER contournent la RLS, mais on autorise aussi
-- la lecture de SES propres notifications.
do $$
begin
  if to_regclass('public.notifications') is not null then
    execute 'alter table public.notifications enable row level security';
    execute 'drop policy if exists nt_read_own on public.notifications';
    execute 'create policy nt_read_own on public.notifications for select to authenticated using (user_id = auth.uid())';
    execute 'drop policy if exists nt_update_own on public.notifications';
    execute 'create policy nt_update_own on public.notifications for update to authenticated using (user_id = auth.uid())';
  end if;
end $$;
