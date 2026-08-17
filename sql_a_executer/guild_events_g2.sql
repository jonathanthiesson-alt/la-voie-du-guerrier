-- ═══════════════════════════════════════════════════════════════════
-- TOURNOI INTERNE — lot G2, docs/ROADMAP_GUILD_BATTLE.md § 7
--
-- Planification + inscriptions du Tournoi interne (mode Combat de guilde).
-- PAS ENCORE de combat (G4), PAS ENCORE de constitution d'équipe (G3) — ce
-- lot s'arrête à la clôture des inscriptions. `guild_events` et
-- `guild_event_participants` sont conçues pour servir aussi aux futurs
-- modes 'friendly' et 'attack' (schéma esquissé au § 4 du cadrage), mais
-- SEUL kind='internal' est utilisable pour l'instant — les RPC ci-dessous
-- ne créent que ce type.
--
-- Décisions appliquées : N (le GM choisit la cadence 3/5/10s à la
-- création), S (aucune récompense — prestige seul — et un seul tournoi
-- interne à la fois par guilde, pas d'autre limite de fréquence), A (Elo
-- figé à l'inscription).
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.guild_events (
  id                      bigint generated always as identity primary key,
  kind                    text not null check (kind in ('internal','friendly','attack')),
  guild_a                 bigint not null references public.guilds(id) on delete cascade,
  guild_b                 bigint references public.guilds(id) on delete cascade, -- null si interne
  status                  text not null default 'scheduled' check (status in ('scheduled','registration_closed','checkin','running','finished','cancelled')),
  cadence                 int not null check (cadence in (3,5,10)),
  starts_at               timestamptz not null,
  registration_closes_at  timestamptz not null,
  created_by              uuid not null references public.profiles(id),
  winner_guild            bigint references public.guilds(id),
  current_game_id         uuid references public.online_games(id),
  current_seat_a          int,
  current_seat_b          int,
  streak_count            int not null default 0,
  cancelled_by            uuid references public.profiles(id),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index if not exists guild_events_guild_a_idx on public.guild_events(guild_a, status);
create index if not exists guild_events_guild_b_idx on public.guild_events(guild_b, status);

create table if not exists public.guild_event_participants (
  event_id         bigint not null references public.guild_events(id) on delete cascade,
  player_id        uuid not null references public.profiles(id) on delete cascade,
  team             text check (team in ('A','B')),  -- assigné au lot G3, null jusque-là
  seat             int,                              -- ordre de passage, assigné au lot G3
  elo              int not null,                      -- figé à l'inscription (décision A)
  checked_in       boolean not null default false,
  plays_as_monban  boolean not null default false,
  eliminated_at    timestamptz,
  eliminated_by    uuid references public.profiles(id),
  wins             int not null default 0,
  registered_at    timestamptz not null default now(),
  primary key (event_id, player_id)
);

alter table public.guild_events enable row level security;
drop policy if exists guild_events_select_members on public.guild_events;
create policy guild_events_select_members on public.guild_events
  for select using (exists (
    select 1 from guild_members gm where gm.player_id = auth.uid()
      and (gm.guild_id = guild_events.guild_a or gm.guild_id = guild_events.guild_b)
  ));

alter table public.guild_event_participants enable row level security;
drop policy if exists guild_event_participants_select_members on public.guild_event_participants;
create policy guild_event_participants_select_members on public.guild_event_participants
  for select using (exists (
    select 1 from guild_events ge join guild_members gm on gm.player_id = auth.uid()
      and (gm.guild_id = ge.guild_a or gm.guild_id = ge.guild_b)
    where ge.id = guild_event_participants.event_id
  ));
-- Aucune politique INSERT/UPDATE/DELETE sur les deux tables : toute écriture
-- passe par les RPC SECURITY DEFINER ci-dessous.

-- ── Planifier un Tournoi interne (GM uniquement) ───────────────────────
create or replace function public.guild_event_create(p_cadence int, p_starts_at timestamptz, p_registration_closes_at timestamptz)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; myrole text; already int; eid bigint; v_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if p_cadence not in (3,5,10) then return jsonb_build_object('ok', false, 'reason', 'bad_cadence'); end if;
  if p_starts_at <= now() then return jsonb_build_object('ok', false, 'reason', 'starts_in_past'); end if;
  if p_registration_closes_at > p_starts_at then return jsonb_build_object('ok', false, 'reason', 'closes_after_start'); end if;
  if p_registration_closes_at <= now() then return jsonb_build_object('ok', false, 'reason', 'closes_in_past'); end if;
  -- Décision S : un seul Tournoi interne à la fois par guilde.
  select count(*) into already from guild_events
    where kind = 'internal' and guild_a = gid and status not in ('finished','cancelled');
  if already > 0 then return jsonb_build_object('ok', false, 'reason', 'busy'); end if;

  insert into guild_events(kind, guild_a, cadence, starts_at, registration_closes_at, created_by)
    values ('internal', gid, p_cadence, p_starts_at, p_registration_closes_at, uid)
    returning id into eid;

  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  insert into notifications(user_id, type, title, body, read, payload)
  select gm2.player_id, 'guild_event_announced', '📅 Tournoi interne planifié',
    coalesce(v_pseudo,'Le chef') || ' a planifié un tournoi interne — inscriptions ouvertes jusqu''au ' || to_char(p_registration_closes_at, 'DD/MM à HH24:MI') || '.',
    false, jsonb_build_object('event_id', eid)
  from guild_members gm2 where gm2.guild_id = gid;

  perform guild_journal_log(gid, 'guild_event_announced', uid, null, '📅 Tournoi interne planifié par ' || coalesce(v_pseudo,'le chef') || ' pour le ' || to_char(p_starts_at, 'DD/MM à HH24:MI') || '.');
  return jsonb_build_object('ok', true, 'event_id', eid);
end $$;
grant execute on function public.guild_event_create(int, timestamptz, timestamptz) to authenticated;

-- ── S'inscrire (tout membre de la guilde organisatrice) ────────────────
create or replace function public.guild_event_register(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; my_guild bigint; my_elo int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select guild_id into my_guild from guild_members where player_id = uid;
  if my_guild is distinct from ev.guild_a then return jsonb_build_object('ok', false, 'reason', 'not_in_guild'); end if;
  if ev.status <> 'scheduled' then return jsonb_build_object('ok', false, 'reason', 'registration_closed'); end if;
  if now() >= ev.registration_closes_at then return jsonb_build_object('ok', false, 'reason', 'registration_closed'); end if;
  select case when ev.cadence <= 3 then coalesce(elo_3s,1200) when ev.cadence >= 10 then coalesce(elo_10s,1200) else coalesce(elo_5s,1200) end
    into my_elo from profiles where id = uid;
  insert into guild_event_participants(event_id, player_id, elo) values (p_event_id, uid, my_elo)
    on conflict (event_id, player_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_register(bigint) to authenticated;

-- ── Se désinscrire (avant clôture) ──────────────────────────────────────
create or replace function public.guild_event_unregister(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if ev.status <> 'scheduled' then return jsonb_build_object('ok', false, 'reason', 'too_late'); end if;
  delete from guild_event_participants where event_id = p_event_id and player_id = uid;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_unregister(bigint) to authenticated;

-- ── Annuler (GM uniquement, avant le début) ─────────────────────────────
create or replace function public.guild_event_cancel(p_event_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); ev record; myrole text; v_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into ev from guild_events where id = p_event_id;
  if ev is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select role into myrole from guild_members where guild_id = ev.guild_a and player_id = uid;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if ev.status in ('running','finished','cancelled') then return jsonb_build_object('ok', false, 'reason', 'too_late'); end if;
  update guild_events set status = 'cancelled', cancelled_by = uid, updated_at = now() where id = p_event_id;
  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  perform guild_journal_log(ev.guild_a, 'guild_event_cancelled', uid, null, '🚫 Tournoi interne annulé par ' || coalesce(v_pseudo,'le chef') || '.');
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.guild_event_cancel(bigint) to authenticated;

-- ── Lecture : événements de ma guilde + mon statut d'inscription ───────
create or replace function public.guild_event_list_mine()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id into gid from guild_members where player_id = uid;
  if gid is null then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', ev.id, 'kind', ev.kind, 'status', ev.status, 'cadence', ev.cadence,
      'starts_at', ev.starts_at, 'registration_closes_at', ev.registration_closes_at,
      'created_by', ev.created_by,
      'registered_count', (select count(*) from guild_event_participants gep where gep.event_id = ev.id),
      'i_am_registered', exists(select 1 from guild_event_participants gep where gep.event_id = ev.id and gep.player_id = uid)
    ) order by ev.starts_at asc)
    from guild_events ev
    where ev.guild_a = gid and ev.status not in ('finished','cancelled')
  ), '[]'::jsonb);
end $$;
grant execute on function public.guild_event_list_mine() to authenticated;

-- ── Tick pg_cron : clôture des inscriptions à l'heure dite ──────────────
create or replace function public.guild_events_registration_tick()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare ev record; n int := 0;
begin
  for ev in select * from guild_events where status = 'scheduled' and now() >= registration_closes_at loop
    update guild_events set status = 'registration_closed', updated_at = now() where id = ev.id;
    insert into notifications(user_id, type, title, body, read, payload)
    select gep.player_id, 'guild_event_registration_closed', '⏳ Inscriptions closes',
      'Les inscriptions au tournoi interne sont closes (' || (select count(*) from guild_event_participants where event_id = ev.id) || ' inscrit(s)).',
      false, jsonb_build_object('event_id', ev.id)
    from guild_event_participants gep where gep.event_id = ev.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('closed', n);
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'guild_events_registration_tick') then
    perform cron.unschedule('guild_events_registration_tick');
  end if;
end $$;
select cron.schedule('guild_events_registration_tick', '20 seconds', $$select public.guild_events_registration_tick();$$);

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regclass('public.guild_events')::text as tbl_events,                        -- attendu non-null
  to_regclass('public.guild_event_participants')::text as tbl_participants,      -- attendu non-null
  to_regproc('public.guild_event_create')::text as fn_create,                    -- attendu non-null
  to_regproc('public.guild_event_register')::text as fn_register,                -- attendu non-null
  to_regproc('public.guild_event_unregister')::text as fn_unregister,            -- attendu non-null
  to_regproc('public.guild_event_cancel')::text as fn_cancel,                    -- attendu non-null
  to_regproc('public.guild_event_list_mine')::text as fn_list,                   -- attendu non-null
  to_regproc('public.guild_events_registration_tick')::text as fn_tick,          -- attendu non-null
  (select count(*) from cron.job where jobname = 'guild_events_registration_tick') as cron_scheduled, -- attendu 1
  'guild_events_g2 OK' as status;
