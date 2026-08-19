-- ═══════════════════════════════════════════════════════════════════
-- MONBAN — pénalité de niveau sur une défense perdue (décision Wurmz
-- 2026-08-19) : « gagner ne lui fait pas prendre de skill, perdre lui
-- fait perdre du skill » — asymétrique avec ses propres duels
-- d'entraînement (voir monban_training_duel.sql), où c'est l'inverse
-- (jamais de perte). Ne s'applique QUE quand Monban a RÉELLEMENT joué la
-- défense (substitution), jamais quand le joueur a défendu en personne et
-- perdu — ce serait punir Monban pour une partie qu'il n'a pas jouée.
-- ═══════════════════════════════════════════════════════════════════

-- ── Helper partagé : -1 de skillRating, plancher 0. Jamais exposé côté
-- client (appelé uniquement depuis invasion_resolve_internal et
-- guild_events_combat_tick, tous deux SECURITY DEFINER).
create or replace function public.monban_apply_defense_loss(p_user_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare cur jsonb; new_sr int;
begin
  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (p_user_id, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;
  select profile into cur from monban_profiles where user_id = p_user_id;
  new_sr := greatest(0, coalesce((cur->>'skillRating')::int, 50) - 1);
  update monban_profiles set profile = jsonb_set(cur, '{skillRating}', to_jsonb(new_sr)) where user_id = p_user_id;
end $$;
revoke all on function public.monban_apply_defense_loss(uuid) from public, anon, authenticated;

-- ── Invasion : pénalité si Monban a joué (status != 'accepted', donc pas
-- de duel live) ET a perdu. v_was_live vient déjà de invasion_requests.
create or replace function public.invasion_resolve_internal(p_game_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare
  g record; v_winner_id uuid; v_loser_id uuid; v_currency text; v_col text; v_amt int := 1;
  names text[] := array['shiso_balance','tamashii_balance','mon_balance','ryu_balance','hanafuda_balance','shiitake_balance','fame_balance','roku_balance'];
  vals int[]; i int; best_i int := 1; best_v int := -1; v int;
  v_was_live boolean;
begin
  select * into g from online_games where id = p_game_id and is_invasion = true and coalesce(invasion_resolved,false) = false;
  if not found or g.winner is null then return; end if;

  v_winner_id := case when g.winner = 'white' then g.white_player_id else g.black_player_id end;
  v_loser_id  := case when g.winner = 'white' then g.black_player_id else g.white_player_id end;

  select array[shiso_balance,tamashii_balance,mon_balance,ryu_balance,hanafuda_balance,shiitake_balance,fame_balance,roku_balance]
    into vals from profiles where id = v_loser_id;
  for i in 1..array_length(names,1) loop
    v := coalesce(vals[i], 0);
    if v > best_v then best_v := v; best_i := i; end if;
  end loop;
  v_col := names[best_i];
  v_currency := replace(v_col, '_balance', '');

  execute format('update profiles set %I = greatest(0, %I - $1) where id = $2', v_col, v_col) using v_amt, v_loser_id;
  execute format('update profiles set %I = %I + $1 where id = $2', v_col, v_col) using v_amt, v_winner_id;

  select (status = 'accepted') into v_was_live from invasion_requests where game_id = p_game_id order by created_at desc limit 1;

  insert into invasion_history (attacker_id, defender_id, winner_id, currency, amount, live, game_id)
    values (g.invasion_attacker_id, g.invasion_defender_id, v_winner_id, v_currency, v_amt, coalesce(v_was_live,false), p_game_id);

  -- Décision : les stats de défense comptent que le défenseur ait joué en
  -- personne ou que Monban ait pris le relais — c'est le dojo qui est jugé.
  insert into monban_stats (user_id, defends_won, defends_lost, updated_at)
    values (g.invasion_defender_id,
            case when v_winner_id = g.invasion_defender_id then 1 else 0 end,
            case when v_winner_id = g.invasion_defender_id then 0 else 1 end,
            now())
    on conflict (user_id) do update set
      defends_won = monban_stats.defends_won + excluded.defends_won,
      defends_lost = monban_stats.defends_lost + excluded.defends_lost,
      updated_at = now();

  -- Pénalité de NIVEAU MONBAN (distincte de monban_stats ci-dessus) :
  -- uniquement si Monban a réellement joué (pas live) ET a perdu.
  if not coalesce(v_was_live, true) and v_winner_id <> g.invasion_defender_id then
    perform monban_apply_defense_loss(g.invasion_defender_id);
  end if;

  insert into notifications (user_id, type, title, body, ref_id, payload) values
    (g.invasion_defender_id,
     case when v_winner_id = g.invasion_defender_id then 'invasion_defended' else 'invasion_lost' end,
     case when v_winner_id = g.invasion_defender_id then 'Invasion repoussée !' else 'Invasion perdue' end,
     case when v_winner_id = g.invasion_defender_id then 'Ton dojo a tenu bon.' else 'Ton dojo est tombé — 1 '||v_currency||' perdu.' end,
     p_game_id, jsonb_build_object('currency', v_currency, 'amount', v_amt)),
    (g.invasion_attacker_id,
     case when v_winner_id = g.invasion_attacker_id then 'invasion_won' else 'invasion_repelled' end,
     case when v_winner_id = g.invasion_attacker_id then 'Invasion réussie !' else 'Invasion repoussée' end,
     case when v_winner_id = g.invasion_attacker_id then 'Tu as pillé 1 '||v_currency||'.' else 'Le défenseur a tenu bon.' end,
     p_game_id, jsonb_build_object('currency', v_currency, 'amount', v_amt));

  insert into player_journal (user_id, event_type, message) values
    (g.invasion_defender_id,
     case when v_winner_id = g.invasion_defender_id then 'invasion_defended' else 'invasion_lost' end,
     case when v_winner_id = g.invasion_defender_id then 'A repoussé une invasion.' else 'A perdu une invasion ('||v_currency||').' end),
    (g.invasion_attacker_id,
     case when v_winner_id = g.invasion_attacker_id then 'invasion_won' else 'invasion_repelled' end,
     case when v_winner_id = g.invasion_attacker_id then 'A réussi une invasion ('||v_currency||').' else 'A été repoussé en tentant une invasion.' end);

  update online_games set invasion_resolved = true, status = 'finished' where id = p_game_id;
  update invasion_requests set status = 'resolved' where game_id = p_game_id;
end; $$;
revoke execute on function public.invasion_resolve_internal(uuid) from public, anon, authenticated;

-- ── Combat de guilde : pénalité si is_monban_defense=true (Monban joue
-- TOUJOURS Noir dans ce cas) ET que Noir a perdu ce duel précis.
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

        -- Pénalité de NIVEAU MONBAN : uniquement si CE duel précis a été
        -- substitué (is_monban_defense=true) ET que Monban (toujours Noir)
        -- l'a perdu. Jamais si le défenseur a joué en personne.
        if coalesce(g.is_monban_defense,false) and loser_player = g.black_player_id then
          perform monban_apply_defense_loss(loser_player);
        end if;

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

select 'monban_defense_penalty OK' as status;
