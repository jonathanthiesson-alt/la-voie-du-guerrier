-- ══════════════════════════════════════════════════════════════════
-- L'ÉQUIPE DES 15 — fondation (Phase B, lot 1/3)  ·  cf. docs/EQUIPE_DES_15.md
--
-- Pose la source de vérité des 16 IA-bots nommés + le socle du BACKFILL
-- (un bot d'Elo proche rejoint un joueur qui poireaute dans la file).
--
-- CE QUE FAIT CE SCRIPT (additif, idempotent, SANS toucher au chemin
-- critique du matchmaking humain) :
--   1. table bot_roster (métadonnées : nom, rang, Elo, tier, lore) + lecture
--      publique — la galerie pourra s'en servir de source ;
--   2. 16 profils VIRTUELS (profiles.is_bot=true) : profiles n'a AUCUNE FK
--      vers auth.users, donc pas besoin de comptes auth — le worker les
--      pilotera en service_role. Elo fixe (elo_3s/5s/10s), « toujours en ligne » ;
--   3. matchmaking_queue : 2 colonnes additives (want_backfill, backfill_after)
--      — défauts sûrs, l'insert existant de l'app n'est pas impacté ;
--   4. suivi des rencontres (bot_encounters) + RPC mark/get pour la galerie ;
--   5. pg_cron d'entretien : garde les 16 « en ligne » + fauche les entrées de
--      file de bots périmées (anti-partie-orpheline).
--
-- CE QU'IL NE FAIT PAS (lots suivants) :
--   • la CRÉATION de la partie de backfill + le pilotage des coups = le WORKER
--     (scripts/bot-army.mjs, service_role) — la construction du game_state reste
--     dans le moteur, jamais dupliquée en SQL (règle anti-dérive) ;
--   • l'UI (case à cocher + slider, galerie depuis la DB) = index.html.
--
-- ⚠ EXCLUSION CLASSEMENT : à faire côté app (leaderboard = requête directe
--   sur profiles) → filtrer is_bot, sinon un bot Elo 2800 trusterait le top.
--   La ligue est déjà protégée (dev_bot_army.sql).
--
-- DÉCISION PRODUIT : les parties de backfill seront AMICALES (ranked=false)
--   côté worker, pour ne pas farmer l'Elo contre des bots à Elo fixe. Flippable.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Table roster + lecture publique ────────────────────────────
create table if not exists bot_roster (
  key        text primary key,
  profile_id uuid not null unique,
  num        text not null,          -- '00'..'15'
  reading    text not null,          -- lecture du nombre (romaji)
  rank       text not null,          -- rang guerrier (accents ok, affichage)
  kanji      text not null,          -- kanji du nombre
  rank_kanji text not null,          -- kanji du rang
  meaning    text not null,          -- sens du rang
  lore       text not null,          -- phrase de lore
  base_elo   int  not null,
  tier       text not null,          -- open | greyed | hidden
  sort       int  not null           -- ordre de force croissant (1..16)
);
alter table bot_roster enable row level security;
drop policy if exists bot_roster_public_read on bot_roster;
create policy bot_roster_public_read on bot_roster for select using (true);

-- ── 2. Seed roster + 16 profils virtuels ──────────────────────────
-- profile_id déterministe (md5 → uuid) : ré-exécutable sans doublon.
-- pseudo ASCII imposé par la contrainte profiles.pseudo (^[A-Za-z0-9_-]{3,20}$).
with r(key,num,reading,rank,pseudo,kanji,rank_kanji,meaning,lore,elo,tier,sort) as (values
  ('ichi','01','Ichi','Ashigaru','01-Ashigaru','一','足軽','Fantassin, la piétaille','Le premier pas sur la Voie. Tout le monde a commencé ici.',800,'open',1),
  ('ni','02','Ni','Genin','02-Genin','二','下忍','L''apprenti, rang le plus bas','Encore dans l''ombre, mais il apprend vite.',920,'open',2),
  ('san','03','San','Dōshin','03-Doshin','三','同心','Le garde, petit officier','Il tient son poste. On ne passe pas si facilement.',1040,'open',3),
  ('shi','04','Shi','Yōjimbo','04-Yojimbo','四','用心棒','Le garde du corps','Shi (四) sonne comme « la mort » (死) : un numéro qu''on évite… lui, non.',1160,'open',4),
  ('go','05','Go','Musha','05-Musha','五','武者','Le guerrier aguerri','La moitié du chemin. Il a déjà vu des batailles.',1280,'open',5),
  ('roku','06','Roku','Kenshi','06-Kenshi','六','剣士','L''escrimeur, sabre en main','Sa lame parle avant lui.',1400,'open',6),
  ('shichi','07','Shichi','Bugeisha','07-Bugeisha','七','武芸者','Le maître d''armes','Sept, chiffre de chance : la sienne, il la forge.',1520,'open',7),
  ('hachi','08','Hachi','Samurai','08-Samurai','八','侍','Le samouraï au service','Hachi (八) évoque la prospérité : un serviteur accompli.',1640,'open',8),
  ('kyu','09','Kyū','Hatamoto','09-Hatamoto','九','旗本','Le vassal direct du shogun','Neuf, tout près du sommet. Il porte la bannière.',1760,'open',9),
  ('ju','10','Jū','Karō','10-Karo','十','家老','L''intendant, plus haut vassal','Dix : la main droite du seigneur. Dernier des « accessibles ».',1880,'open',10),
  ('juichi','11','Jūichi','Kensei','11-Kensei','十一','剣聖','Le saint du sabre','On ne le voit qu''après l''avoir croisé. Sa maîtrise est un mythe.',2020,'greyed',11),
  ('juni','12','Jūni','Daimyō','12-Daimyo','十二','大名','Le grand seigneur féodal','Il commande des provinces entières.',2160,'greyed',12),
  ('jusan','13','Jūsan','Shōgun','13-Shogun','十三','将軍','Le généralissime','Treize : le chiffre qui fait trembler. Il règne.',2300,'greyed',13),
  ('juyon','14','Jūyon','Kami','14-Kami','十四','神','La divinité, l''esprit tutélaire','Plus tout à fait humain. On le vénère autant qu''on le craint.',2440,'greyed',14),
  ('jugo','15','Jūgo','Bushi','15-Bushi','十五','武士','Le Guerrier (voie du bushidō)','Sommet des numéros : l''incarnation même de la Voie.',2580,'greyed',15),
  ('rei','00','Rei','Rōnin','00-Ronin','零','浪人','Le samouraï sans maître','Le numéro qui n''existe pas. Surgi du vide, il ne répond à personne — et il est le plus fort.',2800,'hidden',16)
)
insert into bot_roster(key,profile_id,num,reading,rank,kanji,rank_kanji,meaning,lore,base_elo,tier,sort)
select r.key, md5('vdg-team15-'||r.key)::uuid, r.num, r.reading, r.rank, r.kanji,
       r.rank_kanji, r.meaning, r.lore, r.elo, r.tier, r.sort
from r
on conflict (key) do update set
  num=excluded.num, reading=excluded.reading, rank=excluded.rank, kanji=excluded.kanji,
  rank_kanji=excluded.rank_kanji, meaning=excluded.meaning, lore=excluded.lore,
  base_elo=excluded.base_elo, tier=excluded.tier, sort=excluded.sort;

-- Les profils virtuels. On passe par un 2e VALUES juste pour le pseudo ASCII
-- (bot_roster garde le rang accentué). is_bot + Elo fixe + en ligne.
with p(key,pseudo) as (values
  ('ichi','01-Ashigaru'),('ni','02-Genin'),('san','03-Doshin'),('shi','04-Yojimbo'),
  ('go','05-Musha'),('roku','06-Kenshi'),('shichi','07-Bugeisha'),('hachi','08-Samurai'),
  ('kyu','09-Hatamoto'),('ju','10-Karo'),('juichi','11-Kensei'),('juni','12-Daimyo'),
  ('jusan','13-Shogun'),('juyon','14-Kami'),('jugo','15-Bushi'),('rei','00-Ronin')
)
insert into profiles(id, pseudo, is_bot, is_online, elo_3s, elo_5s, elo_10s)
select br.profile_id, p.pseudo, true, true, br.base_elo, br.base_elo, br.base_elo
from bot_roster br join p on p.key = br.key
on conflict (id) do update set
  pseudo=excluded.pseudo, is_bot=true, is_online=true,
  elo_3s=excluded.elo_3s, elo_5s=excluded.elo_5s, elo_10s=excluded.elo_10s;

-- ── 3. Préférences de backfill sur la file (additif, défauts sûrs) ─
alter table matchmaking_queue add column if not exists want_backfill  boolean not null default false;
alter table matchmaking_queue add column if not exists backfill_after  int     not null default 20; -- secondes d'attente avant qu'un bot rejoigne

-- ── 4. Rencontres (débloque la galerie) ───────────────────────────
create table if not exists bot_encounters (
  player_id    uuid not null,
  bot_key      text not null references bot_roster(key) on delete cascade,
  first_met_at timestamptz not null default now(),
  primary key (player_id, bot_key)
);
-- RLS activée sans politique client : accès uniquement via les RPC ci-dessous
-- (même motif que admin_audit_log).
alter table bot_encounters enable row level security;

-- Marque une rencontre pour le joueur courant (appelé en fin de partie vs bot).
drop function if exists mark_bot_encounter(text);
create or replace function mark_bot_encounter(p_bot_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from bot_roster where key = p_bot_key) then
    raise exception 'bot inconnu: %', p_bot_key;
  end if;
  insert into bot_encounters(player_id, bot_key) values (uid, p_bot_key)
    on conflict (player_id, bot_key) do nothing;
  return jsonb_build_object('ok', true, 'bot_key', p_bot_key);
end $$;

-- Liste des clés de bots rencontrés par le joueur courant (pour la galerie).
drop function if exists get_my_bot_encounters();
create or replace function get_my_bot_encounters()
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return '[]'::jsonb; end if;
  return coalesce(
    (select jsonb_agg(bot_key order by bot_key) from bot_encounters where player_id = uid),
    '[]'::jsonb);
end $$;

-- ── 5. Entretien pg_cron : « toujours en ligne » + fauche des files ─
create extension if not exists pg_cron;
create or replace function team15_maintenance()
returns void language plpgsql security definer set search_path=public as $$
begin
  -- garde les 16 bots présents
  update profiles set is_online = true, last_seen = now()
    where id in (select profile_id from bot_roster);
  -- fauche les entrées de file de bots (roster OU anonymes) trop vieilles :
  -- sinon un joueur pourrait se matcher avec un bot mort → partie orpheline.
  delete from matchmaking_queue q using profiles pr
    where q.player_id = pr.id and pr.is_bot and q.joined_at < now() - interval '2 minutes';
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'team15_maintenance_tick') then
    perform cron.unschedule('team15_maintenance_tick');
  end if;
end $$;
select cron.schedule('team15_maintenance_tick', '1 minute', $$select public.team15_maintenance();$$);

-- ── Contrôle ──────────────────────────────────────────────────────
select
  (select count(*) from bot_roster)                                   as roster_rows,        -- 16
  (select count(*) from profiles where is_bot
     and id in (select profile_id from bot_roster))                   as bot_profiles,       -- 16
  to_regproc('public.mark_bot_encounter')::text                       as fn_mark,
  to_regproc('public.get_my_bot_encounters')::text                    as fn_get,
  (select count(*) from information_schema.columns
     where table_name='matchmaking_queue' and column_name='want_backfill') as has_want_backfill,
  (select count(*) from cron.job where jobname='team15_maintenance_tick')  as cron_scheduled;
