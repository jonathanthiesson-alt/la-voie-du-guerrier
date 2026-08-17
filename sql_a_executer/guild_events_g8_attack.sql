-- ═══════════════════════════════════════════════════════════════════
-- ATTAQUE DE GUILDE — lot G8 (dernier du chantier), docs/ROADMAP_GUILD_BATTLE.md § 7
--
-- Réutilise tout le moteur G2→G7 (kind='attack', déjà prévu au schéma) :
-- inscriptions/équipes/combat/arbre/Elo fonctionnent sans modification.
-- Ce lot ajoute ce qui est SPÉCIFIQUE à l'attaque : pas d'acceptation du
-- défenseur (l'attaque se déclare, ne se négocie pas), cooldowns (V),
-- ciblage par tranche de classement (AG), vol de 10 Ryu (AA), effet plein
-- sur l'Elo de guilde (AJ), annulation asymétrique côté attaquant (R/W),
-- pénalités défense vide / effectif attaquant insuffisant (Q/X).
--
-- 🔴 LIMITATION CONNUE, documentée ici plutôt que cachée (décision F) :
-- « Monban remplace en DÉFENSE uniquement » — un défenseur absent au
-- forfait (60 s, décision M) devrait voir Monban reprendre son duel,
-- comme en Invasion (lot G0). Ce lot ne construit PAS cette substitution
-- réactive (nécessiterait de généraliser le trigger pg_net/Edge Function
-- monban-move au-delà de l'Invasion — chantier à part entière). Pour
-- l'instant, un défenseur absent au forfait est simplement ÉLIMINÉ comme
-- n'importe quel forfait de Tournoi interne/Confrontation amicale — PAS
-- le comportement décidé. À traiter dans un lot dédié avant mise en avant
-- publique du mode.
-- ═══════════════════════════════════════════════════════════════════

alter table public.guilds add column if not exists last_attack_at timestamptz;
alter table public.guilds add column if not exists last_attacked_at timestamptz;

-- ── Candidats à l'attaque, par tranche d'Elo (même patron qu'invasion_candidates) ──
create or replace function public.guild_attack_candidates(p_elo_min int, p_elo_max int)
returns table(id bigint, name text, tag text, guild_elo int) language sql security definer set search_path to 'public' as $$
  select g.id, g.name, g.tag, g.guild_elo
  from guilds g
  where g.id <> (select guild_id from guild_members where player_id = auth.uid())
    and g.guild_elo between p_elo_min and p_elo_max
    and (g.last_attacked_at is null or g.last_attacked_at < now() - interval '4 days')
    and not exists (
      select 1 from guild_events ge where ge.kind = 'attack' and ge.status not in ('finished','cancelled')
        and (ge.guild_a = g.id or ge.guild_b = g.id)
    )
  order by g.guild_elo asc
  limit 20;
$$;
grant execute on function public.guild_attack_candidates(int, int) to authenticated;

-- ── Déclarer une attaque (chef uniquement, aucune acceptation requise —
-- décision R : l'attaque ne se négocie pas, contrairement à l'amical).
create or replace function public.guild_attack_declare(p_target_guild_id bigint, p_cadence int, p_starts_at timestamptz)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; myrole text; already int; eid bigint;
  v_pseudo text; my_name text; target_name text; v_closes timestamptz;
  my_admin boolean; target_has_admin boolean; my_last_attack timestamptz; target_last_attacked timestamptz;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if p_target_guild_id = gid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  if not exists (select 1 from guilds where id = p_target_guild_id) then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if p_cadence not in (3,5,10) then return jsonb_build_object('ok', false, 'reason', 'bad_cadence'); end if;
  if p_starts_at < now() + interval '15 minutes' then return jsonb_build_object('ok', false, 'reason', 'too_soon'); end if;
  if p_starts_at > now() + interval '48 hours' then return jsonb_build_object('ok', false, 'reason', 'too_far'); end if;

  -- Décision AD (étendue de l'Invasion à l'Attaque, annoncée au § 3 du
  -- cadrage) : un admin (Wurmz/Musashi) échappe aux cooldowns, en attaque
  -- ET en défense. Toujours via is_admin_user()/profiles.is_admin, jamais
  -- une liste de pseudos en dur.
  select is_admin_user() into my_admin;
  select exists(select 1 from guild_members gm join profiles p on p.id = gm.player_id where gm.guild_id = p_target_guild_id and p.is_admin) into target_has_admin;

  select last_attack_at into my_last_attack from guilds where id = gid;
  if not coalesce(my_admin,false) and my_last_attack is not null and my_last_attack > now() - interval '7 days' then
    return jsonb_build_object('ok', false, 'reason', 'attacker_cooldown');
  end if;

  select last_attacked_at into target_last_attacked from guilds where id = p_target_guild_id;
  if not (coalesce(my_admin,false) or coalesce(target_has_admin,false)) and target_last_attacked is not null and target_last_attacked > now() - interval '4 days' then
    return jsonb_build_object('ok', false, 'reason', 'target_cooldown');
  end if;

  select count(*) into already from guild_events
    where kind = 'attack' and status not in ('finished','cancelled')
      and (guild_a in (gid, p_target_guild_id) or guild_b in (gid, p_target_guild_id));
  if already > 0 then return jsonb_build_object('ok', false, 'reason', 'busy'); end if;

  v_closes := p_starts_at - interval '5 minutes';
  insert into guild_events(kind, guild_a, guild_b, cadence, starts_at, registration_closes_at, created_by, status)
    values ('attack', gid, p_target_guild_id, p_cadence, p_starts_at, v_closes, uid, 'scheduled')
    returning id into eid;

  -- Le cooldown démarre à la DÉCLARATION, pas au résultat (décision R : il
  -- reste consommé même en cas d'annulation).
  update guilds set last_attack_at = now() where id = gid;
  update guilds set last_attacked_at = now() where id = p_target_guild_id;

  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  select name into my_name from guilds where id = gid;
  select name into target_name from guilds where id = p_target_guild_id;

  insert into notifications(user_id, type, title, body, read, payload)
  select gm2.player_id, 'guild_attack_declared', '⚔ Attaque de guilde !',
    coalesce(my_name,'Une guilde rivale') || ' (chef ' || coalesce(v_pseudo,'?') || ') attaque votre guilde le ' || to_char(p_starts_at, 'DD/MM à HH24:MI') || ' — inscrivez vos défenseurs !',
    false, jsonb_build_object('event_id', eid)
  from guild_members gm2 where gm2.guild_id = p_target_guild_id;

  insert into notifications(user_id, type, title, body, read, payload)
  select gm2.player_id, 'guild_attack_declared', '⚔ Attaque lancée !',
    'Votre guilde attaque ' || coalesce(target_name,'une guilde rivale') || ' le ' || to_char(p_starts_at, 'DD/MM à HH24:MI') || ' — inscrivez vos combattants !',
    false, jsonb_build_object('event_id', eid)
  from guild_members gm2 where gm2.guild_id = gid;

  perform guild_journal_log(gid, 'guild_attack_declared', uid, null, '⚔ Attaque lancée contre ' || coalesce(target_name,'une guilde') || ' pour le ' || to_char(p_starts_at, 'DD/MM à HH24:MI') || '.');
  perform guild_journal_log(p_target_guild_id, 'guild_attack_declared', uid, null, '⚔ ' || coalesce(my_name,'Une guilde rivale') || ' attaque, prévue le ' || to_char(p_starts_at, 'DD/MM à HH24:MI') || '.');
  return jsonb_build_object('ok', true, 'event_id', eid);
end $$;
grant execute on function public.guild_attack_declare(bigint, int, timestamptz) to authenticated;

-- ── Annuler une attaque : ATTAQUANT SEUL, jusqu'à 1h avant (décision R) ──
-- Le cooldown hebdomadaire reste consommé (déjà vrai : posé à la
-- déclaration, jamais retiré ici) et 5 🐉 sont transférés au défenseur
-- (décision W : un transfert, pas de monnaie créée).
create or replace function public.guild_attack_cancel(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; myrole text; v_pseudo text; name_b text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id and kind = 'attack';
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select role into myrole from guild_members where guild_id = ev.guild_a and player_id = uid;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if ev.status in ('running','finished','cancelled') then return jsonb_build_object('ok', false, 'reason', 'too_late'); end if;
  if now() > ev.starts_at - interval '1 hour' then return jsonb_build_object('ok', false, 'reason', 'too_late'); end if;

  update guild_events set status = 'cancelled', cancelled_by = uid, updated_at = now() where id = p_event_id;
  update guilds set ryu_total = greatest(0, ryu_total - 5) where id = ev.guild_a;
  update guilds set ryu_total = ryu_total + 5 where id = ev.guild_b;

  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  select name into name_b from guilds where id = ev.guild_b;

  insert into notifications(user_id, type, title, body, read, payload)
  select gm.player_id, 'guild_attack_cancelled', '⚔ Attaque annulée',
    coalesce(v_pseudo,'Votre chef') || ' a annulé l''attaque contre ' || coalesce(name_b,'la guilde ciblée') || ' — 5 🐉 versés en dédommagement.',
    false, jsonb_build_object('event_id', ev.id)
  from guild_members gm where gm.guild_id = ev.guild_a;

  insert into notifications(user_id, type, title, body, read, payload)
  select gm.player_id, 'guild_attack_cancelled', '🛡 Attaque annulée',
    'L''attaque contre votre guilde a été annulée — vous recevez 5 🐉 en dédommagement.',
    false, jsonb_build_object('event_id', ev.id)
  from guild_members gm where gm.guild_id = ev.guild_b;

  perform guild_journal_log(ev.guild_a, 'guild_attack_cancelled', uid, null, '⚔ Attaque contre ' || coalesce(name_b,'la guilde ciblée') || ' annulée par ' || coalesce(v_pseudo,'le chef') || ' — -5 🐉.');
  perform guild_journal_log(ev.guild_b, 'guild_attack_cancelled', uid, null, '🛡 Attaque adverse annulée — +5 🐉.');
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_attack_cancel(bigint) to authenticated;

-- ── guild_event_cancel : bloque la voie générique pour kind='attack' ────
-- (l'annulation d'une attaque a des règles propres — asymétrique, fenêtre
-- 1h, pénalité — décision R : passe exclusivement par guild_attack_cancel.)
create or replace function public.guild_event_cancel(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; myrole text; v_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if ev.kind = 'attack' then return jsonb_build_object('ok', false, 'reason', 'use_guild_attack_cancel'); end if;
  select role into myrole from guild_members where player_id = uid and guild_id in (ev.guild_a, ev.guild_b);
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if ev.status in ('running','finished','cancelled') then return jsonb_build_object('ok', false, 'reason', 'too_late'); end if;
  update guild_events set status = 'cancelled', cancelled_by = uid, updated_at = now() where id = p_event_id;
  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  perform guild_journal_log(ev.guild_a, 'guild_event_cancelled', uid, null, '🚫 ' || (case when ev.kind='internal' then 'Tournoi interne' else 'Confrontation amicale' end) || ' annulé(e) par ' || coalesce(v_pseudo,'un chef') || '.');
  if ev.guild_b is not null then
    perform guild_journal_log(ev.guild_b, 'guild_event_cancelled', uid, null, '🚫 Confrontation amicale annulée par ' || coalesce(v_pseudo,'un chef') || '.');
  end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_cancel(bigint) to authenticated;

-- ── Tick de check-in : ajoute les pénalités Q (défense vide) et X (effectif
-- attaquant insuffisant), spécifiques à kind='attack' ; comportement
-- inchangé pour internal/friendly (simple annulation sans enjeu, O).
create or replace function public.guild_events_checkin_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare ev record; opened int := 0; started int := 0; noshow int; cnt_a int; cnt_b int; v_name_a text; v_name_b text;
begin
  for ev in
    select * from guild_events
    where status = 'registration_closed' and now() >= starts_at - interval '5 minutes'
  loop
    select count(*) filter (where team = 'A'), count(*) filter (where team = 'B')
      into cnt_a, cnt_b from guild_event_participants where event_id = ev.id;

    if ev.kind = 'attack' and cnt_b = 0 then
      -- décision Q : défense vide → attaque annulée, la guilde défenseure
      -- perd 5 🐉 (moitié prix), transférés à l'attaquant en dédommagement.
      update guilds set ryu_total = greatest(0, ryu_total - 5) where id = ev.guild_b;
      update guilds set ryu_total = ryu_total + 5 where id = ev.guild_a;
      update guild_events set status = 'cancelled', updated_at = now() where id = ev.id;
      select name into v_name_a from guilds where id = ev.guild_a;
      select name into v_name_b from guilds where id = ev.guild_b;
      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_attack_cancelled', '🛡 Attaque annulée — défense vide',
        'Personne ne s''est présenté pour défendre — ' || coalesce(v_name_b,'la guilde ciblée') || ' perd 5 🐉.', false, jsonb_build_object('event_id', ev.id)
      from guild_members gm where gm.guild_id in (ev.guild_a, ev.guild_b);
      perform guild_journal_log(ev.guild_a, 'guild_attack_cancelled', null, null, '🛡 Attaque contre ' || coalesce(v_name_b,'la guilde ciblée') || ' annulée (défense vide) — +5 🐉.');
      perform guild_journal_log(ev.guild_b, 'guild_attack_cancelled', null, null, '🛡 Défense manquée contre ' || coalesce(v_name_a,'l''attaquant') || ' — -5 🐉.');
      continue;
    end if;

    if ev.kind = 'attack' and cnt_a < 3 then
      -- décision X : effectif attaquant insuffisant → même traitement
      -- qu'une annulation volontaire (décision R).
      update guilds set ryu_total = greatest(0, ryu_total - 5) where id = ev.guild_a;
      update guilds set ryu_total = ryu_total + 5 where id = ev.guild_b;
      update guild_events set status = 'cancelled', updated_at = now() where id = ev.id;
      select name into v_name_a from guilds where id = ev.guild_a;
      select name into v_name_b from guilds where id = ev.guild_b;
      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_attack_cancelled', '⚔ Attaque annulée — effectif insuffisant',
        coalesce(v_name_a,'L''attaquant') || ' n''a pas réuni assez de combattants — 5 🐉 versés à ' || coalesce(v_name_b,'la guilde ciblée') || '.', false, jsonb_build_object('event_id', ev.id)
      from guild_members gm where gm.guild_id in (ev.guild_a, ev.guild_b);
      perform guild_journal_log(ev.guild_a, 'guild_attack_cancelled', null, null, '⚔ Attaque contre ' || coalesce(v_name_b,'la guilde ciblée') || ' annulée (effectif insuffisant) — -5 🐉.');
      perform guild_journal_log(ev.guild_b, 'guild_attack_cancelled', null, null, '⚔ Attaque avortée de ' || coalesce(v_name_a,'l''attaquant') || ' — +5 🐉.');
      continue;
    end if;

    if cnt_a < 3 or cnt_b < 3 then
      update guild_events set status = 'cancelled', updated_at = now() where id = ev.id;
      continue;
    end if;

    update guild_events set status = 'checkin', updated_at = now() where id = ev.id;
    insert into notifications(user_id, type, title, body, read, payload)
    select gep.player_id, 'guild_event_starting', '🚪 Check-in ouvert !',
      'Le ' || (case when ev.kind='internal' then 'tournoi interne' when ev.kind='friendly' then 'combat amical' else 'combat' end) || ' commence dans 5 minutes — confirme ta présence maintenant.',
      false, jsonb_build_object('event_id', ev.id)
    from guild_event_participants gep where gep.event_id = ev.id;
    opened := opened + 1;
  end loop;

  for ev in select * from guild_events where status = 'checkin' and now() >= starts_at loop
    delete from guild_event_participants where event_id = ev.id and checked_in = false;
    get diagnostics noshow = row_count;
    update guild_event_participants gep set seat = ranked.rk
      from (
        select player_id, row_number() over (partition by team order by seat asc) as rk
        from guild_event_participants where event_id = ev.id
      ) ranked
      where gep.event_id = ev.id and gep.player_id = ranked.player_id;

    if not exists (select 1 from guild_event_participants where event_id = ev.id and team = 'A')
       or not exists (select 1 from guild_event_participants where event_id = ev.id and team = 'B') then
      update guild_events set status = 'cancelled', updated_at = now() where id = ev.id;
    else
      update guild_events set status = 'running', current_seat_a = 1, current_seat_b = 1, updated_at = now() where id = ev.id;
    end if;
    started := started + 1;
  end loop;

  return jsonb_build_object('opened', opened, 'started', started);
end $$;

-- ── Tick de combat : résolution finale kind-aware, vol de Ryu + Elo plein
-- pour l'Attaque (AA/AJ), notifie les DEUX guildes pour friendly/attack
-- (corrige au passage un trou de G6 : le bloc de fin ne notifiait que
-- guild_a, avec un texte « équipe A/B » qui ne nomme jamais les guildes).
create or replace function public.guild_events_combat_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  ev record; g record; pa_id uuid; pb_id uuid; winner_side text; loser_team text;
  next_seat int; team_size int; last_ended timestamptz; new_seq int;
  created int := 0; resolved int := 0; forfeits int := 0;
  gid uuid; mid bigint; kind_label text;
begin
  for ev in select * from guild_events where status = 'running' loop

    if ev.current_game_id is not null then
      select * into g from online_games where id = ev.current_game_id;
      if g is null then
        update guild_events set current_game_id = null where id = ev.id;
        continue;
      end if;

      if g.status = 'active' and not (coalesce(g.ready_white,false) and coalesce(g.ready_black,false))
         and now() - g.created_at > interval '60 seconds' then
        winner_side := case when coalesce(g.ready_white,false) then 'white' else 'black' end;
        if not coalesce(g.ready_white,false) and not coalesce(g.ready_black,false) then
          update online_games set status = 'finished' where id = g.id;
          update guild_event_matches set ended_at = now() where event_id = ev.id and game_id = g.id;
          update guild_events set current_game_id = null where id = ev.id;
          continue;
        end if;
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

            kind_label := case when ev.kind = 'attack' then (case when v_win_team='A' then '⚔ Attaque remportée !' else '🛡 Défense réussie !' end) else '🤝 Confrontation amicale terminée' end;

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

  return jsonb_build_object('created', created, 'resolved', resolved, 'forfeits', forfeits);
end $$;

-- ── Contrôle ───────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns where table_name='guilds' and column_name='last_attack_at') as col_attack,   -- attendu 1
  (select count(*) from information_schema.columns where table_name='guilds' and column_name='last_attacked_at') as col_defend, -- attendu 1
  to_regproc('public.guild_attack_candidates')::text as fn_candidates, -- attendu non-null
  to_regproc('public.guild_attack_declare')::text as fn_declare,       -- attendu non-null
  to_regproc('public.guild_attack_cancel')::text as fn_cancel,         -- attendu non-null
  'guild_events_g8_attack OK' as status;
