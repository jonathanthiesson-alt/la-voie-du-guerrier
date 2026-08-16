-- ════════════════════════════════════════════════════════════════════════
-- MONBAN CORE — socle du mode Invasion (Dojo > Défendre)
-- docs/ROADMAP_PUZZLE_INVASION.md — lots I0 à I1 (le pilotage serveur I2+
-- reste à construire dans scripts/bot-army.mjs, PAS dans ce script)
-- ════════════════════════════════════════════════════════════════════════
-- Monban (門番) : IA gardienne qui défend le dojo du joueur en son absence,
-- clone de sa façon de jouer. Décisions figées : Elo DÉRIVÉ du joueur (pas
-- un Elo propre) ; apprend de TOUTES ses parties en ligne, pas seulement de
-- l'entraînement quotidien ; l'EXÉCUTION (qui joue les coups, qui arbitre
-- le résultat d'une invasion) tourne sur le serveur — ce script ne pose que
-- les tables, PAS le pilotage (qui vit dans le worker bot-army, lot I2).
-- ════════════════════════════════════════════════════════════════════════

-- ── Colonnes joueur : bouclier + limite d'attaque (décision C) ─────────
alter table public.profiles add column if not exists shield_until timestamptz;
alter table public.profiles add column if not exists last_invasion_at timestamptz;

-- ── Profil Monban : un par joueur, mis à jour à CHAQUE partie en ligne ──
-- Format compact volontairement (risque § 6 : volume) — même esprit que
-- NT2_PROFILE (index.html), mais tenu côté serveur pour être lisible par
-- le worker quand il pilote une défense hors ligne.
create table if not exists public.monban_profiles (
  user_id          uuid primary key references public.profiles(id) on delete cascade,
  profile          jsonb not null default '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb,
  games_learned    integer not null default 0,
  last_trained_at  timestamptz,
  updated_at       timestamptz not null default now()
);

-- ── Stats affichables (décision : « consulter Monban, son Elo, ses stats ») ─
-- L'Elo affiché n'est PAS stocké ici : il est DÉRIVÉ de profiles.elo_Xs à la
-- lecture (décision M) — seules les stats de combat propres à Monban vivent
-- dans cette table.
create table if not exists public.monban_stats (
  user_id        uuid primary key references public.profiles(id) on delete cascade,
  defends_won    integer not null default 0,
  defends_lost   integer not null default 0,
  updated_at     timestamptz not null default now()
);

-- ── Historique d'invasions (anti-harcèlement 72h, décision W) ───────────
create table if not exists public.invasion_history (
  id           bigint generated always as identity primary key,
  attacker_id  uuid not null references public.profiles(id) on delete cascade,
  defender_id  uuid not null references public.profiles(id) on delete cascade,
  winner_id    uuid references public.profiles(id),
  currency     text,               -- monnaie volée (jamais 'koku', décision I/J)
  amount       integer default 1,
  live         boolean not null default false, -- invasion en direct (décision D) vs Monban hors ligne
  created_at   timestamptz not null default now()
);
create index if not exists invasion_history_pair_idx on public.invasion_history(attacker_id, defender_id, created_at);

alter table public.monban_profiles enable row level security;
alter table public.monban_stats enable row level security;
alter table public.invasion_history enable row level security;

drop policy if exists monban_profiles_select_own on public.monban_profiles;
create policy monban_profiles_select_own on public.monban_profiles
  for select using (user_id = auth.uid());
-- Le worker (service_role) contourne la RLS pour lire N'IMPORTE QUEL profil
-- au moment de piloter une défense — normal et voulu (même pattern que
-- bot_roster / matchmaking_queue).

drop policy if exists monban_stats_select_public on public.monban_stats;
create policy monban_stats_select_public on public.monban_stats
  for select using (true); -- stats de combat publiques (consultables sur une fiche joueur)

drop policy if exists invasion_history_select_own on public.invasion_history;
create policy invasion_history_select_own on public.invasion_history
  for select using (attacker_id = auth.uid() or defender_id = auth.uid());

-- ── RPC : apprentissage (décision O) ─────────────────────────────────────
-- Appelée en best-effort depuis endGame() pour CHAQUE partie en ligne,
-- sur le modèle de logJournalEvent — ne doit jamais interrompre le flux de
-- jeu. p_delta est un petit résumé calculé côté client (façon
-- nt2AnalyzePlayerMove : missedWin/exposure/passivity + éventuellement les
-- 2-3 premiers coups joués pour les ouvertures), PAS la partie entière.
create or replace function public.monban_learn_from_game(p_delta jsonb)
returns void language plpgsql security definer set search_path to 'public' as $$
declare cur jsonb;
begin
  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (auth.uid(), '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;
  select profile into cur from monban_profiles where user_id = auth.uid();
  update monban_profiles set
    profile = cur || jsonb_strip_nulls(p_delta),  -- fusion superficielle ; l'agrégation fine (compteurs++) reste côté client avant envoi
    games_learned = games_learned + 1,
    updated_at = now()
    where user_id = auth.uid();
end; $$;

-- ── RPC : rituel d'entraînement quotidien (compte double, décision O) ───
create or replace function public.monban_mark_trained()
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update monban_profiles set last_trained_at = now() where user_id = auth.uid();
end; $$;

-- ── RPC : achat de bouclier (décision C, via Koku) ──────────────────────
create or replace function public.monban_buy_shield(p_koku_cost integer, p_hours integer)
returns timestamptz language plpgsql security definer set search_path to 'public' as $$
declare new_until timestamptz;
begin
  perform spend_koku(p_koku_cost);
  update profiles set shield_until = greatest(coalesce(shield_until, now()), now()) + make_interval(hours => p_hours)
    where id = auth.uid() returning shield_until into new_until;
  return new_until;
end; $$;

-- ⚠️ PAS DE RPC D'INVASION ICI (lancer/résoudre une invasion, voler une
-- monnaie). Ces opérations touchent DEUX comptes à la fois et doivent être
-- arbitrées par le worker serveur qui a réellement fait jouer la partie
-- (décision B) — les construire prématurément côté client serait exactement
-- le trou de triche identifié dans la roadmap. Lot I2/I5.

-- Contrôle de fin de script.
select 'monban_core OK' as status;
