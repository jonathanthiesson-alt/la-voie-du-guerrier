-- ═══════════════════════════════════════════════════════════════════════
--  GRADES DE GUILDE — 4 grades renommables + 5 permissions cochables
--  À RELIRE ET EXÉCUTER par Jonathan (éditeur SQL Supabase). Additif :
--  ne touche à aucune donnée de jeu, ne modifie pas le 1v1.
--
--  Décision (2026-08-14) : contribution en KOKU (déjà en place via
--  guild_members.contributed_ryu / guilds.ryu_total) — pas de nouveau
--  mécanisme XP de guilde dans ce lot.
--
--  Modèle : guild_members.role reste un text, mais prend maintenant les
--  valeurs 'leader' (chef, TOUJOURS toutes les permissions, non stocké) ou
--  'g1'..'g4' (grades classés du plus au moins gradé). Les libellés affichés
--  et les 5 permissions par grade sont stockés sur la guilde elle-même
--  (guilds.rank_names / guilds.rank_permissions), donc personnalisables par
--  guilde sans migration.
--
--  Les 5 permissions (clés fixes, utilisées côté client ET serveur) :
--   manage_tool        — gérer l'outil de guilde (bannière, devise, message)
--   edit_lower_ranks    — changer le grade d'un membre de grade INFÉRIEUR
--   challenge_guild     — défier une autre guilde
--   manage_resources     — gérer/partager/dépenser les ressources (Koku)
--   manage_progress      — gérer XP/barres de progression de guilde
--
--  Contenu :
--   1. Colonnes guilds.rank_names / guilds.rank_permissions (+ défauts)
--   2. Migration des rôles existants 'member' -> 'g4'
--   3. Contrainte sur guild_members.role
--   4. guild_member_permission(guild_id, uid, perm) — vérif serveur réutilisable
--   5. guild_set_rank_config(p_names, p_permissions) — chef uniquement
--   6. guild_set_member_rank(p_player_id, p_rank) — chef, ou détenteur
--      d'edit_lower_ranks visant un grade strictement inférieur au sien
-- ═══════════════════════════════════════════════════════════════════════

-- 1. Colonnes ---------------------------------------------------------------
alter table public.guilds add column if not exists rank_names jsonb
  not null default '{"g1":"Vétéran","g2":"Officier","g3":"Membre","g4":"Recrue"}'::jsonb;

alter table public.guilds add column if not exists rank_permissions jsonb
  not null default '{
    "g1": {"manage_tool":false,"edit_lower_ranks":true,"challenge_guild":true,"manage_resources":true,"manage_progress":false},
    "g2": {"manage_tool":false,"edit_lower_ranks":false,"challenge_guild":true,"manage_resources":false,"manage_progress":false},
    "g3": {"manage_tool":false,"edit_lower_ranks":false,"challenge_guild":false,"manage_resources":false,"manage_progress":false},
    "g4": {"manage_tool":false,"edit_lower_ranks":false,"challenge_guild":false,"manage_resources":false,"manage_progress":false}
  }'::jsonb;

-- 2. Migration des rôles existants ------------------------------------------
update public.guild_members set role = 'g4' where role = 'member';

-- 3. Contrainte sur les valeurs de rôle --------------------------------------
alter table public.guild_members drop constraint if exists guild_members_role_check;
alter table public.guild_members add constraint guild_members_role_check
  check (role in ('leader','g1','g2','g3','g4'));

-- 4. Vérification de permission (réutilisable par d'autres RPC) -------------
--    Le chef a TOUJOURS toutes les permissions, sans avoir besoin d'être
--    listé dans rank_permissions.
create or replace function public.guild_member_permission(p_guild_id bigint, p_uid uuid, p_perm text)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare myrole text; perms jsonb;
begin
  select role into myrole from guild_members where guild_id = p_guild_id and player_id = p_uid;
  if myrole is null then return false; end if;
  if myrole = 'leader' then return true; end if;
  select rank_permissions -> myrole -> p_perm into perms from guilds where id = p_guild_id;
  return coalesce(perms::text::boolean, false);
end $function$;

-- 5. Configurer les grades (noms + permissions) — chef uniquement -----------
create or replace function public.guild_set_rank_config(p_names jsonb, p_permissions jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); gid bigint; myrole text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if myrole <> 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  -- On ne fait confiance qu'aux clés g1..g4 attendues, pour éviter d'injecter
  -- une clé arbitraire qui casserait guild_member_permission.
  if not (p_names ?& array['g1','g2','g3','g4']) then
    return jsonb_build_object('ok', false, 'reason', 'bad_names');
  end if;
  if not (p_permissions ?& array['g1','g2','g3','g4']) then
    return jsonb_build_object('ok', false, 'reason', 'bad_permissions');
  end if;
  update guilds set rank_names = p_names, rank_permissions = p_permissions where id = gid;
  return jsonb_build_object('ok', true);
end $function$;

-- 6. Changer le grade d'un membre --------------------------------------------
--    Le chef peut tout faire (sauf se retirer lui-même du rôle de chef ici —
--    la transmission du rôle de chef n'est pas incluse dans ce lot).
--    Un détenteur d'edit_lower_ranks ne peut viser qu'un membre dont le grade
--    ACTUEL est strictement inférieur au sien (g1 < g2 < g3 < g4 en rang, donc
--    "inférieur" = chiffre plus grand), et ne peut pas le promouvoir au-delà
--    de son propre grade.
create or replace function public.guild_set_member_rank(p_player_id uuid, p_rank text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); gid bigint; myrole text; targetrole text;
  my_n int; target_n int; new_n int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_rank not in ('g1','g2','g3','g4') then return jsonb_build_object('ok', false, 'reason', 'bad_rank'); end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if p_player_id = uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  select role into targetrole from guild_members where guild_id = gid and player_id = p_player_id;
  if targetrole is null then return jsonb_build_object('ok', false, 'reason', 'not_member'); end if;
  if targetrole = 'leader' then return jsonb_build_object('ok', false, 'reason', 'cant_edit_leader'); end if;

  if myrole = 'leader' then
    update guild_members set role = p_rank where guild_id = gid and player_id = p_player_id;
    return jsonb_build_object('ok', true);
  end if;

  if not public.guild_member_permission(gid, uid, 'edit_lower_ranks') then
    return jsonb_build_object('ok', false, 'reason', 'no_permission');
  end if;
  my_n := substring(myrole from 2)::int;
  target_n := substring(targetrole from 2)::int;
  new_n := substring(p_rank from 2)::int;
  if target_n <= my_n then return jsonb_build_object('ok', false, 'reason', 'target_not_lower'); end if;
  if new_n < my_n then return jsonb_build_object('ok', false, 'reason', 'cant_promote_above_self'); end if;
  update guild_members set role = p_rank where guild_id = gid and player_id = p_player_id;
  return jsonb_build_object('ok', true);
end $function$;

-- 7. get_my_guild() doit exposer les nouvelles colonnes au client (sinon le
--    client ne peut ni afficher ni éditer les grades). Redéfinition complète
--    par prudence (create or replace, même signature/type de retour donc pas
--    besoin de drop d'abord) — le reste du corps est inchangé.
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
      'banner',g.banner,'devise',g.devise,'info_message',g.info_message,'info_message_at',g.info_message_at,
      'rank_names',g.rank_names,'rank_permissions',g.rank_permissions),
    'my_role', myrole, 'members', members, 'requests', requests);
end $function$;

grant execute on function public.guild_member_permission(bigint, uuid, text) to authenticated;
grant execute on function public.guild_set_rank_config(jsonb, jsonb) to authenticated;
grant execute on function public.guild_set_member_rank(uuid, text) to authenticated;

-- Contrôle -------------------------------------------------------------------
-- select rank_names, rank_permissions from guilds limit 3;
-- select role, count(*) from guild_members group by role;
