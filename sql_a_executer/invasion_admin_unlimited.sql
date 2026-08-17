-- ═══════════════════════════════════════════════════════════════════
-- INVASIONS ILLIMITÉES POUR LES ADMINS (décision AD, ROADMAP_GUILD_BATTLE.md)
--
-- Prérequis de test du lot G0 (Monban réactif) : Wurmz et Musashi doivent
-- pouvoir déclencher des invasions à volonté, dans les deux sens, pour
-- valider la latence de l'Edge Function monban-move sans attendre les
-- cooldowns normaux (24h attaquant, 72h par couple attaquant/défenseur).
--
-- Portée du bypass :
--  • attaquant admin (is_admin_user()) → saute le cooldown 24h ET le
--    cooldown 72h du couple ;
--  • défenseur admin → saute le cooldown 72h du couple (permet à
--    n'importe qui de ré-envahir un admin pour tester la défense/Monban) ;
--  • le bouclier (shield_until) du défenseur reste TOUJOURS respecté,
--    admin ou pas — ce n'est pas un anti-harcèlement mais un achat du
--    joueur, on ne le contourne jamais silencieusement.
--
-- Le rôle admin est lu via is_admin_user()/profiles.is_admin (jamais une
-- liste de pseudos en dur, cf. CLAUDE.md).
--
-- Réécrit invasion_authorize (invasion_engine.sql) — même signature,
-- simple create or replace, idempotent. À exécuter après invasion_engine.sql.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.invasion_authorize(p_defender_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_attacker uuid := auth.uid();
  v_attacker_admin boolean;
  v_defender_admin boolean;
  v_last_invasion timestamptz;
  v_shield timestamptz;
  v_recent_pair int;
  v_request_id bigint;
  v_expires timestamptz;
begin
  if v_attacker is null then raise exception 'Non authentifié.'; end if;
  if v_attacker = p_defender_id then raise exception 'Impossible de s''envahir soi-même.'; end if;

  select coalesce(is_admin, false) into v_attacker_admin from profiles where id = v_attacker;
  select coalesce(is_admin, false) into v_defender_admin from profiles where id = p_defender_id;

  -- Cooldown 24h attaquant : sauté si l'attaquant est admin.
  if not v_attacker_admin then
    select last_invasion_at into v_last_invasion from profiles where id = v_attacker;
    if v_last_invasion is not null and v_last_invasion > now() - interval '24 hours' then
      raise exception 'Une seule invasion par jour — reviens plus tard.';
    end if;
  end if;

  -- Bouclier : TOUJOURS respecté, même pour/contre un admin.
  select shield_until into v_shield from profiles where id = p_defender_id;
  if v_shield is not null and v_shield > now() then
    raise exception 'Ce joueur est protégé par un bouclier.';
  end if;

  -- Cooldown 72h du couple : sauté si l'attaquant OU le défenseur est admin.
  if not v_attacker_admin and not v_defender_admin then
    select count(*) into v_recent_pair from invasion_history
      where attacker_id = v_attacker and defender_id = p_defender_id and created_at > now() - interval '72 hours';
    if v_recent_pair > 0 then
      raise exception 'Tu as déjà envahi ce joueur récemment — réessaie plus tard.';
    end if;
  end if;

  -- Le marquage last_invasion_at reste écrit même pour un admin (traçabilité),
  -- il n'est simplement plus lu comme cooldown pour lui à la prochaine invasion.
  update profiles set last_invasion_at = now() where id = v_attacker;

  v_expires := now() + interval '15 seconds';
  insert into invasion_requests (attacker_id, defender_id, status, expires_at)
    values (v_attacker, p_defender_id, 'awaiting_accept', v_expires)
    returning id into v_request_id;

  insert into notifications (user_id, type, title, body, payload)
    values (p_defender_id, 'invasion_incoming', 'Invasion !',
            'Un envahisseur attaque ton dojo — 15 secondes pour te défendre en personne, sinon Monban prend le relais.',
            jsonb_build_object('request_id', v_request_id));

  return jsonb_build_object('request_id', v_request_id, 'expires_at', v_expires);
end; $$;

-- ── Contrôle ───────────────────────────────────────────────────────
select to_regproc('public.invasion_authorize')::text as fn_invasion_authorize, -- attendu non-null
  'invasion_admin_unlimited OK' as status;
