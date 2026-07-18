-- ═══════════════════════════════════════════════════════════════════
-- Guildes v3 — les défis inter-guildes doivent être ACCEPTÉS.
--
-- Constat du test à 2 comptes (2026-07-18) : un défi lancé démarrait
-- immédiatement en 'active', sans que la guilde défiée ne soit prévenue
-- ni consultée — « j'ai envoyé un défi, puis rien ne se passe ».
--
-- Nouveau cycle de vie :
--   pending  → créé par le chef A (guild_challenge) ; AUCUN point ne
--              compte encore (guild_report_win ne regarde que 'active').
--   active   → le chef B accepte (guild_challenge_respond) ; 48 h
--              démarrent À L'ACCEPTATION.
--   declined → le chef B refuse.
--   expired  → 48 h sans réponse (nettoyage pg_cron).
--   finished → clôture automatique du défi actif (+30 Ryu au gagnant).
--
-- Idempotent. À exécuter en une fois dans l'éditeur SQL Supabase.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Le défi part désormais en 'pending', sans deadline (elle n'est
--    posée qu'à l'acceptation). Même signature → simple replace.
create or replace function public.guild_challenge(p_target_guild bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); g bigint; myrole text; already int; tid bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id, role into g, myrole from guild_members where player_id = uid;
  if g is null then return jsonb_build_object('ok', false, 'reason', 'not_in_guild'); end if;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if p_target_guild = g then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  if not exists (select 1 from guilds where id = p_target_guild) then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  -- Un seul défi en vie (en attente OU actif) par guilde impliquée.
  select count(*) into already from guild_tournaments
    where status in ('pending','active') and (guild_a in (g, p_target_guild) or guild_b in (g, p_target_guild));
  if already > 0 then return jsonb_build_object('ok', false, 'reason', 'busy'); end if;
  insert into guild_tournaments(guild_a, guild_b, status)
    values (g, p_target_guild, 'pending')
    returning id into tid;
  return jsonb_build_object('ok', true, 'id', tid);
end $function$;

grant execute on function public.guild_challenge(bigint) to authenticated;

-- 2. Réponse au défi — chef de la guilde DÉFIÉE (guild_b) uniquement.
create or replace function public.guild_challenge_respond(p_challenge_id bigint, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); g bigint; myrole text; t record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id, role into g, myrole from guild_members where player_id = uid;
  if g is null then return jsonb_build_object('ok', false, 'reason', 'not_in_guild'); end if;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  select * into t from guild_tournaments where id = p_challenge_id for update;
  if t is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if t.guild_b is distinct from g then return jsonb_build_object('ok', false, 'reason', 'not_target'); end if;
  if t.status is distinct from 'pending' then return jsonb_build_object('ok', false, 'reason', 'not_pending'); end if;
  if p_accept then
    -- Les 48 h démarrent maintenant, pas à l'envoi du défi.
    update guild_tournaments set status = 'active', deadline = now() + interval '48 hours'
      where id = p_challenge_id;
  else
    update guild_tournaments set status = 'declined' where id = p_challenge_id;
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept);
end $function$;

grant execute on function public.guild_challenge_respond(bigint, boolean) to authenticated;

-- 3. Nettoyage : en plus de clore les défis actifs échus (+30 Ryu),
--    on expire les défis restés sans réponse 48 h.
create or replace function public.guild_challenges_cleanup()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare t record; n int := 0; w bigint; e int := 0;
begin
  for t in select * from guild_tournaments where status = 'active' and deadline is not null and now() >= deadline loop
    w := case when t.score_a > t.score_b then t.guild_a
              when t.score_b > t.score_a then t.guild_b
              else null end;   -- égalité : pas de gagnant
    update guild_tournaments set status = 'finished', winner_guild = w where id = t.id;
    if w is not null then
      update guilds set ryu_total = ryu_total + 30 where id = w;
    end if;
    n := n + 1;
  end loop;
  update guild_tournaments set status = 'expired'
    where status = 'pending' and created_at < now() - interval '48 hours';
  get diagnostics e = row_count;
  return jsonb_build_object('closed', n, 'expired', e);
end $function$;

-- (le tick pg_cron 'guild_challenges_tick' existe déjà — guilds_v2.sql —
--  et appelle cette fonction : rien à replanifier.)

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regproc('public.guild_challenge')::text          as fn_challenge,
  to_regproc('public.guild_challenge_respond')::text  as fn_respond,   -- attendu non-null
  (select count(*) from cron.job where jobname='guild_challenges_tick') as tick;  -- attendu 1
