-- ═══════════════════════════════════════════════════════════════════
-- MONBAN — plafond Elo + moyenne mobile (décision Wurmz 2026-08-19)
--
-- Problème : même symétrique, un +K/-K par partie accumulé sans ancrage
-- est une marche aléatoire — rien ne relie skillRating au niveau RÉEL du
-- joueur, et rien ne fait redescendre une série chaude après coup.
--
-- Deux mécanismes combinés :
-- 1. PLAFOND — skillRating ne peut jamais dépasser une valeur dérivée du
--    meilleur Elo réel du joueur (elo_3s/5s/10s). Recalculé et RE-APPLIQUÉ
--    (pas juste "bloque la suite") à chaque événement Monban : si l'Elo a
--    baissé depuis la dernière fois, le stocké est immédiatement ramené au
--    nouveau plafond, pas seulement empêché de monter davantage.
--    Formule V1 (à ajuster avec une vraie flotte de joueurs) :
--    plafond = clamp((meilleur_elo - 800) / 8, 0, 100) — Elo 1200 → 50.
-- 2. MOYENNE MOBILE — remplace les gains/pertes FIXES par une traction
--    proportionnelle à l'écart au but (100 si victoire, 0 si défaite) :
--    new = old + alpha*(cible-old). Les 10-15 dernières parties pèsent,
--    pas tout l'historique — une forme qui ne reflète plus rien s'efface
--    seule. Diminue aussi mécaniquement près des bornes (un gain proche de
--    100 rapporte peu), contrairement à l'ancien +3 fixe qui "collait" au
--    plafond dès qu'on l'approchait.
--
-- Les ASYMÉTRIES voulues explicitement par Wurmz restent INTACTES : le
-- duel d'entraînement ne fait toujours JAMAIS perdre (aucun appel de la
-- moyenne mobile sur une défaite, comportement inchangé) ; la défense ne
-- fait toujours JAMAIS gagner (aucun appel sur une victoire). Seule la
-- MAGNITUDE du mouvement change (proportionnelle, pas un forfait fixe).
-- ═══════════════════════════════════════════════════════════════════

-- ── Plafond partagé, interne (pas exposé côté client) ───────────────
create or replace function public.monban_elo_ceiling(p_user_id uuid)
returns int language plpgsql stable security definer set search_path to 'public' as $$
declare best_elo int;
begin
  select greatest(coalesce(elo_3s,1200), coalesce(elo_5s,1200), coalesce(elo_10s,1200))
    into best_elo from profiles where id = p_user_id;
  if best_elo is null then return 50; end if;
  return greatest(0, least(100, round((best_elo - 800) / 8.0)::int));
end $$;
revoke all on function public.monban_elo_ceiling(uuid) from public, anon, authenticated;

-- ── 1. Parties en ligne réelles : moyenne mobile symétrique (alpha=0.1) ──
create or replace function public.monban_learn_from_game(
  p_game_id uuid, p_weaknesses jsonb, p_dominant_weakness text,
  p_dominant_weakness_rate numeric, p_opening_key text
)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  uid uuid := auth.uid(); g record; cur jsonb; my_color text; won boolean;
  cur_sr int; target int; ceiling int; new_sr int; openings jsonb; new_profile jsonb; already boolean;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into g from online_games
    where id = p_game_id and status = 'finished' and winner is not null
      and (white_player_id = uid or black_player_id = uid);
  if not found then return jsonb_build_object('ok', false, 'reason', 'game_not_found'); end if;

  my_color := case when g.white_player_id = uid then 'white' else 'black' end;
  already := case when my_color = 'white' then coalesce(g.monban_counted_white,false) else coalesce(g.monban_counted_black,false) end;
  if already then return jsonb_build_object('ok', false, 'reason', 'already_counted'); end if;

  won := (g.winner = my_color);

  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (uid, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;
  select profile into cur from monban_profiles where user_id = uid;

  ceiling := monban_elo_ceiling(uid);
  cur_sr := least(coalesce((cur->>'skillRating')::int, 50), ceiling); -- re-synchronise si l'Elo a baissé depuis
  target := case when won then 100 else 0 end;
  new_sr := greatest(0, least(ceiling, round(cur_sr + 0.1*(target - cur_sr))::int));

  openings := coalesce(cur->'openings', '{}'::jsonb);
  if p_opening_key is not null then
    openings := jsonb_set(openings, array[p_opening_key], to_jsonb(coalesce((openings->>p_opening_key)::int, 0) + 1));
  end if;

  new_profile := cur || jsonb_build_object(
    'skillRating', new_sr,
    'openings', openings,
    'weaknesses', coalesce(p_weaknesses, cur->'weaknesses'),
    'dominantWeakness', p_dominant_weakness,
    'dominantWeaknessRate', coalesce(p_dominant_weakness_rate, 0)
  );

  update monban_profiles set profile = new_profile, games_learned = games_learned + 1, updated_at = now()
    where user_id = uid;

  if my_color = 'white' then
    update online_games set monban_counted_white = true where id = p_game_id;
  else
    update online_games set monban_counted_black = true where id = p_game_id;
  end if;

  return jsonb_build_object('ok', true, 'skill_rating', new_sr, 'ceiling', ceiling);
end $$;
grant execute on function public.monban_learn_from_game(uuid, jsonb, text, numeric, text) to authenticated;

-- ── 2. Duel d'entraînement : traction proportionnelle vers 100 sur
-- victoire (alpha selon cadence, plus dur = plus payant), TOUJOURS aucun
-- mouvement sur défaite — asymétrie voulue, inchangée.
create or replace function public.monban_apply_training_duel(p_cadence integer, p_player_won boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  uid uuid := auth.uid(); cur jsonb; pending date; is_admin boolean;
  cur_sr int; ceiling int; alpha numeric; new_sr int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_cadence not in (3,5,10) then raise exception 'cadence invalide: %', p_cadence; end if;

  select is_admin_user() into is_admin;

  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (uid, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;

  select profile, pending_duel_date into cur, pending from monban_profiles where user_id = uid;

  if not coalesce(is_admin, false) then
    if pending is null or pending <> current_date then
      return jsonb_build_object('ok', false, 'reason', 'not_authorized');
    end if;
    update monban_profiles set pending_duel_date = null where user_id = uid;
  end if;

  ceiling := monban_elo_ceiling(uid);
  cur_sr := least(coalesce((cur->>'skillRating')::int, 50), ceiling);
  if cur_sr <> coalesce((cur->>'skillRating')::int, 50) then
    update monban_profiles set profile = jsonb_set(cur, '{skillRating}', to_jsonb(cur_sr)) where user_id = uid;
  end if;

  if not p_player_won then
    return jsonb_build_object('ok', true, 'gain', 0, 'skill_rating', cur_sr);
  end if;

  alpha := case p_cadence when 3 then 0.15 when 5 then 0.10 else 0.07 end;
  new_sr := least(ceiling, round(cur_sr + alpha*(100 - cur_sr))::int);
  update monban_profiles set profile = jsonb_set(cur, '{skillRating}', to_jsonb(new_sr)) where user_id = uid;
  return jsonb_build_object('ok', true, 'gain', new_sr - cur_sr, 'skill_rating', new_sr);
end $$;
grant execute on function public.monban_apply_training_duel(integer, boolean) to authenticated;

-- ── 3. Défense perdue : traction proportionnelle vers 0, TOUJOURS aucun
-- mouvement sur victoire — asymétrie voulue, inchangée.
create or replace function public.monban_apply_defense_loss(p_user_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare cur jsonb; cur_sr int; ceiling int; new_sr int;
begin
  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (p_user_id, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;
  select profile into cur from monban_profiles where user_id = p_user_id;

  ceiling := monban_elo_ceiling(p_user_id);
  cur_sr := least(coalesce((cur->>'skillRating')::int, 50), ceiling);
  new_sr := greatest(0, round(cur_sr + 0.08*(0 - cur_sr))::int);
  update monban_profiles set profile = jsonb_set(cur, '{skillRating}', to_jsonb(new_sr)) where user_id = p_user_id;
end $$;
revoke all on function public.monban_apply_defense_loss(uuid) from public, anon, authenticated;

select 'monban_elo_anchor OK' as status;
