-- ══════════════════════════════════════════════════════════════════
-- CHAMP DE BATAILLE — lobby d'équipe + matchmaking ELO cumulé (Passe 2b, lot ②③)
-- cf. docs/CHAMP_DE_BATAILLE_ONLINE.md
--
-- Additif et idempotent : rejouable sans risque. Ne touche PAS online_games,
-- ni challenges (chemin critique) : les invitations de siège ont leur PROPRE
-- table. Dépend de battlefield_online.sql (table battlefield_games + RPC
-- battlefield_bot_fill) — à exécuter AVANT ou dans la même passe.
--
-- Décisions (2026-08-08) : partie AMICALE (l'ELO cumulé sert UNIQUEMENT au
-- matchmaking, jamais modifié), déconnexion/timeout d'un siège = forfait, les
-- 3 voies pour un slot ouvert (salon d'équipes ouvertes + file solo + code).
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Équipe (le lobby de préparation) ───────────────────────────
-- slots = 3 objets ordonnés (index 0,1,2 → combattants 1,2,3) :
--   { "slot":0, "state":"human|bot|open|empty",
--     "player_id":"<uuid|null>", "is_bot":false, "bot_key":null,
--     "name":"Wurmz", "elo":1200 }
-- Le chef occupe le slot 0 (state human). leader_id porte le contrôle.
create table if not exists battlefield_teams (
  id             uuid primary key default gen_random_uuid(),
  leader_id      uuid not null,
  name           text not null default 'Escouade',
  status         text not null default 'forming',   -- forming | queued | matched | closed
  slots          jsonb not null,                     -- 3 sièges (voir ci-dessus)
  elo_sum        int  not null default 0,            -- somme des ELO des 3 slots (matchmaking)
  invite_code    text unique,                        -- code court partageable (voie « lien »)
  open_to_random boolean not null default false,     -- apparaît dans le salon / accepte la file solo
  timer_seconds  int  not null default 5,
  game_id        uuid,                               -- battlefield_games une fois apparié
  color          text,                               -- white | black (affecté à l'appariement)
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists battlefield_teams_status_idx on battlefield_teams(status);
create index if not exists battlefield_teams_code_idx   on battlefield_teams(invite_code);

-- ── 2. File solo « je cherche une équipe » ────────────────────────
create table if not exists battlefield_solo_queue (
  player_id  uuid primary key,
  name       text,
  elo        int not null default 1200,
  created_at timestamptz not null default now()
);

-- ── 3. Invitations de siège (table DÉDIÉE — pas challenges) ────────
create table if not exists battlefield_invites (
  id         uuid primary key default gen_random_uuid(),
  team_id    uuid not null,
  slot       int  not null,
  from_id    uuid not null,
  to_id      uuid not null,
  status     text not null default 'pending',        -- pending | accepted | declined | expired
  created_at timestamptz not null default now()
);
create index if not exists battlefield_invites_to_idx on battlefield_invites(to_id, status);

-- ── 4. updated_at automatique sur les équipes ─────────────────────
-- Réutilise la fonction trigger de battlefield_online.sql si présente, sinon
-- la crée (idempotent : même corps).
create or replace function battlefield_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists battlefield_teams_touch on battlefield_teams;
create trigger battlefield_teams_touch before update on battlefield_teams
  for each row execute function battlefield_touch_updated_at();

-- ── 5. RLS ────────────────────────────────────────────────────────
alter table battlefield_teams      enable row level security;
alter table battlefield_solo_queue enable row level security;
alter table battlefield_invites    enable row level security;

-- Équipes : lecture ouverte (salon + spectateur). Écriture réservée au chef.
drop policy if exists battlefield_teams_read   on battlefield_teams;
create policy battlefield_teams_read   on battlefield_teams for select using (true);
drop policy if exists battlefield_teams_insert on battlefield_teams;
create policy battlefield_teams_insert on battlefield_teams for insert with check (leader_id = auth.uid());
drop policy if exists battlefield_teams_update on battlefield_teams;
create policy battlefield_teams_update on battlefield_teams for update using (leader_id = auth.uid());
-- NB : rejoindre un slot ouvert / matchmaking passent par des RPC SECURITY
-- DEFINER (ci-dessous) — un non-chef n'écrit JAMAIS la ligne en direct.

-- File solo : chacun gère sa propre ligne.
drop policy if exists battlefield_solo_read   on battlefield_solo_queue;
create policy battlefield_solo_read   on battlefield_solo_queue for select using (true);
drop policy if exists battlefield_solo_insert on battlefield_solo_queue;
create policy battlefield_solo_insert on battlefield_solo_queue for insert with check (player_id = auth.uid());
drop policy if exists battlefield_solo_delete on battlefield_solo_queue;
create policy battlefield_solo_delete on battlefield_solo_queue for delete using (player_id = auth.uid());

-- Invitations : émetteur et destinataire voient ; l'émetteur (chef) crée ;
-- les deux peuvent mettre à jour le statut.
drop policy if exists battlefield_inv_read   on battlefield_invites;
create policy battlefield_inv_read   on battlefield_invites for select using (from_id = auth.uid() or to_id = auth.uid());
drop policy if exists battlefield_inv_insert on battlefield_invites;
create policy battlefield_inv_insert on battlefield_invites for insert with check (from_id = auth.uid());
drop policy if exists battlefield_inv_update on battlefield_invites;
create policy battlefield_inv_update on battlefield_invites for update using (from_id = auth.uid() or to_id = auth.uid());

-- ── 6. Realtime ───────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='battlefield_teams') then
    execute 'alter publication supabase_realtime add table battlefield_teams';
  end if;
  if not exists (select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='battlefield_invites') then
    execute 'alter publication supabase_realtime add table battlefield_invites';
  end if;
end $$;

-- ── 7. Helper : ELO cumulé d'un jeu de slots ──────────────────────
create or replace function battlefield_slots_elo(p_slots jsonb)
returns int language sql immutable as $$
  select coalesce(sum((s->>'elo')::int), 0)::int
  from jsonb_array_elements(p_slots) s
  where s->>'state' in ('human','bot');
$$;

-- ── 8. RPC : rejoindre un slot ouvert (salon / code) ──────────────
-- Claim ATOMIQUE : le slot doit être 'open'. Place le joueur, recalcule
-- l'ELO cumulé. SECURITY DEFINER pour écrire une équipe dont on n'est pas chef.
drop function if exists battlefield_join_open_slot(uuid, int);
create or replace function battlefield_join_open_slot(p_team_id uuid, p_slot int)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid := auth.uid();
  t battlefield_teams;
  my_elo int;
  my_name text;
  new_slots jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into t from battlefield_teams where id=p_team_id for update;
  if not found then raise exception 'team not found'; end if;
  if t.status <> 'forming' then raise exception 'team not forming'; end if;
  if (t.slots->p_slot->>'state') <> 'open' then raise exception 'slot not open'; end if;
  -- Un même joueur ne peut pas occuper deux slots de la même équipe.
  if exists (select 1 from jsonb_array_elements(t.slots) s where (s->>'player_id')=uid::text) then
    raise exception 'already seated in this team';
  end if;
  select coalesce(elo_5s,1200), pseudo into my_elo, my_name from profiles where id=uid;
  new_slots := jsonb_set(t.slots, array[p_slot::text], jsonb_build_object(
      'slot', p_slot, 'state','human', 'player_id', uid, 'is_bot', false,
      'bot_key', null, 'name', coalesce(my_name,'Joueur'), 'elo', coalesce(my_elo,1200)));
  update battlefield_teams
     set slots=new_slots, elo_sum=battlefield_slots_elo(new_slots)
   where id=p_team_id;
  select * into t from battlefield_teams where id=p_team_id;
  return to_jsonb(t);
end $$;

-- ── 9. RPC : accepter une invitation de siège ─────────────────────
drop function if exists battlefield_accept_invite(uuid);
create or replace function battlefield_accept_invite(p_invite_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid := auth.uid();
  inv battlefield_invites;
  t battlefield_teams;
  my_elo int; my_name text; new_slots jsonb; st text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into inv from battlefield_invites where id=p_invite_id for update;
  if not found then raise exception 'invite not found'; end if;
  if inv.to_id <> uid then raise exception 'not your invite'; end if;
  if inv.status <> 'pending' then raise exception 'invite not pending'; end if;
  select * into t from battlefield_teams where id=inv.team_id for update;
  if not found or t.status <> 'forming' then raise exception 'team unavailable'; end if;
  st := t.slots->inv.slot->>'state';
  if st not in ('open','empty') then raise exception 'slot taken'; end if;
  if exists (select 1 from jsonb_array_elements(t.slots) s where (s->>'player_id')=uid::text) then
    raise exception 'already seated in this team';
  end if;
  select coalesce(elo_5s,1200), pseudo into my_elo, my_name from profiles where id=uid;
  new_slots := jsonb_set(t.slots, array[inv.slot::text], jsonb_build_object(
      'slot', inv.slot, 'state','human', 'player_id', uid, 'is_bot', false,
      'bot_key', null, 'name', coalesce(my_name,'Joueur'), 'elo', coalesce(my_elo,1200)));
  update battlefield_teams set slots=new_slots, elo_sum=battlefield_slots_elo(new_slots)
   where id=t.id;
  update battlefield_invites set status='accepted' where id=p_invite_id;
  select * into t from battlefield_teams where id=t.id;
  return to_jsonb(t);
end $$;

-- ── 10. RPC : matchmaking par ELO cumulé ──────────────────────────
-- Le chef appelle avec le FORMAT (rendu client) et la cadence. On met SON
-- équipe en file 'queued', on cherche l'adversaire 'queued' d'ELO cumulé le
-- plus proche (verrou SKIP LOCKED anti-course), on crée la partie
-- battlefield_games avec les 6 sièges interleavés W1,B1,W2,B2,W3,B3.
--   • Le caller = équipe A = BLANC. Il reçoit game_id et écrit le plateau
--     initial (game_state) côté client (comme createOnlineGame).
--   • L'adversaire = équipe B = NOIR, découvre game_id par realtime sur sa ligne.
-- Renvoie {game_id, color} si apparié, sinon {game_id:null} (rester en file).
drop function if exists battlefield_matchmake(uuid, jsonb, int);
create or replace function battlefield_matchmake(p_team_id uuid, p_format jsonb, p_timer int)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid := auth.uid();
  me battlefield_teams;
  opp battlefield_teams;
  full_count int;
  seats jsonb := '[]'::jsonb;
  gid uuid;
  u int;
  ws jsonb; bs jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into me from battlefield_teams where id=p_team_id and leader_id=uid for update;
  if not found then raise exception 'not team leader'; end if;
  -- Équipe complète = 3 slots human/bot.
  select count(*) into full_count from jsonb_array_elements(me.slots) s where s->>'state' in ('human','bot');
  if full_count <> 3 then raise exception 'team not full'; end if;
  update battlefield_teams set status='queued' where id=p_team_id;

  select * into opp from battlefield_teams
    where status='queued' and id <> p_team_id and game_id is null
      and (select count(*) from jsonb_array_elements(slots) s where s->>'state' in ('human','bot'))=3
    order by abs(elo_sum - me.elo_sum), created_at
    limit 1
    for update skip locked;
  if not found then
    return jsonb_build_object('game_id', null);  -- rester en file, le client repollera
  end if;

  -- Sièges interleavés : moi=blanc (A), opp=noir (B).
  for u in 0..2 loop
    ws := me.slots->u;  bs := opp.slots->u;
    seats := seats || jsonb_build_array(
      jsonb_build_object('seat',u*2,   'color','white','unit',u+1,
        'player_id', ws->'player_id', 'is_bot', coalesce((ws->>'is_bot')::boolean,false),
        'bot_key', ws->'bot_key', 'name', ws->>'name', 'eliminated', false),
      jsonb_build_object('seat',u*2+1, 'color','black','unit',u+1,
        'player_id', bs->'player_id', 'is_bot', coalesce((bs->>'is_bot')::boolean,false),
        'bot_key', bs->'bot_key', 'name', bs->>'name', 'eliminated', false));
  end loop;

  insert into battlefield_games(status, format, game_state, seats, seat_idx, turn,
                                timer_seconds, team_a_elo, team_b_elo)
  values ('active', p_format, '{}'::jsonb, seats, 0, 'white',
          coalesce(p_timer,5), me.elo_sum, opp.elo_sum)
  returning id into gid;

  update battlefield_teams set status='matched', game_id=gid, color='white' where id=me.id;
  update battlefield_teams set status='matched', game_id=gid, color='black' where id=opp.id;
  return jsonb_build_object('game_id', gid, 'color', 'white');
end $$;

-- ── 11. RPC : placer la file solo dans les slots ouverts (worker) ──
-- Le worker appelle en boucle : pour chaque joueur de la file, trouver une
-- équipe 'forming' + open_to_random avec un slot 'open' d'ELO cumulé compatible,
-- l'y glisser. SECURITY DEFINER (écrit des équipes tierces). Renvoie le nombre placé.
drop function if exists battlefield_solo_place();
create or replace function battlefield_solo_place()
returns int language plpgsql security definer set search_path=public as $$
declare
  q battlefield_solo_queue;
  t battlefield_teams;
  slot_idx int;
  new_slots jsonb;
  placed int := 0;
begin
  for q in select * from battlefield_solo_queue order by created_at loop
    select * into t from battlefield_teams
      where status='forming' and open_to_random=true
        and exists (select 1 from jsonb_array_elements(slots) s where s->>'state'='open')
        and not exists (select 1 from jsonb_array_elements(slots) s where (s->>'player_id')=q.player_id::text)
      order by abs(elo_sum - q.elo)
      limit 1 for update skip locked;
    if found then
      select (s->>'slot')::int into slot_idx
        from jsonb_array_elements(t.slots) s where s->>'state'='open' order by (s->>'slot')::int limit 1;
      new_slots := jsonb_set(t.slots, array[slot_idx::text], jsonb_build_object(
          'slot', slot_idx, 'state','human', 'player_id', q.player_id, 'is_bot', false,
          'bot_key', null, 'name', coalesce(q.name,'Joueur'), 'elo', q.elo));
      update battlefield_teams set slots=new_slots, elo_sum=battlefield_slots_elo(new_slots) where id=t.id;
      delete from battlefield_solo_queue where player_id=q.player_id;
      placed := placed + 1;
    end if;
  end loop;
  return placed;
end $$;

-- ── Contrôle ──────────────────────────────────────────────────────
select
  to_regclass('public.battlefield_teams')::text       as t_teams,
  to_regclass('public.battlefield_solo_queue')::text  as t_solo,
  to_regclass('public.battlefield_invites')::text     as t_invites,
  to_regproc('public.battlefield_join_open_slot')::text as fn_join,
  to_regproc('public.battlefield_accept_invite')::text  as fn_accept,
  to_regproc('public.battlefield_matchmake')::text      as fn_match,
  to_regproc('public.battlefield_solo_place')::text     as fn_solo,
  (select count(*) from pg_policies where tablename in
     ('battlefield_teams','battlefield_solo_queue','battlefield_invites')) as nb_policies;  -- 10
