-- ═══════════════════════════════════════════════════════════════════════
--  ADMINISTRATION DE GUILDE — retirer un membre + consulter d'autres guildes
--  À RELIRE ET EXÉCUTER par Jonathan (éditeur SQL Supabase). Additif et
--  idempotent : ne touche à aucune donnée, ne modifie pas le 1v1.
--
--  Prérequis présence : les colonnes profiles.last_seen / profiles.is_online
--  EXISTENT DÉJÀ (heartbeat client toutes les 20 s + presenceTier). Rien à
--  ajouter côté schéma : on ne fait que les EXPOSER via guild_roster.
--
--  Contenu :
--   1. guild_kick(p_player_id)  — le CHEF retire un membre (pas lui-même, pas
--                                 un autre chef)
--   2. guild_roster(p_guild_id) — roster PUBLIC d'une guilde (nom, membres,
--                                 rôle, contribution, présence) pour consulter
--                                 les autres guildes et leurs joueurs
-- ═══════════════════════════════════════════════════════════════════════

-- 1. Retirer un membre (chef uniquement) ---------------------------------
create or replace function public.guild_kick(p_player_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); gid bigint; myrole text; targetrole text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if myrole <> 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if p_player_id = uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  select role into targetrole from guild_members where guild_id = gid and player_id = p_player_id;
  if targetrole is null then return jsonb_build_object('ok', false, 'reason', 'not_member'); end if;
  -- Un chef ne peut pas être retiré (il doit transmettre le rôle ou dissoudre).
  if targetrole = 'leader' then return jsonb_build_object('ok', false, 'reason', 'cant_kick_leader'); end if;
  delete from guild_members where guild_id = gid and player_id = p_player_id;
  return jsonb_build_object('ok', true);
end $function$;

-- 2. Roster public d'une guilde (consulter les autres guildes) -----------
--    Présence incluse : last_seen/is_online sont déjà publics (liste des
--    joueurs en ligne). Classé par contribution comme get_my_guild.
create or replace function public.guild_roster(p_guild_id bigint)
 returns jsonb
 language sql
 security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'guild', (select jsonb_build_object('id', id, 'name', name, 'tag', tag,
                'join_mode', join_mode, 'ryu_total', ryu_total,
                'banner', banner, 'devise', devise)
              from guilds where id = p_guild_id),
    'members', coalesce((select jsonb_agg(row_to_json(x)) from (
        select pr.id as player_id, pr.pseudo, gm.role, gm.contributed_ryu,
               pr.last_seen, pr.is_online
        from guild_members gm join profiles pr on pr.id = gm.player_id
        where gm.guild_id = p_guild_id
        order by (gm.role = 'leader') desc, gm.contributed_ryu desc
      ) x), '[]'::jsonb)
  );
$function$;

grant execute on function public.guild_kick(uuid) to authenticated;
grant execute on function public.guild_roster(bigint) to authenticated, anon;

-- Contrôle -----------------------------------------------------------------
-- select public.guild_roster((select id from guilds order by ryu_total desc limit 1));
