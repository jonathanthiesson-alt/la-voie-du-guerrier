-- ═══════════════════════════════════════════════════════════════════
-- SUBSTITUTION MONBAN EN DÉFENSE — lot G8b, décision F du cadrage
-- docs/ROADMAP_GUILD_BATTLE.md § 7 et § 10 (limitation levée)
--
-- Complète le lot G8 : un défenseur (équipe B) absent au forfait (60s de
-- grâce, décision M) voyait jusqu'ici son duel purement perdu, comme un
-- forfait de Tournoi interne. Décision F : « Monban remplace en DÉFENSE
-- uniquement » — Monban doit reprendre SON duel plutôt que l'éliminer
-- d'office. L'attaquant (équipe A) absent reste éliminé sans substitution
-- (décision P : un attaquant doit être un humain présent).
--
-- Réutilise le pipeline réactif du lot G0 (trigger pg_net + Edge Function
-- monban-move, déjà déployée et étendue séparément) : la nouvelle colonne
-- online_games.is_monban_defense EST l'autorisation vérifiée côté Edge
-- Function — aucune donnée sensible, elle n'est posée QUE par
-- guild_events_combat_tick lui-même.
-- ═══════════════════════════════════════════════════════════════════

alter table public.online_games add column if not exists is_monban_defense boolean not null default false;

-- ── Combat tick : le forfait d'un défenseur (attack, équipe B) substitue
-- Monban au lieu d'éliminer — l'attaquant absent reste éliminé tel quel.
-- ready_black doit être forcé à true : c'est ce flag qui débloque
-- markReadyAndWaitForOpponent() côté client de l'ATTAQUANT (poll toutes les
-- 500ms, cf. index.html) — sans ça son décompte de départ ne démarre
-- jamais, en attente indéfinie d'un adversaire qui ne rejoindra jamais.
create or replace function public.guild_events_combat_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  ev record; g record; pa_id uuid; pb_id uuid; winner_side text; loser_team text;
  next_seat int; team_size int; last_ended timestamptz; new_seq int;
  created int := 0; resolved int := 0; forfeits int := 0; monban_subs int := 0;
  gid uuid; mid bigint; kind_label text; absent_side text;
begin
  for ev in select * from guild_events where status = 'running' loop

    if ev.current_game_id is not null then
      select * into g from online_games where id = ev.current_game_id;
      if g is null then
        update guild_events set current_game_id = null where id = ev.id;
        continue;
      end if;

      -- Une partie déjà substituée à Monban (is_monban_defense=true) n'est
      -- JAMAIS re-candidate au forfait : Monban ne charge jamais de client,
      -- ready_black restera toujours à sa valeur forcée — sans cette garde,
      -- le tick retenterait la substitution (ou pire) à chaque passage.
      if g.status = 'active' and not coalesce(g.is_monban_defense,false)
         and not (coalesce(g.ready_white,false) and coalesce(g.ready_black,false))
         and now() - g.created_at > interval '60 seconds' then
        if not coalesce(g.ready_white,false) and not coalesce(g.ready_black,false) then
          update online_games set status = 'finished' where id = g.id;
          update guild_event_matches set ended_at = now() where event_id = ev.id and game_id = g.id;
          update guild_events set current_game_id = null where id = ev.id;
          continue;
        end if;

        absent_side := case when coalesce(g.ready_white,false) then 'black' else 'white' end;

        if ev.kind = 'attack' and absent_side = 'black' then
          -- Décision F : le défenseur absent est remplacé par Monban, pas
          -- éliminé. On ne clôt PAS la partie : elle continue normalement,
          -- Monban jouant Noir dès que le trigger réactif le déclenche.
          update guild_event_participants set plays_as_monban = true
            where event_id = ev.id and player_id = g.black_player_id;
          update online_games set is_monban_defense = true, ready_black = true where id = g.id;
          monban_subs := monban_subs + 1;
          continue; -- rien d'autre à faire ce tick pour cet événement
        end if;

        -- Tout le reste (attaquant absent, ou défenseur absent hors mode
        -- attaque — internal/friendly n'ont pas de Monban) : comportement
        -- inchangé, forfait = défaite immédiate.
        winner_side := case when coalesce(g.ready_white,false) then 'white' else 'black' end;
        update online_games set status = 'finished', winner = winner_side where id = g.id;
        forfeits := forfeits + 1;
        select * into g from online_games where id = g.id;
      end if;

      if g.status <> 'finished' or g.winner is null then
        continue;
      end if;

      declare winner_team text; loser_player uuid; winner_player uuid; prev_winner_team text; new_streak int;
      begin
        winner_team := case when g.winner = 'white' then 'A' else 'B' end;
        loser_team := case when g.winner = 'white' then 'B' else 'A' end;
        winner_player := case when g.winner = 'white' then g.white_player_id else g.black_player_id end;
        loser_player := case when g.winner = 'white' then g.black_player_id else g.white_player_id end;

        update guild_event_matches set winner = winner_team, ended_at = now()
          where event_id = ev.id and game_id = g.id;

        update guild_event_participants set eliminated_at = now(), eliminated_by = winner_player
          where event_id = ev.id and player_id = loser_player;
        update guild_event_participants set wins = wins + 1 where event_id = ev.id and player_id = winner_player;

        select winner into prev_winner_team from guild_event_matches
          where event_id = ev.id and ended_at is not null and winner is not null
            and id < (select id from guild_event_matches where event_id = ev.id and game_id = g.id)
          order by id desc limit 1;
        new_streak := case when prev_winner_team = winner_team then ev.streak_count + 1 else 1 end;

        if loser_team = 'A' then
          select coalesce(max(seat),0) into team_size from guild_event_participants where event_id = ev.id and team = 'A';
          next_seat := ev.current_seat_a + 1;
          if next_seat > team_size then
            update guild_events set status = 'finished', winner_team = 'B', current_game_id = null, updated_at = now() where id = ev.id;
          else
            update guild_events set current_seat_a = next_seat, streak_count = new_streak, current_game_id = null, updated_at = now() where id = ev.id;
          end if;
        else
          select coalesce(max(seat),0) into team_size from guild_event_participants where event_id = ev.id and team = 'B';
          next_seat := ev.current_seat_b + 1;
          if next_seat > team_size then
            update guild_events set status = 'finished', winner_team = 'A', current_game_id = null, updated_at = now() where id = ev.id;
          else
            update guild_events set current_seat_b = next_seat, streak_count = new_streak, current_game_id = null, updated_at = now() where id = ev.id;
          end if;
        end if;
      end;
      resolved := resolved + 1;

      if exists (select 1 from guild_events where id = ev.id and status = 'finished' and winner_team is not null and updated_at > now() - interval '5 seconds') then
        declare
          v_win_team text; v_win_guild bigint; v_lose_guild bigint; v_name_a text; v_name_b text;
          elo_res jsonb; stolen int := 0; remaining int; extra_a text := ''; extra_b text := '';
        begin
          select winner_team into v_win_team from guild_events where id = ev.id;
          select name into v_name_a from guilds where id = ev.guild_a;
          select name into v_name_b from guilds where id = ev.guild_b;

          if ev.kind = 'internal' then
            insert into notifications(user_id, type, title, body, read, payload)
            select gep.player_id, 'guild_event_result', '🏆 Tournoi interne terminé',
              'L''équipe ' || v_win_team || ' remporte le tournoi interne !',
              false, jsonb_build_object('event_id', ev.id)
            from guild_event_participants gep where gep.event_id = ev.id
            union select gm2.player_id, 'guild_event_result', '🏆 Tournoi interne terminé',
              'L''équipe ' || v_win_team || ' remporte le tournoi interne !', false, jsonb_build_object('event_id', ev.id)
            from guild_members gm2 where gm2.guild_id = ev.guild_a
              and gm2.player_id not in (select player_id from guild_event_participants where event_id = ev.id);
            perform guild_journal_log(ev.guild_a, 'guild_event_result', null, null, '🏆 Le tournoi interne s''achève : équipe ' || v_win_team || ' victorieuse.');
          else
            v_win_guild := case when v_win_team = 'A' then ev.guild_a else ev.guild_b end;
            v_lose_guild := case when v_win_team = 'A' then ev.guild_b else ev.guild_a end;

            if ev.kind = 'attack' then
              stolen := 10;
              update guilds set ryu_total = greatest(0, ryu_total - stolen) where id = v_lose_guild;
              update guilds set ryu_total = ryu_total + stolen where id = v_win_guild;
              select count(*) filter (where eliminated_at is null) into remaining
                from guild_event_participants where event_id = ev.id and team = v_win_team;
              elo_res := guild_elo_apply_result(v_win_guild, v_lose_guild, greatest(remaining,1), 0, 1.0);
              extra_a := ' — 🐉 +' || stolen || (case when elo_res is not null and (elo_res->>'delta')::int > 0 then ' · Elo +' || (elo_res->>'delta') else '' end);
              extra_b := ' — 🐉 -' || stolen || (case when elo_res is not null and (elo_res->>'delta')::int > 0 then ' · Elo -' || (elo_res->>'delta') else '' end);
            end if;

            insert into notifications(user_id, type, title, body, read, payload)
            select gm.player_id,
              'guild_event_result',
              case when gm.guild_id = v_win_guild then
                (case when ev.kind='attack' and v_win_guild=ev.guild_a then '⚔ Attaque remportée !' when ev.kind='attack' then '🛡 Défense réussie !' else '🤝 Confrontation remportée' end)
              else
                (case when ev.kind='attack' and v_lose_guild=ev.guild_a then '⚔ Attaque repoussée' when ev.kind='attack' then '💀 Défense enfoncée' else '🤝 Confrontation perdue' end)
              end,
              case when gm.guild_id = v_win_guild then
                'Victoire contre ' || coalesce((case when v_win_guild=ev.guild_a then v_name_b else v_name_a end),'l''adversaire') || (case when ev.kind='attack' then extra_a else '' end) || '.'
              else
                'Défaite contre ' || coalesce((case when v_lose_guild=ev.guild_a then v_name_b else v_name_a end),'l''adversaire') || (case when ev.kind='attack' then extra_b else '' end) || '.'
              end,
              false, jsonb_build_object('event_id', ev.id)
            from guild_members gm where gm.guild_id in (ev.guild_a, ev.guild_b);

            perform guild_journal_log(v_win_guild, 'guild_event_result', null, null, '🏆 Victoire contre ' || coalesce((case when v_win_guild=ev.guild_a then v_name_b else v_name_a end),'l''adversaire') || (case when ev.kind='attack' then extra_a else '' end) || '.');
            perform guild_journal_log(v_lose_guild, 'guild_event_result', null, null, '💀 Défaite contre ' || coalesce((case when v_lose_guild=ev.guild_a then v_name_b else v_name_a end),'l''adversaire') || (case when ev.kind='attack' then extra_b else '' end) || '.');
          end if;
        end;
      end if;

      continue;
    end if;

    select max(ended_at) into last_ended from guild_event_matches where event_id = ev.id;
    if last_ended is not null and now() - last_ended < interval '30 seconds' then
      continue;
    end if;

    select player_id into pa_id from guild_event_participants where event_id = ev.id and team = 'A' and seat = ev.current_seat_a;
    select player_id into pb_id from guild_event_participants where event_id = ev.id and team = 'B' and seat = ev.current_seat_b;
    if pa_id is null or pb_id is null then continue; end if;

    select coalesce(max(seq),0) + 1 into new_seq from guild_event_matches where event_id = ev.id;

    insert into online_games (white_player_id, black_player_id, game_state, turn, timer_seconds, ranked, is_guild_event, guild_event_id)
      values (
        pa_id, pb_id,
        '{
          "board": [
            [null,{"type":"sword","color":"white"},{"type":"epeiste","color":"white"},{"type":"sword","color":"white"},null],
            [null,null,{"type":"shield","color":"white"},null,null],
            [null,null,null,null,null],
            [null,null,{"type":"shield","color":"black"},null,null],
            [null,{"type":"sword","color":"black"},{"type":"epeiste","color":"black"},{"type":"sword","color":"black"},null]
          ],
          "stacks": [[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null]],
          "lastMoved": null, "lastPush": null, "lastMovedByColor": {"white":null,"black":null}
        }'::jsonb,
        'white', ev.cadence, false, true, ev.id
      ) returning id into gid;

    insert into guild_event_matches(event_id, seq, game_id, player_a, player_b)
      values (ev.id, new_seq, gid, pa_id, pb_id) returning id into mid;

    update online_games set guild_event_match_id = mid where id = gid;
    update guild_events set current_game_id = gid, updated_at = now() where id = ev.id;

    kind_label := case when ev.kind='internal' then 'le tournoi interne' when ev.kind='friendly' then 'la confrontation amicale' else 'le combat' end;
    insert into notifications(user_id, type, title, body, read, payload, ref_id)
    values
      (pa_id, 'guild_event_your_turn', '⚔ Ton duel commence !', 'C''est ton tour dans ' || kind_label || ' — rejoins la partie.', false, jsonb_build_object('event_id', ev.id, 'game_id', gid), gid),
      (pb_id, 'guild_event_your_turn', '⚔ Ton duel commence !', 'C''est ton tour dans ' || kind_label || ' — rejoins la partie.', false, jsonb_build_object('event_id', ev.id, 'game_id', gid), gid);

    created := created + 1;
  end loop;

  return jsonb_build_object('created', created, 'resolved', resolved, 'forfeits', forfeits, 'monban_subs', monban_subs);
end $$;

-- ── Trigger réactif : dispatche monban-move dès qu'une partie substituée
-- (is_monban_defense=true) passe au tour de Monban (Noir). Séparé du
-- trigger d'Invasion (invasion_dispatch_monban_trg, sql_a_executer/
-- invasion_reactive_monban.sql) plutôt que fusionné : les deux gardes
-- restent lisibles indépendamment, et aucune des deux tables de contrôle
-- (invasion_requests vs guild_event_participants) ne se mélange.
create or replace function public.guild_dispatch_monban_defense()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  perform net.http_post(
    url := 'https://ikssbshpvpqlcgrbjldz.supabase.co/functions/v1/monban-move',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-monban-secret', '1ea0943dfd093ee488eaca6cf49d2e7811de6474a7f6e0d6'),
    body := jsonb_build_object('game_id', new.id)
  );
  return new;
end $$;

drop trigger if exists guild_dispatch_monban_defense_trg on public.online_games;
create trigger guild_dispatch_monban_defense_trg
  after update of turn on public.online_games
  for each row
  when (new.is_monban_defense = true and new.status = 'active' and new.turn = 'black' and old.turn is distinct from new.turn)
  execute function public.guild_dispatch_monban_defense();

-- Cas particulier : la substitution elle-même (is_monban_defense passe à
-- true, ready_black forcé) ne déclenche PAS le trigger ci-dessus (il
-- n'écoute que UPDATE OF turn, et turn vaut déjà 'white' à ce moment — le
-- créateur du duel, l'attaquant, doit jouer AVANT que Monban n'ait quoi que
-- ce soit à jouer). Rien à faire de plus : le premier coup de l'attaquant
-- fera légitimement passer turn à 'black', ce qui déclenchera le trigger
-- normalement.

-- ── État détaillé : expose plays_as_monban + is_monban_defense côté client
-- (sinon aucun moyen d'afficher un indicateur 🤖 sur le joueur substitué).
create or replace function public.guild_event_state(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; ev record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id into gid from guild_members where player_id = uid;
  select * into ev from guild_events where id = p_event_id and (guild_a = gid or guild_b = gid);
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  return jsonb_build_object(
    'ok', true,
    'event', jsonb_build_object(
      'id', ev.id, 'kind', ev.kind, 'status', ev.status, 'cadence', ev.cadence, 'starts_at', ev.starts_at,
      'registration_closes_at', ev.registration_closes_at, 'created_by', ev.created_by,
      'guild_a', ev.guild_a, 'guild_b', ev.guild_b,
      'guild_a_name', (select name from guilds where id = ev.guild_a),
      'guild_b_name', (select name from guilds where id = ev.guild_b),
      'winner_team', ev.winner_team, 'current_seat_a', ev.current_seat_a, 'current_seat_b', ev.current_seat_b,
      'streak_count', ev.streak_count
    ),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'player_id', gep.player_id, 'pseudo', p.pseudo, 'team', gep.team, 'seat', gep.seat,
        'elo', gep.elo, 'checked_in', gep.checked_in, 'eliminated_at', gep.eliminated_at, 'wins', gep.wins,
        'plays_as_monban', gep.plays_as_monban
      ) order by gep.team, gep.seat nulls last, p.pseudo)
      from guild_event_participants gep join profiles p on p.id = gep.player_id
      where gep.event_id = ev.id
    ), '[]'::jsonb),
    'current_match', (
      select jsonb_build_object(
        'game_id', gem.game_id, 'player_a', gem.player_a, 'player_a_pseudo', pa.pseudo,
        'player_b', gem.player_b, 'player_b_pseudo', pb.pseudo,
        'white_player_id', og.white_player_id, 'black_player_id', og.black_player_id,
        'is_monban_defense', coalesce(og.is_monban_defense,false)
      )
      from guild_event_matches gem
      join profiles pa on pa.id = gem.player_a
      join profiles pb on pb.id = gem.player_b
      left join online_games og on og.id = gem.game_id
      where gem.event_id = ev.id and gem.game_id = ev.current_game_id
      limit 1
    ),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'seq', gem.seq, 'player_a', gem.player_a, 'player_a_pseudo', pa.pseudo,
        'player_b', gem.player_b, 'player_b_pseudo', pb.pseudo,
        'winner', gem.winner, 'started_at', gem.started_at, 'ended_at', gem.ended_at
      ) order by gem.seq desc)
      from guild_event_matches gem
      join profiles pa on pa.id = gem.player_a
      join profiles pb on pb.id = gem.player_b
      where gem.event_id = ev.id and gem.winner is not null
    ), '[]'::jsonb)
  );
end $$;
grant execute on function public.guild_event_state(bigint) to authenticated;

-- ── Contrôle ───────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns where table_name='online_games' and column_name='is_monban_defense') as col_monban_defense, -- attendu 1
  to_regproc('public.guild_events_combat_tick')::text as fn_combat, -- attendu non-null
  to_regproc('public.guild_dispatch_monban_defense')::text as fn_dispatch, -- attendu non-null
  (select count(*) from pg_trigger where tgname = 'guild_dispatch_monban_defense_trg') as trg_installed, -- attendu 1
  'guild_events_g8b_monban_defense OK' as status;
