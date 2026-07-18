-- ═══════════════════════════════════════════════════════════════════
-- Chat de guilde — canal de discussion des membres (refonte UI, phase B)
--
-- Calqué sur league_channel_messages : une table simple, lue et écrite
-- directement par le client (pas de RPC), protégée par RLS pour que
-- SEULS les membres de la guilde voient et écrivent dans le canal.
--
-- Double accès côté client : depuis le menu Guilde (onglet JOUER) et
-- depuis la Messagerie (onglet SOCIAL) — une seule table, deux portes.
--
-- Idempotent. À exécuter en une fois dans l'éditeur SQL Supabase.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.guild_channel_messages (
  id            bigint generated always as identity primary key,
  guild_id      bigint not null references public.guilds(id) on delete cascade,
  sender_id     uuid   not null references auth.users(id) on delete cascade,
  sender_pseudo text   not null default '?',
  body          text   not null,
  created_at    timestamptz not null default now()
);

create index if not exists guild_channel_messages_guild_idx
  on public.guild_channel_messages (guild_id, created_at);

alter table public.guild_channel_messages enable row level security;

-- ⚠ RLS activée SANS politique = table totalement bloquée (leçon du
-- matchmaking). On pose donc explicitement lecture + écriture réservées
-- aux membres de la guilde concernée.

-- Lecture : uniquement si je suis membre de cette guilde.
drop policy if exists guild_chat_select on public.guild_channel_messages;
create policy guild_chat_select on public.guild_channel_messages
  for select to authenticated
  using (exists (
    select 1 from public.guild_members gm
    where gm.guild_id = guild_channel_messages.guild_id
      and gm.player_id = auth.uid()
  ));

-- Écriture : je ne peux insérer que MON propre message, et seulement
-- dans une guilde dont je suis membre (sender_id forcé à auth.uid()).
drop policy if exists guild_chat_insert on public.guild_channel_messages;
create policy guild_chat_insert on public.guild_channel_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.guild_members gm
      where gm.guild_id = guild_channel_messages.guild_id
        and gm.player_id = auth.uid()
    )
  );

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regclass('public.guild_channel_messages')::text as table_ok,          -- attendu non-null
  (select count(*) from pg_policies
     where schemaname='public' and tablename='guild_channel_messages') as nb_policies;  -- attendu 2
