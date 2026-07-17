-- ═══════════════════════════════════════════════════════════════════
-- ÉVÉNEMENT SUMO (été 2026, jusqu'au 31 août)
--
-- Le SUMO réutilise TOUTE l'infrastructure Arène (mêmes tables, mêmes
-- manches BO3) : on ne fait qu'ajouter une colonne `mode` pour séparer
-- les files et les matchs, une colonne `elo` pour l'appariement au plus
-- proche niveau, et la monnaie Fame 心 (profiles.fame_balance).
--
-- Barème (versé UNIQUEMENT au match décidé, jamais par manche) :
--   vainqueur +2 Fame · vaincu +1 Fame — le tout côté serveur, en un
--   seul appel RPC fait par le client GAGNANT (même convention que
--   record_arena_round_win : le perdant ne fait que poller).
-- Après le 31 août : le match se termine normalement, mais plus aucune
-- Fame n'est versée.
--
-- Classement : score = fame × (1 + ratio de victoires). Plus le ratio
-- victoires/parties est élevé, plus le multiplicateur est important —
-- calculé dans la vue, jamais côté client.
--
-- Idempotent. À exécuter en une fois dans l'éditeur SQL Supabase.
-- ═══════════════════════════════════════════════════════════════════

-- ── Colonnes ────────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists fame_balance integer not null default 0,
  add column if not exists sumo_wins    integer not null default 0,
  add column if not exists sumo_losses  integer not null default 0;

alter table public.arena_matchmaking_queue
  add column if not exists mode text not null default 'arena',
  add column if not exists elo  integer not null default 1200;

alter table public.arena_matches
  add column if not exists mode text not null default 'arena';

-- ── RPC : fin de manche SUMO ───────────────────────────────────────
-- Copie conforme de record_arena_round_win pour l'enchaînement des
-- manches, mais : pas de Koku/Tamashii, Fame aux DEUX joueurs à la fin
-- du match, et compteurs sumo_wins/sumo_losses pour le multiplicateur.
create or replace function public.record_sumo_round_win(p_arena_match_id uuid, p_winner_color text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  m record; new_ww integer; new_wb integer; done boolean;
  wid uuid; lid uuid; new_round integer; fame integer := 0;
  event_live boolean := (now() < timestamptz '2026-09-01 00:00:00+02');
begin
  select * into m from arena_matches where id = p_arena_match_id for update;
  if m is null then raise exception 'Match SUMO introuvable'; end if;
  if coalesce(m.mode,'arena') <> 'sumo' then raise exception 'Ce match n''est pas un match SUMO'; end if;
  -- Seuls les deux combattants peuvent clore une manche de leur match.
  if auth.uid() is distinct from m.white_player_id and auth.uid() is distinct from m.black_player_id then
    raise exception 'not a participant';
  end if;

  if p_winner_color = 'white' then
    new_ww := m.wins_white + 1; new_wb := m.wins_black; wid := m.white_player_id; lid := m.black_player_id;
  else
    new_ww := m.wins_white; new_wb := m.wins_black + 1; wid := m.black_player_id; lid := m.white_player_id;
  end if;

  done := (new_ww >= 2 or new_wb >= 2);
  new_round := case when done then m.round_number else m.round_number + 1 end;

  if done and event_live then
    -- Montants EN DUR côté serveur (leçon guild_contribute_ryu : le
    -- client ne transmet jamais un montant).
    fame := 2;
    update profiles set fame_balance = fame_balance + 2, sumo_wins   = sumo_wins   + 1 where id = wid;
    update profiles set fame_balance = fame_balance + 1, sumo_losses = sumo_losses + 1 where id = lid;
  end if;

  update arena_matches set
    wins_white = new_ww, wins_black = new_wb,
    status     = case when done then 'finished' else status end,
    winner_id  = case when done then wid else winner_id end,
    round_number = new_round,
    ready_white = false, ready_black = false
  where id = p_arena_match_id;

  return jsonb_build_object('wins_white', new_ww, 'wins_black', new_wb,
    'match_done', done, 'fame_awarded', fame, 'winner_id', wid, 'round_number', new_round);
end $function$;

grant execute on function public.record_sumo_round_win(uuid, text) to authenticated;

-- ── Classement SUMO ────────────────────────────────────────────────
-- score = fame × (1 + ratio de victoires × montée en puissance).
-- Le bonus de ratio ne se débloque PAS d'un coup : il monte à chaque
-- partie jouée (min(parties,35)/35, soit ~2,9 % du plein bonus par
-- partie) et n'atteint son plein effet qu'à 35 parties. Sans ça, un
-- joueur à 1 victoire / 1 partie afficherait un ratio de 100 % et
-- doublerait sa Fame au classement — le palier force un ratio
-- statistiquement exploitable pour le classement général du tournoi.
-- fame_balance reste la monnaie brute (dépensable), le bonus n'existe
-- qu'au classement.
drop view if exists public.sumo_leaderboard;
create view public.sumo_leaderboard as
select
  p.id, p.pseudo,
  p.fame_balance                               as fame,
  p.sumo_wins, p.sumo_losses,
  (p.sumo_wins + p.sumo_losses)                as games,
  round(p.sumo_wins::numeric / (p.sumo_wins + p.sumo_losses), 3)                as ratio,
  -- part du bonus débloquée (0 → 1), pleine à 35 parties
  round(least(p.sumo_wins + p.sumo_losses, 35) / 35.0, 3)                       as bonus_unlock,
  round(p.fame_balance * (1 + (p.sumo_wins::numeric / (p.sumo_wins + p.sumo_losses))
                              * (least(p.sumo_wins + p.sumo_losses, 35) / 35.0))) as score
from profiles p
where (p.sumo_wins + p.sumo_losses) > 0
order by score desc, fame desc;

grant select on public.sumo_leaderboard to authenticated;

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regproc('public.record_sumo_round_win')::text as fn_sumo,
  (select count(*) from information_schema.columns
     where table_name='profiles' and column_name in ('fame_balance','sumo_wins','sumo_losses')) as cols_profiles,   -- attendu 3
  (select count(*) from information_schema.columns
     where table_name='arena_matchmaking_queue' and column_name in ('mode','elo')) as cols_queue,                   -- attendu 2
  (select count(*) from information_schema.columns
     where table_name='arena_matches' and column_name='mode') as col_matches;                                       -- attendu 1
