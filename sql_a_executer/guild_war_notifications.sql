-- ═══════════════════════════════════════════════════════════════════
-- GUERRE DE GUILDE — notifications d'acceptation et de résolution
--
-- Constat (bilan mode Guilde) : aucun signal pour les membres quand un
-- défi qu'ils ont lancé vient d'être accepté, ni quand un défi se
-- conclut (victoire/défaite/égalité) — il fallait revenir consulter
-- l'écran Guilde > Défis inter-guildes pour le savoir.
--
-- Cible : TOUS les membres des deux guildes concernées (pas que le
-- chef) — c'est un effort collectif, chaque victoire classée d'un
-- membre compte pour le score du défi.
--
-- Réécrit guild_challenge_respond (guilds_v3.sql) et
-- guild_challenges_cleanup (guilds_v3.sql) — même signature, simple
-- create or replace, idempotent. À exécuter après guilds_v3.sql.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Acceptation d'un défi → notif à tous les membres des DEUX guildes :
--    la guerre commence.
create or replace function public.guild_challenge_respond(p_challenge_id bigint, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid(); g bigint; myrole text; t record;
  name_a text; name_b text;
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
    update guild_tournaments set status = 'active', deadline = now() + interval '48 hours'
      where id = p_challenge_id;

    select name into name_a from guilds where id = t.guild_a;
    select name into name_b from guilds where id = t.guild_b;

    insert into notifications(user_id, type, title, body, read, payload)
    select gm.player_id, 'guild_war_accepted', '⚔ La guerre commence !',
      coalesce(name_b,'La guilde adverse') || ' a accepté votre défi — 48 h pour marquer plus de victoires classées qu''eux.',
      false, jsonb_build_object('challenge_id', t.id, 'opponent_guild', t.guild_b)
    from guild_members gm where gm.guild_id = t.guild_a;

    insert into notifications(user_id, type, title, body, read, payload)
    select gm.player_id, 'guild_war_accepted', '⚔ La guerre commence !',
      'Votre chef a accepté le défi de ' || coalesce(name_a,'une guilde rivale') || ' — 48 h pour marquer plus de victoires classées qu''eux.',
      false, jsonb_build_object('challenge_id', t.id, 'opponent_guild', t.guild_a)
    from guild_members gm where gm.guild_id = t.guild_b;
  else
    update guild_tournaments set status = 'declined' where id = p_challenge_id;
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept);
end $function$;

grant execute on function public.guild_challenge_respond(bigint, boolean) to authenticated;

-- 2. Clôture d'un défi → notif à tous les membres des DEUX guildes :
--    victoire / défaite / égalité.
create or replace function public.guild_challenges_cleanup()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare t record; n int := 0; w bigint; e int := 0; name_a text; name_b text; loser bigint;
begin
  for t in select * from guild_tournaments where status = 'active' and deadline is not null and now() >= deadline loop
    w := case when t.score_a > t.score_b then t.guild_a
              when t.score_b > t.score_a then t.guild_b
              else null end;   -- égalité : pas de gagnant
    update guild_tournaments set status = 'finished', winner_guild = w where id = t.id;
    if w is not null then
      update guilds set ryu_total = ryu_total + 30 where id = w;

      loser := case when w = t.guild_a then t.guild_b else t.guild_a end;
      select name into name_a from guilds where id = w;
      select name into name_b from guilds where id = loser;

      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_war_won', '🏆 Défi remporté !',
        'Votre guilde a battu ' || coalesce(name_b,'la guilde adverse') || ' ('||t.score_a||' - '||t.score_b||') — +30 🐉 pour la guilde !',
        false, jsonb_build_object('challenge_id', t.id)
      from guild_members gm where gm.guild_id = w;

      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_war_lost', '💀 Défi perdu',
        coalesce(name_a,'La guilde adverse') || ' a remporté le défi ('||t.score_a||' - '||t.score_b||').',
        false, jsonb_build_object('challenge_id', t.id)
      from guild_members gm where gm.guild_id = loser;
    else
      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_war_draw', '⚔ Défi terminé — égalité',
        'Le défi s''est conclu à égalité ('||t.score_a||' - '||t.score_b||'). Personne ne remporte le Ryu.',
        false, jsonb_build_object('challenge_id', t.id)
      from guild_members gm where gm.guild_id in (t.guild_a, t.guild_b);
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
  to_regproc('public.guild_challenge_respond')::text   as fn_respond,   -- attendu non-null
  to_regproc('public.guild_challenges_cleanup')::text   as fn_cleanup,  -- attendu non-null
  'guild_war_notifications OK' as status;
