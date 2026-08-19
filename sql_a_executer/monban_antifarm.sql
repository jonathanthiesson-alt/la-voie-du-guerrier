-- ═══════════════════════════════════════════════════════════════════
-- MONBAN — colmate deux trous de farm trouvés en audit (2026-08-19)
--
-- 1. monban_learn_from_game(p_delta jsonb) faisait `cur || p_delta` SANS
--    AUCUNE vérification serveur : n'importe quel client authentifié
--    pouvait appeler supa.rpc('monban_learn_from_game',{p_delta:
--    {skillRating:100}}) et maxer Monban en un appel, zéro partie jouée.
--    Fix : la RPC prend maintenant un game_id, vérifie côté serveur que
--    l'appelant a bien participé à CETTE partie FINIE et que SON côté
--    (blanc/noir — deux flags séparés, une partie a DEUX joueurs qui
--    doivent chacun pouvoir compter leur propre résultat) n'a pas déjà
--    été compté, et calcule elle-même le +3/-1 — le client ne contrôle
--    plus skillRating, seulement les faiblesses/ouvertures (données
--    qualitatives, enjeu bien moindre qu'un plafond numérique).
--    Piège rencontré en testant : un premier jet utilisait UN SEUL flag
--    "monban_counted" par partie → le second joueur (légitime) qui
--    appelait après le premier se voyait refuser SON propre gain. Une
--    partie a deux joueurs, donc deux flags (monban_counted_white/black).
--
-- 2. monban_apply_training_duel(cadence, player_won) n'avait AUCUNE limite
--    en elle-même — la garde "1×/jour" ne vivait que dans monban_mark_
--    trained(), une fonction SÉPARÉE que rien n'obligeait à appeler
--    avant. On pouvait boucler monban_apply_training_duel(3,true) à
--    l'infini pour +7 par appel. Fix : jeton à usage unique
--    (pending_duel_date) posé par monban_mark_trained() au moment du
--    clic, consommé par monban_apply_training_duel() — sans jeton valide
--    du jour, aucun gain, quel que soit p_player_won. Bypass admin
--    inchangé (is_admin_user()).
-- ═══════════════════════════════════════════════════════════════════

alter table public.online_games add column if not exists monban_counted_white boolean not null default false;
alter table public.online_games add column if not exists monban_counted_black boolean not null default false;
alter table public.monban_profiles add column if not exists pending_duel_date date;

-- ── 1. monban_learn_from_game : signature complètement différente
-- (jsonb → uuid+jsonb+text+numeric+text), donc nouvelle fonction — mais on
-- DOIT explicitement supprimer l'ancienne version exploitable, sinon les
-- deux signatures coexistent et l'ancienne reste appelable.
drop function if exists public.monban_learn_from_game(jsonb);

create function public.monban_learn_from_game(
  p_game_id uuid, p_weaknesses jsonb, p_dominant_weakness text,
  p_dominant_weakness_rate numeric, p_opening_key text
)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  uid uuid := auth.uid(); g record; cur jsonb; my_color text; won boolean;
  gain int; new_sr int; openings jsonb; new_profile jsonb; already boolean;
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
  gain := case when won then 3 else -1 end;

  insert into monban_profiles (user_id, profile, games_learned, updated_at)
    values (uid, '{"skillRating":50,"weaknesses":{"exposure":0,"missedWin":0,"passivity":0},"openings":{}}'::jsonb, 0, now())
    on conflict (user_id) do nothing;
  select profile into cur from monban_profiles where user_id = uid;

  new_sr := greatest(0, least(100, coalesce((cur->>'skillRating')::int, 50) + gain));

  openings := coalesce(cur->'openings', '{}'::jsonb);
  if p_opening_key is not null then
    openings := jsonb_set(openings, array[p_opening_key], to_jsonb(coalesce((openings->>p_opening_key)::int, 0) + 1));
  end if;

  -- skillRating vient du SERVEUR (gain calculé ci-dessus) ; le reste
  -- (faiblesses, ouvertures) reste alimenté par le client, sur le même
  -- modèle "best-effort" que le reste du système (V1, décision O).
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

  return jsonb_build_object('ok', true, 'gain', gain, 'skill_rating', new_sr);
end $$;
grant execute on function public.monban_learn_from_game(uuid, jsonb, text, numeric, text) to authenticated;

-- ── 2. Jeton à usage unique pour le duel d'entraînement.
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

  -- pending_duel_date = jeton "un duel autorisé aujourd'hui, pas encore
  -- consommé" — c'est monban_apply_training_duel() qui le consomme.
  update monban_profiles set last_trained_at = now(), pending_duel_date = current_date where user_id = uid;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.monban_mark_trained() to authenticated;

drop function if exists public.monban_apply_training_duel(integer, boolean);

create function public.monban_apply_training_duel(p_cadence integer, p_player_won boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); cur jsonb; pending date; is_admin boolean; new_sr int; gain int;
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
    -- Jeton consommé qu'on gagne ou qu'on perde le duel — un seul par jour.
    update monban_profiles set pending_duel_date = null where user_id = uid;
  end if;

  if not p_player_won then
    return jsonb_build_object('ok', true, 'gain', 0, 'skill_rating', coalesce((cur->>'skillRating')::int, 50));
  end if;

  gain := case p_cadence when 3 then 7 when 5 then 5 else 3 end;
  new_sr := least(100, coalesce((cur->>'skillRating')::int, 50) + gain);
  update monban_profiles set profile = jsonb_set(cur, '{skillRating}', to_jsonb(new_sr)) where user_id = uid;
  return jsonb_build_object('ok', true, 'gain', gain, 'skill_rating', new_sr);
end $$;
grant execute on function public.monban_apply_training_duel(integer, boolean) to authenticated;

select 'monban_antifarm OK' as status;
