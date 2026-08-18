-- ═══════════════════════════════════════════════════════════════════
-- ENTRAÎNEMENT QUOTIDIEN DE MONBAN — complète la décision O
-- (docs/ROADMAP_PUZZLE_INVASION.md § E/O)
--
-- monban_mark_trained() existait déjà (monban_core.sql) mais ne posait
-- qu'un timestamp, sans limite ni effet réel — un rituel décoratif. Ce
-- script lui donne un vrai effet (+2 skillRating, même ordre de grandeur
-- qu'une victoire en ligne qui donne +3 — décision confirmée par Wurmz
-- le 2026-08-18) et une vraie limite (1×/jour), avec la même convention
-- de bornage calendaire que record_daily_first_win (current_date, pas de
-- fenêtre glissante de 24h).
--
-- Débridage admin (Wurmz/Musashi) : entraînements illimités pour les
-- tests, même patron que les invasions/attaques de guilde — is_admin_user()
-- uniquement, jamais une liste de pseudos en dur.
-- ═══════════════════════════════════════════════════════════════════

-- Le type de retour change (void → jsonb) : drop obligatoire avant de
-- recréer (piège CLAUDE.md, create or replace échoue en 42P13).
drop function if exists public.monban_mark_trained();

create function public.monban_mark_trained()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); cur jsonb; last_date date; new_sr int; is_admin boolean;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select is_admin_user() into is_admin;

  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (uid, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;

  select profile, last_trained_at::date into cur, last_date from monban_profiles where user_id = uid;

  if not coalesce(is_admin, false) and last_date = current_date then
    return jsonb_build_object('ok', false, 'reason', 'already_trained');
  end if;

  new_sr := least(100, coalesce((cur->>'skillRating')::int, 50) + 2);
  update monban_profiles set
    profile = jsonb_set(cur, '{skillRating}', to_jsonb(new_sr)),
    last_trained_at = now()
    where user_id = uid;

  return jsonb_build_object('ok', true, 'skill_rating', new_sr);
end $$;
grant execute on function public.monban_mark_trained() to authenticated;

select 'monban_daily_training OK' as status;
