-- ═══════════════════════════════════════════════════════════════════
-- MOTEUR DE COMBAT SÉQUENTIEL — lot G4 (« le cœur du mode »)
-- docs/ROADMAP_GUILD_BATTLE.md § 7
--
-- Prend le relais du lot G3 : dès qu'un événement est en status='running'
-- (équipes formées, sièges à 1/1), enchaîne réellement les duels façon
-- Tekken Team Battle — le vainqueur reste, le perdant est éliminé, son
-- équipe avance son siège suivant — jusqu'à ce qu'une équipe soit vidée.
--
-- Décisions appliquées :
--  I — strictement séquentiel, un seul duel à la fois.
--  J — pause de 30 s entre deux duels.
--  M — délai de grâce de 60 s : si un des deux joueurs n'a jamais chargé
--      la partie (ready_white/ready_black jamais les deux à true) passé ce
--      délai, il est déclaré forfait. Pas de substitution Monban ici
--      (décision F : Monban ne joue qu'en DÉFENSE d'une attaque de guilde,
--      jamais dans un tournoi interne) — le joueur absent est simplement
--      éliminé, comme n'importe quelle défaite.
--  S — aucune récompense (Ryu) à la clôture, prestige seul.
--
-- Chaque duel est une partie en ligne NORMALE (online_games), juste taguée
-- (is_guild_event/guild_event_id/guild_event_match_id) pour que le lot G5
-- (spectateur + arbre) puisse la retrouver sans reparcourir tout
-- l'historique. `ranked=false` : ces duels ne touchent jamais l'Elo
-- personnel (décision H, prise pour le chantier dans son ensemble).
-- ═══════════════════════════════════════════════════════════════════

alter table public.guild_events add column if not exists winner_team text check (winner_team in ('A','B'));

alter table public.online_games add column if not exists is_guild_event boolean not null default false;
alter table public.online_games add column if not exists guild_event_id bigint references public.guild_events(id) on delete set null;
alter table public.online_games add column if not exists guild_event_match_id bigint;

create table if not exists public.guild_event_matches (
  id          bigint generated always as identity primary key,
  event_id    bigint not null references public.guild_events(id) on delete cascade,
  seq         int not null,
  game_id     uuid references public.online_games(id),
  player_a    uuid not null references public.profiles(id),
  player_b    uuid not null references public.profiles(id),
  winner      text check (winner in ('A','B')),
  started_at  timestamptz not null default now(),
  ended_at    timestamptz
);
create index if not exists guild_event_matches_event_idx on public.guild_event_matches(event_id, seq);

alter table public.guild_event_matches enable row level security;
drop policy if exists guild_event_matches_select_members on public.guild_event_matches;
create policy guild_event_matches_select_members on public.guild_event_matches
  for select using (exists (
    select 1 from guild_events ge join guild_members gm on gm.player_id = auth.uid()
      and (gm.guild_id = ge.guild_a or gm.guild_id = ge.guild_b)
    where ge.id = guild_event_matches.event_id
  ));
-- Aucune politique INSERT/UPDATE/DELETE : écriture exclusivement via le
-- tick serveur ci-dessous (SECURITY DEFINER).

-- ── Tick pg_cron : fait vivre TOUS les tournois internes en cours ──────
create or replace function public.guild_events_combat_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  ev record; g record; pa_id uuid; pb_id uuid; winner_side text; loser_team text;
  next_seat int; team_size int; last_ended timestamptz; new_seq int;
  created int := 0; resolved int := 0; forfeits int := 0;
  gid uuid; mid bigint;
begin
  for ev in select * from guild_events where status = 'running' loop

    -- 1) Un duel est déjà en cours pour cet événement.
    if ev.current_game_id is not null then
      select * into g from online_games where id = ev.current_game_id;
      if g is null then
        -- Partie disparue (ne devrait jamais arriver) : on repart à zéro.
        update guild_events set current_game_id = null where id = ev.id;
        continue;
      end if;

      -- 1a) Forfait : 60 s sans que les DEUX joueurs aient chargé la partie.
      if g.status = 'active' and not (coalesce(g.ready_white,false) and coalesce(g.ready_black,false))
         and now() - g.created_at > interval '60 seconds' then
        winner_side := case when coalesce(g.ready_white,false) then 'white' else 'black' end;
        -- Si NI l'un ni l'autre n'est prêt (les deux absents), le duel est
        -- rejoué à l'identique plus tard plutôt que de trancher au hasard :
        -- on referme juste la partie sans résultat et on relance le même duel.
        if not coalesce(g.ready_white,false) and not coalesce(g.ready_black,false) then
          update online_games set status = 'finished' where id = g.id;
          update guild_event_matches set ended_at = now() where event_id = ev.id and game_id = g.id;
          update guild_events set current_game_id = null where id = ev.id;
          continue;
        end if;
        update online_games set status = 'finished', winner = winner_side where id = g.id;
        forfeits := forfeits + 1;
        -- tombe dans la résolution ci-dessous via une relecture immédiate
        select * into g from online_games where id = g.id;
      end if;

      if g.status <> 'finished' or g.winner is null then
        continue; -- toujours en cours, rien à faire ce tick
      end if;

      -- 2) Duel résolu : élimine le perdant, avance son équipe, calcule le streak.
      -- Convention de couleur des duels générés ci-dessous : équipe A = blanc, équipe B = noir.
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

        -- Le siège d'une équipe ne bouge QUE quand elle perd : si l'équipe
        -- gagnante a aussi gagné le duel précédent, c'est FORCÉMENT le même
        -- joueur qui reste sur le ring (le champion) — inutile de comparer
        -- les identités, comparer les équipes gagnantes suffit.
        -- 🔴 winner is not null : exclut les tentatives ABANDONNÉES (60s sans
        -- que personne ne charge la partie, cf. section 1a) — un abandon
        -- n'a jamais désigné de champion, il ne doit pas casser le streak
        -- du précédent VRAI vainqueur (bug vécu en test : streak retombait à
        -- 1 après une 2e victoire consécutive du même joueur, dès qu'une
        -- tentative sans résultat s'était intercalée entre les deux duels).
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

      -- Tournoi terminé à l'instant : notifier + journaliser (pas de Ryu, décision S).
      if exists (select 1 from guild_events where id = ev.id and status = 'finished' and winner_team is not null and updated_at > now() - interval '5 seconds') then
        declare v_win_team text;
        begin
          select winner_team into v_win_team from guild_events where id = ev.id;
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
        end;
      end if;

      continue; -- ce tick a déjà fait le nécessaire pour cet événement
    end if;

    -- 3) Aucun duel en cours : le tournoi vient-il de commencer (pas de
    --    match encore) ou faut-il respecter la pause de 30 s (décision J) ?
    select max(ended_at) into last_ended from guild_event_matches where event_id = ev.id;
    if last_ended is not null and now() - last_ended < interval '30 seconds' then
      continue; -- encore en pause
    end if;

    select player_id into pa_id from guild_event_participants where event_id = ev.id and team = 'A' and seat = ev.current_seat_a;
    select player_id into pb_id from guild_event_participants where event_id = ev.id and team = 'B' and seat = ev.current_seat_b;
    if pa_id is null or pb_id is null then continue; end if; -- composition incomplète, rien à faire

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

    -- ref_id = l'id de la partie : permet au clic sur la notif d'ouvrir
    -- directement le duel (joinGuildEventDuel côté client), sans repasser
    -- par l'écran du tournoi.
    insert into notifications(user_id, type, title, body, read, payload, ref_id)
    values
      (pa_id, 'guild_event_your_turn', '⚔ Ton duel commence !', 'C''est ton tour dans le tournoi interne — rejoins la partie.', false, jsonb_build_object('event_id', ev.id, 'game_id', gid), gid),
      (pb_id, 'guild_event_your_turn', '⚔ Ton duel commence !', 'C''est ton tour dans le tournoi interne — rejoins la partie.', false, jsonb_build_object('event_id', ev.id, 'game_id', gid), gid);

    created := created + 1;
  end loop;

  return jsonb_build_object('created', created, 'resolved', resolved, 'forfeits', forfeits);
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'guild_events_combat_tick') then
    perform cron.unschedule('guild_events_combat_tick');
  end if;
end $$;
select cron.schedule('guild_events_combat_tick', '20 seconds', $$select public.guild_events_combat_tick();$$);

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regclass('public.guild_event_matches')::text as tbl_matches,             -- attendu non-null
  to_regproc('public.guild_events_combat_tick')::text as fn_tick,             -- attendu non-null
  (select count(*) from cron.job where jobname = 'guild_events_combat_tick') as cron_scheduled, -- attendu 1
  'guild_events_g4 OK' as status;
