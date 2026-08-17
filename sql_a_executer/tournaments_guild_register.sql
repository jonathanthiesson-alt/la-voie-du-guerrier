-- ═══════════════════════════════════════════════════════════════════
-- TOURNOIS DE GUILDE — active enfin l'inscription (Lot C guilde, jamais
-- terminé dans tournaments_v4_admin.sql).
--
-- Constat (bilan mode Guilde, 2026-08-17) : tournament_register()
-- refusait TOUJOURS l'inscription pour un tournoi kind='guild' (bloc
-- « Lot C guilde ») et aucune autre RPC ne permettait d'y entrer — un
-- admin pouvait créer et lister ce type de tournoi, mais personne ne
-- pouvait jamais s'y inscrire. Coquille vide, pas juste une ambiguïté
-- de nom.
--
-- Choix retenu (le plus simple qui rend le mode réellement jouable
-- sans inventer un second système de score) : un tournoi de guilde
-- fonctionne EXACTEMENT comme un tournoi individuel (système suisse,
-- appariement, score par victoire) — seule l'inscription change :
-- réservée aux joueurs qui appartiennent à UNE guilde, quelle qu'elle
-- soit (pas de restriction sur une guilde précise). Si un jour un
-- vrai scoring collectif par guilde est voulu, ce sera un lot à part.
--
-- Réécrit tournament_register (tournaments_v4_admin.sql) — même
-- signature, simple create or replace, idempotent.
-- ═══════════════════════════════════════════════════════════════════

create or replace function tournament_register(p_tournament_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); t record; cnt int; sub boolean; my_guild bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into t from tournaments where id = p_tournament_id;
  if t is null then raise exception 'tournament not found'; end if;
  if t.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'closed'); end if;

  -- Fenêtre d'inscription (si renseignée).
  if t.registration_opens_at is not null and now() < t.registration_opens_at then
    return jsonb_build_object('ok', false, 'reason', 'not_open_yet');
  end if;
  if t.registration_closes_at is not null and now() > t.registration_closes_at then
    return jsonb_build_object('ok', false, 'reason', 'registration_closed');
  end if;

  -- Public réservé.
  if t.audience in ('subscriber','freemium') then
    select coalesce(is_subscriber,false) into sub from profiles where id = uid;
    if t.audience = 'subscriber' and not sub then
      return jsonb_build_object('ok', false, 'reason', 'subscriber_only');
    end if;
    if t.audience = 'freemium' and sub then
      return jsonb_build_object('ok', false, 'reason', 'freemium_only');
    end if;
  end if;

  -- Type guilde : inscription individuelle réservée aux membres d'UNE guilde
  -- (n'importe laquelle). Le reste du parcours (score, rondes, récompenses)
  -- est identique à un tournoi individuel.
  if t.kind = 'guild' then
    select guild_id into my_guild from guild_members where player_id = uid;
    if my_guild is null then
      return jsonb_build_object('ok', false, 'reason', 'not_in_guild');
    end if;
  end if;

  select count(*) into cnt from tournament_participants where tournament_id = p_tournament_id;
  if cnt >= coalesce(t.max_players,32) then
    return jsonb_build_object('ok', false, 'reason', 'full', 'max_players', t.max_players);
  end if;

  insert into tournament_participants(tournament_id, player_id)
    values (p_tournament_id, uid) on conflict (tournament_id, player_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- ── Contrôle ───────────────────────────────────────────────────────
select to_regproc('public.tournament_register')::text as fn_register, -- attendu non-null
  'tournaments_guild_register OK' as status;
