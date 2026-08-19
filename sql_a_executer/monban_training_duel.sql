-- ═══════════════════════════════════════════════════════════════════
-- DUEL D'ENTRAÎNEMENT CONTRE SON PROPRE MONBAN — décision Wurmz 2026-08-18
-- Sens du gain INVERSÉ le 2026-08-19 (Wurmz) : c'est en le BATTANT qu'on
-- l'améliore, pas l'inverse — un sparring-partner progresse en encaissant.
--
-- Le clic quotidien "Entraîner Monban" ne donne plus un +2 instantané : il
-- déclenche un vrai duel local (couleur tirée au sort, cadence au choix
-- 3s/5s/10s). monban_mark_trained() ne fait que poser la garde 1×/jour
-- (illimité pour Wurmz/Musashi via is_admin_user(), même patron que
-- sql_a_executer/monban_daily_training.sql) — les points viennent du
-- résultat réel du duel, appliqués par monban_apply_training_duel().
--
-- Barème : le JOUEUR gagne le duel → +7 (3s, cadence la plus dure) / +5
-- (5s) / +3 (10s, la plus confortable). Le joueur perd (Monban gagne) →
-- AUCUNE pénalité, c'est un pur bonus (demande explicite de Wurmz : "en
-- cas de défaite, pas de perte de points, c'est que du bonus").
-- ═══════════════════════════════════════════════════════════════════

-- Signature/type de retour inchangés (jsonb) depuis monban_daily_training.sql
-- — pas de drop nécessaire, create or replace suffit.
create or replace function public.monban_mark_trained()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); last_date date; is_admin boolean;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select is_admin_user() into is_admin;

  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (uid, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;

  select last_trained_at::date into last_date from monban_profiles where user_id = uid;

  if not coalesce(is_admin, false) and last_date = current_date then
    return jsonb_build_object('ok', false, 'reason', 'already_trained');
  end if;

  update monban_profiles set last_trained_at = now() where user_id = uid;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.monban_mark_trained() to authenticated;

-- Renommage p_monban_won → p_player_won : contrairement au type de retour,
-- Postgres refuse aussi de renommer un paramètre via create or replace
-- (42P13) — drop obligatoire, piège CLAUDE.md étendu au nom des paramètres.
drop function if exists public.monban_apply_training_duel(integer, boolean);

create function public.monban_apply_training_duel(p_cadence integer, p_player_won boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); cur jsonb; new_sr int; gain int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_cadence not in (3,5,10) then raise exception 'cadence invalide: %', p_cadence; end if;

  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (uid, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;

  select profile into cur from monban_profiles where user_id = uid;

  if not p_player_won then
    return jsonb_build_object('ok', true, 'gain', 0, 'skill_rating', coalesce((cur->>'skillRating')::int, 50));
  end if;

  gain := case p_cadence when 3 then 7 when 5 then 5 else 3 end;
  new_sr := least(100, coalesce((cur->>'skillRating')::int, 50) + gain);
  update monban_profiles set profile = jsonb_set(cur, '{skillRating}', to_jsonb(new_sr)) where user_id = uid;
  return jsonb_build_object('ok', true, 'gain', gain, 'skill_rating', new_sr);
end $$;
grant execute on function public.monban_apply_training_duel(integer, boolean) to authenticated;

select 'monban_training_duel OK' as status;
