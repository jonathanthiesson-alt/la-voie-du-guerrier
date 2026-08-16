-- ════════════════════════════════════════════════════════════════════════
-- PUZZLES CORE — socle du mode Puzzle (Dojo > Créer)
-- docs/ROADMAP_PUZZLE_INVASION.md — lots P0 à P6, décisions A/F/G/H/N/T/U
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ Ne pas confondre avec `mined_puzzles` (existant) : ce sont des mats
-- forcés extraits automatiquement de vraies parties pour le lecteur de
-- leçon de la Campagne — un système entièrement différent, non touché ici.
-- `puzzles` = créations DE JOUEURS, publiées et jouées par d'autres joueurs.
--
-- Le descripteur `format` reprend EXACTEMENT la sortie de
-- labEdCurrentFormat() ({rows,cols,voids,pieces,setup,...}) + un champ `v`
-- de version (risque § 6 de la roadmap : un puzzle publié doit rester
-- solvable si le moteur évolue).
-- ════════════════════════════════════════════════════════════════════════

-- ── Colonnes joueur : monnaie puzzle + slots de publication ────────────
-- Nom de colonne provisoire (placeholder) — le nom d'affichage définitif de
-- cette monnaie est une décision Wurmz/Thomas à figer avant la sortie
-- publique (même règle que « Monban » : nommage fr/en/ja dès le 1er commit
-- côté UI, pas côté colonne SQL qui elle ne change jamais après coup).
alter table public.profiles add column if not exists puzzle_coin_balance integer not null default 0;
alter table public.profiles add column if not exists puzzle_slots integer not null default 1;

-- ── Table principale ─────────────────────────────────────────────────────
create table if not exists public.puzzles (
  id                uuid primary key default gen_random_uuid(),
  creator_id        uuid not null references public.profiles(id) on delete cascade,
  title             text not null,
  format            jsonb not null,              -- {v:1, rows,cols,voids,pieces,setup} — labEdCurrentFormat()
  objective         jsonb not null,               -- {type:'survive_turns'|'reach_cell'|'eliminate', ...}
  ai                jsonb not null,               -- config déterministe (décision A) : {depth:int, luck:0}
  timer_seconds     integer not null default 0,   -- cadence du puzzle, 0 = illimité
  solution          jsonb,                        -- séquence gagnante prouvée par le créateur (mode Tester)
  published         boolean not null default false, -- slot consommé UNIQUEMENT si published=true (décision N)
  status            text not null default 'active', -- 'active' | 'hidden' (décision H, dépublication admin)
  rating            numeric not null default 1200,   -- Elo du puzzle (décision F, façon Glicko simplifié)
  rating_deviation  numeric not null default 350,    -- incertitude, se resserre avec les tentatives
  play_count        integer not null default 0,      -- dénormalisé pour l'affichage liste (décision T)
  success_count     integer not null default 0,
  fail_count        integer not null default 0,
  star_sum          integer not null default 0,      -- moyenne = star_sum::numeric/star_count (décision U)
  star_count        integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists puzzles_creator_idx on public.puzzles(creator_id);
create index if not exists puzzles_published_idx on public.puzzles(published, status) where published = true;

-- ── Tentatives (une ligne par essai, succès ou échec) ───────────────────
-- Table étroite volontairement (risque § 6 : volume) — alimente à la fois
-- l'Elo du puzzle et les stats publiques, un seul pipeline (§ 3 roadmap).
create table if not exists public.puzzle_attempts (
  id             bigint generated always as identity primary key,
  puzzle_id      uuid not null references public.puzzles(id) on delete cascade,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  success        boolean not null,
  elo_at_attempt integer,             -- Elo du joueur (cadence du puzzle) au moment de l'essai
  created_at     timestamptz not null default now()
);
create index if not exists puzzle_attempts_puzzle_idx on public.puzzle_attempts(puzzle_id);

-- ── Achèvements (1 ligne par joueur unique) ─────────────────────────────
-- La clé primaire composite EST la garde anti-farm (décision G) : un joueur
-- ne peut avoir qu'UNE ligne par puzzle, donc qu'UN gain de monnaie.
create table if not exists public.puzzle_completions (
  puzzle_id       uuid not null references public.puzzles(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  completed_at    timestamptz not null default now(),
  stars           integer,                          -- 1..5, note optionnelle (décision U)
  reward_claimed  boolean not null default false,
  primary key (puzzle_id, user_id)
);

-- ── Plafond quotidien de gains par créateur (décision G) ────────────────
create table if not exists public.puzzle_creator_daily (
  creator_id  uuid not null references public.profiles(id) on delete cascade,
  day         date not null default current_date,
  earned      integer not null default 0,
  primary key (creator_id, day)
);

-- ── Signalements (décision H, modération obligatoire dès le départ) ────
create table if not exists public.puzzle_reports (
  id           bigint generated always as identity primary key,
  puzzle_id    uuid not null references public.puzzles(id) on delete cascade,
  reporter_id  uuid not null references public.profiles(id) on delete cascade,
  reason       text,
  created_at   timestamptz not null default now(),
  resolved     boolean not null default false
);

-- ── RLS ──────────────────────────────────────────────────────────────────
alter table public.puzzles enable row level security;
alter table public.puzzle_attempts enable row level security;
alter table public.puzzle_completions enable row level security;
alter table public.puzzle_creator_daily enable row level security;
alter table public.puzzle_reports enable row level security;

drop policy if exists puzzles_select on public.puzzles;
create policy puzzles_select on public.puzzles
  for select using (
    (published = true and status = 'active') or creator_id = auth.uid() or is_admin_user()
  );

drop policy if exists puzzle_attempts_select_own on public.puzzle_attempts;
create policy puzzle_attempts_select_own on public.puzzle_attempts
  for select using (user_id = auth.uid());

drop policy if exists puzzle_completions_select_own on public.puzzle_completions;
create policy puzzle_completions_select_own on public.puzzle_completions
  for select using (user_id = auth.uid());

-- Pas de policy insert/update/delete pour authenticated sur aucune de ces
-- tables : toute écriture passe par les RPC SECURITY DEFINER ci-dessous
-- (Elo, monnaie, anti-farm, modération — trop d'invariants pour un insert
-- client direct, même pattern que unlock_skin_pack/spend_koku).

-- ── RPC : créer / mettre à jour un brouillon ─────────────────────────────
create or replace function public.puzzle_upsert(
  p_id uuid, p_title text, p_format jsonb, p_objective jsonb, p_ai jsonb, p_timer integer
) returns public.puzzles
language plpgsql security definer set search_path to 'public' as $$
declare r public.puzzles;
begin
  if p_title is null or length(trim(p_title)) = 0 then raise exception 'Titre requis'; end if;
  if p_id is null then
    insert into puzzles (creator_id, title, format, objective, ai, timer_seconds)
      values (auth.uid(), trim(p_title), p_format, p_objective, p_ai, coalesce(p_timer,0))
      returning * into r;
  else
    update puzzles set title = trim(p_title), format = p_format, objective = p_objective,
      ai = p_ai, timer_seconds = coalesce(p_timer,0), updated_at = now()
      where id = p_id and creator_id = auth.uid() and published = false
      returning * into r;
    if r.id is null then raise exception 'Puzzle introuvable, non éditable (publié ?), ou non autorisé'; end if;
  end if;
  return r;
end; $$;

-- ── RPC : enregistrer la preuve de réussite en mode Tester (décision A) ─
create or replace function public.puzzle_set_solution(p_id uuid, p_solution jsonb)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update puzzles set solution = p_solution, updated_at = now()
    where id = p_id and creator_id = auth.uid();
  if not found then raise exception 'Puzzle introuvable ou non autorisé'; end if;
end; $$;

-- ── RPC : publier ─────────────────────────────────────────────────────
-- Garde-fous : (1) le créateur doit avoir réussi son propre puzzle
-- (solution non nulle, décision A) ; (2) slot disponible (décision N —
-- published=true consomme un slot, dépublier en libère un).
create or replace function public.puzzle_publish(p_id uuid)
returns public.puzzles language plpgsql security definer set search_path to 'public' as $$
declare r public.puzzles; used integer; slots integer;
begin
  select * into r from puzzles where id = p_id and creator_id = auth.uid();
  if r.id is null then raise exception 'Puzzle introuvable ou non autorisé'; end if;
  if r.solution is null then raise exception 'Réussis d''abord ton puzzle en mode Tester avant de le publier'; end if;
  if r.published then return r; end if;
  select count(*) into used from puzzles where creator_id = auth.uid() and published = true;
  select puzzle_slots into slots from profiles where id = auth.uid();
  if used >= coalesce(slots,1) then raise exception 'Aucun slot de publication disponible'; end if;
  update puzzles set published = true, status = 'active', updated_at = now()
    where id = p_id returning * into r;
  return r;
end; $$;

create or replace function public.puzzle_unpublish(p_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update puzzles set published = false, updated_at = now()
    where id = p_id and creator_id = auth.uid();
  if not found then raise exception 'Puzzle introuvable ou non autorisé'; end if;
end; $$;

-- ── RPC : enregistrer une tentative (jouée par un AUTRE joueur) ─────────
-- Un seul point d'entrée qui fait tout atomiquement : historise l'essai,
-- met à jour les compteurs publics, ajuste l'Elo du puzzle (décision F,
-- moyenne mobile simple en V1), et au PREMIER succès crédite le créateur
-- (décision G, plafonné) via puzzle_creator_daily.
create or replace function public.puzzle_record_attempt(p_id uuid, p_success boolean, p_player_elo integer)
returns public.puzzles language plpgsql security definer set search_path to 'public' as $$
declare
  r public.puzzles;
  already_completed boolean;
  daily_cap constant integer := 5;   -- plafond de gains/jour par créateur — à recalibrer après mesure réelle
  reward constant integer := 1;
begin
  select * into r from puzzles where id = p_id and published = true and status = 'active';
  if r.id is null then raise exception 'Puzzle introuvable ou indisponible'; end if;

  insert into puzzle_attempts (puzzle_id, user_id, success, elo_at_attempt)
    values (p_id, auth.uid(), p_success, p_player_elo);

  update puzzles set
    play_count = play_count + 1,
    success_count = success_count + (case when p_success then 1 else 0 end),
    fail_count = fail_count + (case when p_success then 0 else 1 end),
    -- V1 minimale (décision F) : glisse l'Elo du puzzle vers l'Elo du
    -- joueur qui vient de le résoudre/échouer, pondéré par l'incertitude
    -- qui se resserre à chaque tentative (façon Glicko simplifiée).
    rating = rating + (coalesce(p_player_elo,1200) - rating) * (rating_deviation / (rating_deviation + 400)) * (case when p_success then 0.5 else -0.5 end),
    rating_deviation = greatest(60, rating_deviation * 0.97),
    updated_at = now()
    where id = p_id;

  if p_success then
    select exists(select 1 from puzzle_completions where puzzle_id = p_id and user_id = auth.uid()) into already_completed;
    if not already_completed then
      insert into puzzle_completions (puzzle_id, user_id, reward_claimed) values (p_id, auth.uid(), false);
      insert into puzzle_creator_daily (creator_id, day, earned) values (r.creator_id, current_date, 0)
        on conflict (creator_id, day) do nothing;
      update puzzle_creator_daily set earned = earned + reward
        where creator_id = r.creator_id and day = current_date and earned < daily_cap;
      if found then
        update profiles set puzzle_coin_balance = puzzle_coin_balance + reward where id = r.creator_id;
        update puzzle_completions set reward_claimed = true where puzzle_id = p_id and user_id = auth.uid();
      end if;
    end if;
  end if;

  select * into r from puzzles where id = p_id;
  return r;
end; $$;

-- ── RPC : noter (décision U — réservé à ceux qui ont RÉUSSI) ────────────
create or replace function public.puzzle_rate(p_id uuid, p_stars integer)
returns void language plpgsql security definer set search_path to 'public' as $$
declare prev integer;
begin
  if p_stars < 1 or p_stars > 5 then raise exception 'Note invalide (1 à 5)'; end if;
  select stars into prev from puzzle_completions where puzzle_id = p_id and user_id = auth.uid();
  if prev is null then raise exception 'Réussis ce puzzle avant de le noter'; end if;
  update puzzle_completions set stars = p_stars where puzzle_id = p_id and user_id = auth.uid();
  update puzzles set
    star_sum = star_sum - coalesce(prev,0) + p_stars,
    star_count = star_count + (case when prev is null then 1 else 0 end)
    where id = p_id;
end; $$;

-- ── RPC : signaler (décision H) ─────────────────────────────────────────
create or replace function public.puzzle_report(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  insert into puzzle_reports (puzzle_id, reporter_id, reason) values (p_id, auth.uid(), p_reason);
end; $$;

-- ── RPC admin : dépublier suite à signalement (décision H) ──────────────
create or replace function public.puzzle_admin_hide(p_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not is_admin_user() then raise exception 'admin only'; end if;
  update puzzles set status = 'hidden', updated_at = now() where id = p_id;
  update puzzle_reports set resolved = true where puzzle_id = p_id;
end; $$;

-- Contrôle de fin de script.
select 'puzzles_core OK' as status;
