-- ═══════════════════════════════════════════════════════════════════════
--  IDENTITÉ DE GUILDE — bannière, devise, message d'info du chef
--  À RELIRE ET EXÉCUTER par Jonathan (éditeur SQL Supabase). Additif et
--  idempotent : n'altère aucune donnée existante, ne touche pas au 1v1.
--
--  Contenu :
--   1. 3 colonnes sur `guilds` (banner jsonb, devise, info_message + horodatage)
--   2. get_my_guild() étendu pour renvoyer ces champs (type de retour inchangé)
--   3. guild_update_identity() — le CHEF (role='leader') édite l'identité
--   4. guild_identity(id) — lecture publique (affichage combat / popup)
-- ═══════════════════════════════════════════════════════════════════════

-- 1. Colonnes -------------------------------------------------------------
alter table public.guilds add column if not exists banner          jsonb;        -- {emblem:'🐉', color1:'#..', color2:'#..'}
alter table public.guilds add column if not exists devise          text;
alter table public.guilds add column if not exists info_message    text;
alter table public.guilds add column if not exists info_message_at timestamptz;  -- bumpé quand le message change (déclenche le popup joueurs)

-- 2. get_my_guild() : on ajoute banner/devise/info à l'objet guilde --------
--    (return type reste jsonb → CREATE OR REPLACE sans DROP, pas de 42P16)
create or replace function public.get_my_guild()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); g record; members jsonb; requests jsonb; myrole text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.role into myrole from guild_members gm where gm.player_id = uid;
  if myrole is null then return jsonb_build_object('in_guild', false); end if;
  select gu.* into g from guilds gu join guild_members gm on gm.guild_id = gu.id where gm.player_id = uid;
  select coalesce(jsonb_agg(row_to_json(x)),'[]'::jsonb) into members from (
    select pr.pseudo, gm.role, gm.contributed_ryu, gm.player_id
    from guild_members gm join profiles pr on pr.id = gm.player_id
    where gm.guild_id = g.id order by gm.contributed_ryu desc
  ) x;
  requests := '[]'::jsonb;
  if myrole = 'leader' then
    select coalesce(jsonb_agg(row_to_json(y)),'[]'::jsonb) into requests from (
      select gr.id, pr.pseudo, gr.player_id
      from guild_requests gr join profiles pr on pr.id = gr.player_id
      where gr.guild_id = g.id order by gr.created_at asc
    ) y;
  end if;
  return jsonb_build_object('in_guild', true, 'guild',
    jsonb_build_object('id',g.id,'name',g.name,'tag',g.tag,'join_mode',g.join_mode,'ryu_total',g.ryu_total,
      'banner',g.banner,'devise',g.devise,'info_message',g.info_message,'info_message_at',g.info_message_at),
    'my_role', myrole, 'members', members, 'requests', requests);
end $function$;

-- 3. Édition par le chef --------------------------------------------------
create or replace function public.guild_update_identity(p_devise text, p_banner jsonb, p_info_message text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); gid bigint; myrole text; changed boolean; clean_info text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if myrole <> 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  -- Longueurs bornées (la modération de fond racisme/insultes est faite côté
  -- client comme pour la devise de joueur ; ici on borne et on nettoie).
  p_devise      := nullif(btrim(left(coalesce(p_devise, ''), 80)), '');
  clean_info    := nullif(btrim(left(coalesce(p_info_message, ''), 500)), '');
  select (info_message is distinct from clean_info) into changed from guilds where id = gid;
  update guilds set
    devise = p_devise,
    banner = p_banner,
    info_message = clean_info,
    -- On ne bump l'horodatage QUE si le message a réellement changé et n'est
    -- pas vide → le popup ne réapparaît pas pour une simple édition de devise.
    info_message_at = case when changed and clean_info is not null then now() else info_message_at end
  where id = gid;
  return jsonb_build_object('ok', true);
end $function$;

-- 4. Lecture publique de l'identité (affichage au combat, popup) ----------
create or replace function public.guild_identity(p_guild_id bigint)
 returns jsonb
 language sql
 security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object('id', id, 'name', name, 'tag', tag, 'devise', devise,
    'banner', banner, 'info_message', info_message, 'info_message_at', info_message_at)
  from guilds where id = p_guild_id;
$function$;

grant execute on function public.get_my_guild() to authenticated;
grant execute on function public.guild_update_identity(text, jsonb, text) to authenticated;
grant execute on function public.guild_identity(bigint) to authenticated, anon;

-- Contrôle -----------------------------------------------------------------
-- select column_name from information_schema.columns
--   where table_schema='public' and table_name='guilds'
--     and column_name in ('banner','devise','info_message','info_message_at');
