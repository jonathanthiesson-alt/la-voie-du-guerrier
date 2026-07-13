-- ══════════════════════════════════════════════════════════════════
-- TOURNOIS — ATTACHEMENT À TOUTE ÉPREUVE
--
-- Bug : tournament_attach_game insérait une notification. Si cette
-- insertion échouait (colonne absente, contrainte sur `type`…), TOUTE la
-- fonction échouait → la partie n'était jamais rattachée à l'appariement
-- → l'adversaire ne la trouvait jamais et créait la sienne → les deux
-- joueurs se retrouvaient dans deux plateaux différents, chacun « en
-- attente de l'adversaire ».
--
-- Correction : l'attachement est fait EN PREMIER et la notification est
-- isolée dans un bloc d'exception. Prévenir l'adversaire est un confort ;
-- rattacher la partie est vital. L'un ne doit jamais faire tomber l'autre.
--
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════

alter table notifications
  add column if not exists payload jsonb default '{}'::jsonb;

drop function if exists tournament_attach_game(bigint, bigint);
create or replace function tournament_attach_game(p_pairing_id bigint, p_game_id bigint)
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
