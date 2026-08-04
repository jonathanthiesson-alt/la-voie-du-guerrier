-- ══════════════════════════════════════════════════════════════════
-- ÉQUIPE DES 15 — autorise le mode 'backfill' dans la directive du bot army.
--
-- Redéfinit bot_army_set_directive (de dev_bot_army.sql) en ajoutant 'backfill'
-- à la liste des modes acceptés, pour que le menu dev puisse poser cette
-- directive et que le CRON du worker la joue (sans passer par l'input manuel du
-- workflow). Rien d'autre ne change. Idempotent.
-- ══════════════════════════════════════════════════════════════════

drop function if exists bot_army_set_directive(boolean, int, text, uuid);
create or replace function bot_army_set_directive(
  p_enabled boolean, p_count int, p_mode text, p_target uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not is_admin_user() then raise exception 'not authorized'; end if;
  if p_mode not in ('matchmaking','arena','tournament','free','backfill') then
    raise exception 'mode invalide: %', p_mode;
  end if;
  update bot_army_control
     set enabled    = p_enabled,
         count      = greatest(0, least(coalesce(p_count,0), 100)),
         mode       = p_mode,
         target_id  = p_target,
         updated_by = auth.uid(),
         updated_at = now()
   where id = 1;
  return jsonb_build_object('ok', true);
end $$;

-- Contrôle : doit renvoyer la fonction + accepter 'backfill'.
select to_regproc('public.bot_army_set_directive')::text as fn;
