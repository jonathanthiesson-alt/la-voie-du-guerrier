-- ══════════════════════════════════════════════════════════════════
-- CHAMP DE BATAILLE — online 6 sièges (Passe 2b, lot ①)
-- cf. docs/CHAMP_DE_BATAILLE_ONLINE.md
--
-- Additif et idempotent : rejouable sans risque, ne touche PAS online_games
-- ni le 1v1. Décisions : partie AMICALE (aucun ELO persistant), déconnexion/
-- timeout d'un siège = forfait du combattant (élimination), cadences activées
-- (turn_deadline imposé par le WORKER, pas par du SQL — pas de manipulation de
-- plateau en plpgsql).
--
-- ⚠ Un mode 3v3 = 6 propriétaires + rotation par siège : impossible sur
-- online_games (2 joueurs en dur). D'où une table dédiée.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Table de partie ────────────────────────────────────────────
create table if not exists battlefield_games (
  id            uuid primary key default gen_random_uuid(),
  status        text not null default 'active',      -- active | finished
  format        jsonb not null,                      -- format champDeBataille (rendu client)
  game_state    jsonb not null,                      -- {board,stacks,lastMoved,lastMovedByColor,eliminatedUnits}
  seats         jsonb not null,                      -- 6 sièges, ordre de rotation (voir doc)
  seat_idx      int  not null default 0,             -- siège actif (index dans seats, 0..5)
  turn          text not null default 'white',       -- couleur du siège actif (parité client)
  timer_seconds int  not null default 5,
  turn_deadline timestamptz,                         -- échéance du siège actif (timeout=forfait, imposé worker)
  team_a_elo    int,                                 -- blanc = équipe A
  team_b_elo    int,                                 -- noir  = équipe B
  winner        text,                                -- white | black | null
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Rattrapage idempotent si une version antérieure a créé la table autrement.
alter table battlefield_games add column if not exists format        jsonb;
alter table battlefield_games add column if not exists seats         jsonb;
alter table battlefield_games add column if not exists seat_idx      int  not null default 0;
alter table battlefield_games add column if not exists turn_deadline timestamptz;
alter table battlefield_games add column if not exists team_a_elo    int;
alter table battlefield_games add column if not exists team_b_elo    int;

create index if not exists battlefield_games_status_idx on battlefield_games(status);

-- ── 2. updated_at automatique ─────────────────────────────────────
create or replace function battlefield_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists battlefield_games_touch on battlefield_games;
create trigger battlefield_games_touch before update on battlefield_games
  for each row execute function battlefield_touch_updated_at();

-- ── 3. RLS (calquée sur online_games) ─────────────────────────────
alter table battlefield_games enable row level security;

-- SELECT ouvert : permet le spectateur, comme og_read sur online_games.
drop policy if exists battlefield_read on battlefield_games;
create policy battlefield_read on battlefield_games for select using (true);

-- INSERT : le créateur doit être un siège HUMAIN de la partie qu'il crée.
-- (Le service_role du worker passe outre la RLS pour les parties bot-only.)
drop policy if exists battlefield_insert on battlefield_games;
create policy battlefield_insert on battlefield_games for insert with check (
  exists (
    select 1 from jsonb_array_elements(seats) s
    where (s->>'player_id')::uuid = auth.uid()
      and coalesce((s->>'is_bot')::boolean, false) = false
  )
);

-- UPDATE : tout participant humain peut pousser l'état (modèle de confiance
-- identique au 1v1 amical). Le worker (service_role) pilote bots + timeouts.
drop policy if exists battlefield_update on battlefield_games;
create policy battlefield_update on battlefield_games for update using (
  exists (
    select 1 from jsonb_array_elements(seats) s
    where (s->>'player_id')::uuid = auth.uid()
      and coalesce((s->>'is_bot')::boolean, false) = false
  )
);

-- ── 4. Realtime (comme online_games) ──────────────────────────────
-- add table échoue si déjà présent → on garde l'opération conditionnelle.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='battlefield_games'
  ) then
    execute 'alter publication supabase_realtime add table battlefield_games';
  end if;
end $$;

-- ── 5. RPC : bots pour remplir les sièges vides ───────────────────
-- Renvoie jusqu'à p_count bots PROVISIONNÉS (profile_id non null), d'ELO proche
-- de p_elo, hors Rōnin caché (tier<>'hidden'). Le client s'en sert pour peupler
-- les sièges bots d'une équipe. SECURITY DEFINER (lecture bot_roster).
drop function if exists battlefield_bot_fill(int, int);
create or replace function battlefield_bot_fill(p_elo int, p_count int)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); res jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into res from (
    select jsonb_build_object(
             'profile_id', r.profile_id,
             'name',       r.pseudo,
             'elo',        r.base_elo,
             'bot_key',    r.key
           ) as x
    from bot_roster r
    where r.profile_id is not null
      and r.tier <> 'hidden'
    order by abs(r.base_elo - coalesce(p_elo,1200)), random()
    limit greatest(coalesce(p_count,0), 0)
  ) q;
  return res;
end $$;

-- ── Contrôle ──────────────────────────────────────────────────────
select
  to_regclass('public.battlefield_games')::text                        as tbl,
  (select count(*) from pg_policies where tablename='battlefield_games') as nb_policies,          -- 3
  (select count(*) from pg_publication_tables
     where pubname='supabase_realtime' and tablename='battlefield_games') as realtime_on,          -- 1
  to_regproc('public.battlefield_bot_fill')::text                       as fn_bot_fill,
  (select count(*) from pg_trigger where tgname='battlefield_games_touch') as trg_updated_at;      -- 1
