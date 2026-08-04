-- ══════════════════════════════════════════════════════════════════
-- L'ÉQUIPE DES 15 — fondation (Phase B, lot 1/3)  ·  cf. docs/EQUIPE_DES_15.md
--
-- ⚠ IDENTITÉ DES BOTS : profiles.id RÉFÉRENCE auth.users(id). On ne crée donc
-- PAS les comptes ici (insérer dans auth.users à la main est fragile) : c'est
-- le WORKER (lot 2) qui provisionne les 16 comptes via l'API admin service_role,
-- crée leur ligne profiles (is_bot, Elo fixe, DEVISE = explication du nom) et
-- renseigne bot_roster.profile_id. Ce script reste purement additif (aucun
-- write sur profiles) et passe seul.
--
-- Chaque bot aura un VRAI profil consultable en jeu, avec sa devise = le sens
-- de son nom. Déblocage galerie (docs/EQUIPE_DES_15.md) : 1→10 visibles ;
-- 11→15 grisés tant que non rencontrés ; 0 (rei) invisible jusqu'à la 1re
-- rencontre — géré par tier + bot_encounters, appliqué côté app (lot 3).
--
-- ⚠ EXCLUSION CLASSEMENT (à faire côté app, lot 3) : leaderboard = requête
--   directe sur profiles → filtrer is_bot. La ligue est déjà protégée.
-- DÉCISION PRODUIT : parties de backfill AMICALES (ranked=false). Flippable.
-- ══════════════════════════════════════════════════════════════════

-- ── 1. Table roster + lecture publique ────────────────────────────
create table if not exists bot_roster (
  key        text primary key,
  profile_id uuid unique,            -- NULL tant que non provisionné (worker)
  num        text not null,          -- '00'..'15'
  reading    text not null,          -- lecture du nombre (romaji)
  rank       text not null,          -- rang guerrier (accents ok, affichage)
  pseudo     text not null,          -- pseudo ASCII (^[A-Za-z0-9_-]{3,20}$)
  kanji      text not null,          -- kanji du nombre
  rank_kanji text not null,          -- kanji du rang
  meaning    text not null,          -- sens du rang
  lore       text not null,          -- phrase de lore (galerie)
  devise     text not null,          -- explication du nom → devise du profil (≤60)
  base_elo   int  not null,
  tier       text not null,          -- open | greyed | hidden
  sort       int  not null           -- ordre de force croissant (1..16)
);
-- Rattrapage si une version antérieure a créé la table autrement (idempotent).
alter table bot_roster alter column profile_id drop not null;
alter table bot_roster add column if not exists pseudo text;
alter table bot_roster add column if not exists devise text;

alter table bot_roster enable row level security;
drop policy if exists bot_roster_public_read on bot_roster;
create policy bot_roster_public_read on bot_roster for select using (true);

-- ── 2. Seed roster (métadonnées uniquement — aucun write sur profiles) ─
insert into bot_roster(key,num,reading,rank,pseudo,kanji,rank_kanji,meaning,lore,devise,base_elo,tier,sort) values
  ('ichi','01','Ichi','Ashigaru','01-Ashigaru','一','足軽','Fantassin, la piétaille','Le premier pas sur la Voie. Tout le monde a commencé ici.','Ashigaru : le fantassin qui ouvre la Voie.',800,'open',1),
  ('ni','02','Ni','Genin','02-Genin','二','下忍','L''apprenti, rang le plus bas','Encore dans l''ombre, mais il apprend vite.','Genin : l''apprenti de l''ombre.',920,'open',2),
  ('san','03','San','Dōshin','03-Doshin','三','同心','Le garde, petit officier','Il tient son poste. On ne passe pas si facilement.','Dōshin : le garde qui tient son poste.',1040,'open',3),
  ('shi','04','Shi','Yōjimbo','04-Yojimbo','四','用心棒','Le garde du corps','Shi (四) sonne comme « la mort » (死) : un numéro qu''on évite… lui, non.','Yōjimbo : le garde du corps.',1160,'open',4),
  ('go','05','Go','Musha','05-Musha','五','武者','Le guerrier aguerri','La moitié du chemin. Il a déjà vu des batailles.','Musha : le guerrier aguerri.',1280,'open',5),
  ('roku','06','Roku','Kenshi','06-Kenshi','六','剣士','L''escrimeur, sabre en main','Sa lame parle avant lui.','Kenshi : l''escrimeur dont la lame parle.',1400,'open',6),
  ('shichi','07','Shichi','Bugeisha','07-Bugeisha','七','武芸者','Le maître d''armes','Sept, chiffre de chance : la sienne, il la forge.','Bugeisha : le maître d''armes.',1520,'open',7),
  ('hachi','08','Hachi','Samurai','08-Samurai','八','侍','Le samouraï au service','Hachi (八) évoque la prospérité : un serviteur accompli.','Samurai : le serviteur accompli.',1640,'open',8),
  ('kyu','09','Kyū','Hatamoto','09-Hatamoto','九','旗本','Le vassal direct du shogun','Neuf, tout près du sommet. Il porte la bannière.','Hatamoto : le vassal qui porte la bannière.',1760,'open',9),
  ('ju','10','Jū','Karō','10-Karo','十','家老','L''intendant, plus haut vassal','Dix : la main droite du seigneur. Dernier des « accessibles ».','Karō : la main droite du seigneur.',1880,'open',10),
  ('juichi','11','Jūichi','Kensei','11-Kensei','十一','剣聖','Le saint du sabre','On ne le voit qu''après l''avoir croisé. Sa maîtrise est un mythe.','Kensei : le saint du sabre.',2020,'greyed',11),
  ('juni','12','Jūni','Daimyō','12-Daimyo','十二','大名','Le grand seigneur féodal','Il commande des provinces entières.','Daimyō : le grand seigneur féodal.',2160,'greyed',12),
  ('jusan','13','Jūsan','Shōgun','13-Shogun','十三','将軍','Le généralissime','Treize : le chiffre qui fait trembler. Il règne.','Shōgun : le généralissime qui règne.',2300,'greyed',13),
  ('juyon','14','Jūyon','Kami','14-Kami','十四','神','La divinité, l''esprit tutélaire','Plus tout à fait humain. On le vénère autant qu''on le craint.','Kami : la divinité tutélaire.',2440,'greyed',14),
  ('jugo','15','Jūgo','Bushi','15-Bushi','十五','武士','Le Guerrier (voie du bushidō)','Sommet des numéros : l''incarnation même de la Voie.','Bushi : l''incarnation de la Voie.',2580,'greyed',15),
  ('rei','00','Rei','Rōnin','00-Ronin','零','浪人','Le samouraï sans maître','Le numéro qui n''existe pas. Surgi du vide, il ne répond à personne — et il est le plus fort.','Rōnin : le samouraï sans maître, surgi du vide.',2800,'hidden',16)
on conflict (key) do update set
  num=excluded.num, reading=excluded.reading, rank=excluded.rank, pseudo=excluded.pseudo,
  kanji=excluded.kanji, rank_kanji=excluded.rank_kanji, meaning=excluded.meaning,
  lore=excluded.lore, devise=excluded.devise, base_elo=excluded.base_elo,
  tier=excluded.tier, sort=excluded.sort;

-- ── 3. Préférences de backfill sur la file (additif, défauts sûrs) ─
alter table matchmaking_queue add column if not exists want_backfill  boolean not null default false;
alter table matchmaking_queue add column if not exists backfill_after  int     not null default 20; -- secondes avant qu'un bot rejoigne

-- ── 4. Rencontres (débloque la galerie) ───────────────────────────
create table if not exists bot_encounters (
  player_id    uuid not null,
  bot_key      text not null references bot_roster(key) on delete cascade,
  first_met_at timestamptz not null default now(),
  primary key (player_id, bot_key)
);
-- RLS activée sans politique client : accès uniquement via les RPC (motif admin_audit_log).
alter table bot_encounters enable row level security;

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

-- ── 5. Entretien pg_cron : « en ligne » + fauche des files ─────────
create extension if not exists pg_cron;
create or replace function team15_maintenance()
returns void language plpgsql security definer set search_path=public as $$
begin
  update profiles set is_online = true, last_seen = now()
    where id in (select profile_id from bot_roster where profile_id is not null);
  delete from matchmaking_queue q using profiles pr
    where q.player_id = pr.id and pr.is_bot and q.joined_at < now() - interval '2 minutes';
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'team15_maintenance_tick') then
    perform cron.unschedule('team15_maintenance_tick');
  end if;
end $$;
-- Format cron 5 champs (cette version de pg_cron refuse '1 minute' ; l'interval
-- n'accepte que '[1-59] seconds'). '* * * * *' = chaque minute.
select cron.schedule('team15_maintenance_tick', '* * * * *', $$select public.team15_maintenance();$$);

-- ── Contrôle ──────────────────────────────────────────────────────
select
  (select count(*) from bot_roster)                                   as roster_rows,        -- 16
  (select count(*) from bot_roster where profile_id is not null)      as provisioned,        -- 0 (worker plus tard)
  (select count(*) from bot_roster where length(devise) > 60)         as devises_trop_longues, -- 0
  to_regproc('public.mark_bot_encounter')::text                       as fn_mark,
  to_regproc('public.get_my_bot_encounters')::text                    as fn_get,
  (select count(*) from information_schema.columns
     where table_name='matchmaking_queue' and column_name='want_backfill') as has_want_backfill,
  (select count(*) from cron.job where jobname='team15_maintenance_tick')  as cron_scheduled;
