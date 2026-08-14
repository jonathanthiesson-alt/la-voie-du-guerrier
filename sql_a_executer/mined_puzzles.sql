-- ═══════════════════════════════════════════════════════════════════════
--  DÉFIS MINÉS — banque de puzzles extraits de vraies parties jouées
--  À RELIRE ET EXÉCUTER par Jonathan (éditeur SQL Supabase). Additif :
--  ne touche à aucune donnée de jeu existante.
--
--  Alimentée par scripts/mine-puzzles.mjs (offline, via service_role) :
--  ce script rejoue les parties décisives de game_history, cherche des
--  séquences de mat FORCÉ (2 ou 3 coups du camp gagnant, quelle que soit
--  la réplique adverse — recherche ET/OU, pas un simple coup gagnant
--  ponctuel) et insère chaque trouvaille ici au format « leçon » (le même
--  format que les leçons de campagne écrites à la main), pour être
--  directement jouable par le lecteur de leçon existant sans y toucher.
--
--  Lecture publique (authenticated) : ce sont des positions de jeu
--  publiques, pas des données personnelles. Écriture réservée au
--  service_role (le script d'extraction), jamais au client.
-- ═══════════════════════════════════════════════════════════════════════

create table if not exists public.mined_puzzles (
  id bigint generated always as identity primary key,
  lesson jsonb not null,              -- {setup, steps, briefing, num, title}
  mate_depth int not null,            -- 2 ou 3 (coups du camp gagnant)
  difficulty int not null default 3,  -- 1..5, même échelle que getPuzzlePool()
  source_game_id uuid,
  created_at timestamptz not null default now()
);

alter table public.mined_puzzles enable row level security;

drop policy if exists mined_puzzles_select on public.mined_puzzles;
create policy mined_puzzles_select on public.mined_puzzles
  for select to authenticated using (true);

-- Aucune policy insert/update/delete pour authenticated/anon : seul le
-- service_role (le script offline) peut écrire, en contournant la RLS.

-- Contrôle -------------------------------------------------------------------
-- select count(*), mate_depth from mined_puzzles group by mate_depth;
