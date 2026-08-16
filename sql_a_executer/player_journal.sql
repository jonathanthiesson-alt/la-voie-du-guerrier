-- Journal personnel du joueur (Archives) — V0.87.0
-- Table dédiée : activity_feed n'a pas de colonne user_id (fil GLOBAL du
-- serveur, pas réutilisable pour un journal par joueur). Idempotent.

create table if not exists player_journal (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  event_type text not null, -- 'victory' | 'defeat' | 'achievement' | 'guild_join' | 'skin_unlock'
  message text not null
);

create index if not exists player_journal_user_idx on player_journal(user_id, created_at desc);

alter table player_journal enable row level security;

drop policy if exists player_journal_select_own on player_journal;
create policy player_journal_select_own on player_journal
  for select using (auth.uid() = user_id);

drop policy if exists player_journal_insert_own on player_journal;
create policy player_journal_insert_own on player_journal
  for insert with check (auth.uid() = user_id);

-- Contrôle de fin de script.
select 'player_journal OK' as status;
