-- ═══════════════════════════════════════════════════════════════════
-- CLASSEMENT DES GUILDES — lot G7, docs/ROADMAP_GUILD_BATTLE.md § 7
--
-- Refonte du classement : `v_guild_leaderboard` triait sur `ryu_total`,
-- un cumul qui ne descend jamais (une vieille guilde inactive y domine
-- indéfiniment). Décisions AE/AF/AL : le tri passe à un Elo de guilde
-- (`guilds.guild_elo`, défaut 1200, même formule que l'Elo joueur), le Ryu
-- redevient une trésorerie pure (affiché, mais ne pilote plus le rang).
--
-- Ce qui fait bouger l'Elo de guilde à ce stade (décisions AJ/AK) :
--  - Attaque de guilde (lot G8, à venir) : effet plein.
--  - Défi guilde 48h (guild_tournaments, DÉJÀ EN PROD) : moitié moins —
--    c'est donc le SEUL événement qui peut réellement le faire bouger
--    avant que G8 existe. `guild_elo_apply_result()` est écrite une fois,
--    pondérée par un paramètre de poids, pour que G8 la réutilise telle
--    quelle avec un poids de 1.0 au lieu de 0.5.
-- ═══════════════════════════════════════════════════════════════════

alter table public.guilds add column if not exists guild_elo int not null default 1200;

-- create or replace view ne peut pas réordonner/ajouter des colonnes au
-- milieu — drop obligatoire avant de recréer (piège CLAUDE.md).
drop view if exists public.v_guild_leaderboard;
create view public.v_guild_leaderboard as
  select id, name, tag, join_mode, ryu_total, guild_elo,
    (select count(*) from guild_members gm where gm.guild_id = g.id) as members
  from guilds g
  order by guild_elo desc;

-- ── Applique un résultat à l'Elo de deux guildes (formule Elo standard,
-- même famille que computeNewElo() côté joueur — K=32 pour une guilde,
-- pas de K provisoire car il n'y a pas de "guildes débutantes" à
-- distinguer). L'écart de score sert de marge de victoire : un score
-- serré rapproche le résultat effectif de 0.5 (peu de mouvement), un
-- score écrasant s'approche de 1 (mouvement plein). p_weight pondère le
-- résultat final : 1.0 pour une Attaque (G8), 0.5 pour un Défi guilde
-- 48h (décision AK) — jamais négatif pour le vainqueur (un vainqueur ne
-- perd jamais de points, même très à l'avantage de l'adversaire).
create or replace function public.guild_elo_apply_result(p_winner_guild bigint, p_loser_guild bigint, p_score_winner numeric, p_score_loser numeric, p_weight numeric default 1.0)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare elo_w int; elo_l int; total numeric; margin numeric; expected numeric; delta int;
begin
  select guild_elo into elo_w from guilds where id = p_winner_guild;
  select guild_elo into elo_l from guilds where id = p_loser_guild;
  if elo_w is null or elo_l is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;

  total := greatest(p_score_winner + p_score_loser, 1);
  margin := 0.5 + 0.5 * least(1.0, abs(p_score_winner - p_score_loser) / total);
  expected := 1.0 / (1.0 + power(10, (elo_l - elo_w) / 400.0));
  delta := round(32 * (margin - expected) * p_weight);
  if delta < 0 then delta := 0; end if;

  update guilds set guild_elo = greatest(100, elo_w + delta) where id = p_winner_guild;
  update guilds set guild_elo = greatest(100, elo_l - delta) where id = p_loser_guild;
  return jsonb_build_object('ok', true, 'delta', delta, 'winner_elo', elo_w + delta, 'loser_elo', greatest(100, elo_l - delta));
end $$;
revoke all on function public.guild_elo_apply_result(bigint, bigint, numeric, numeric, numeric) from public;

-- ── guild_challenges_cleanup : branche l'Elo de guilde sur le Défi 48h ──
-- (reprend le corps de guild_journal.sql tel quel, ajoute simplement
-- l'appel à guild_elo_apply_result avec un poids de 0.5 — décision AK.)
create or replace function public.guild_challenges_cleanup()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare t record; n int := 0; w bigint; e int := 0; name_a text; name_b text; loser bigint; elo_res jsonb;
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

      elo_res := guild_elo_apply_result(w, loser, greatest(t.score_a, t.score_b), least(t.score_a, t.score_b), 0.5);

      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_war_won', '🏆 Défi remporté !',
        'Votre guilde a battu ' || coalesce(name_b,'la guilde adverse') || ' ('||t.score_a||' - '||t.score_b||') — +30 🐉'
          || (case when elo_res is not null and (elo_res->>'delta')::int > 0 then ' et +'||(elo_res->>'delta')||' Elo de guilde' else '' end) || ' !',
        false, jsonb_build_object('challenge_id', t.id)
      from guild_members gm where gm.guild_id = w;

      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_war_lost', '💀 Défi perdu',
        coalesce(name_a,'La guilde adverse') || ' a remporté le défi ('||t.score_a||' - '||t.score_b||').',
        false, jsonb_build_object('challenge_id', t.id)
      from guild_members gm where gm.guild_id = loser;

      perform guild_journal_log(w, 'guild_war_result', null, null, '🏆 Victoire contre ' || coalesce(name_b,'la guilde adverse') || ' (' || t.score_a || ' - ' || t.score_b || ') — +30 🐉.');
      perform guild_journal_log(loser, 'guild_war_result', null, null, '💀 Défaite contre ' || coalesce(name_a,'la guilde adverse') || ' (' || t.score_a || ' - ' || t.score_b || ').');
    else
      insert into notifications(user_id, type, title, body, read, payload)
      select gm.player_id, 'guild_war_draw', '⚔ Défi terminé — égalité',
        'Le défi s''est conclu à égalité ('||t.score_a||' - '||t.score_b||'). Personne ne remporte le Ryu.',
        false, jsonb_build_object('challenge_id', t.id)
      from guild_members gm where gm.guild_id in (t.guild_a, t.guild_b);

      perform guild_journal_log(t.guild_a, 'guild_war_result', null, null, '⚔ Défi terminé à égalité (' || t.score_a || ' - ' || t.score_b || ').');
      perform guild_journal_log(t.guild_b, 'guild_war_result', null, null, '⚔ Défi terminé à égalité (' || t.score_a || ' - ' || t.score_b || ').');
    end if;
    n := n + 1;
  end loop;
  update guild_tournaments set status = 'expired'
    where status = 'pending' and created_at < now() - interval '48 hours';
  return jsonb_build_object('closed', n);
end $$;

-- ── get_my_guild() : expose guild_elo à l'écran de guilde (header) ──────
-- (reprend le corps de guild_ranks.sql tel quel, ajoute juste 'guild_elo'
-- dans le jsonb_build_object — sinon le client ne peut pas afficher l'Elo
-- de SA PROPRE guilde, seulement celui des autres via v_guild_leaderboard.)
create or replace function public.get_my_guild()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); g record; members jsonb; requests jsonb; myrole text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.role into myrole from guild_members gm where gm.player_id = uid;
  if myrole is null then return jsonb_build_object('in_guild', false); end if;
  select gu.* into g from guilds gu join guild_members gm on gm.guild_id = gu.id where gm.player_id = uid;
  select coalesce(jsonb_agg(row_to_json(x)),'[]'::jsonb) into members from (
    select pr.pseudo, gm.role, gm.contributed_ryu, gm.player_id
    from guild_members gm join profiles pr on pr.id = gm.player_id
    where gm.guild_id = g.id order by gm.contributed_ryu desc
  ) x;
  requests := '[]'::jsonb;
  if myrole = 'leader' then
    select coalesce(jsonb_agg(row_to_json(y)),'[]'::jsonb) into requests from (
      select gr.id, pr.pseudo, gr.player_id
      from guild_requests gr join profiles pr on pr.id = gr.player_id
      where gr.guild_id = g.id order by gr.created_at asc
    ) y;
  end if;
  return jsonb_build_object('in_guild', true, 'guild',
    jsonb_build_object('id',g.id,'name',g.name,'tag',g.tag,'join_mode',g.join_mode,'ryu_total',g.ryu_total,'guild_elo',g.guild_elo,
      'banner',g.banner,'devise',g.devise,'info_message',g.info_message,'info_message_at',g.info_message_at,
      'rank_names',g.rank_names,'rank_permissions',g.rank_permissions),
    'my_role', myrole, 'members', members, 'requests', requests);
end $function$;

-- ── guild_roster() : expose guild_elo au roster public d'une AUTRE guilde
create or replace function public.guild_roster(p_guild_id bigint)
 returns jsonb
 language sql
 security definer
 set search_path to 'public'
as $function$
  select jsonb_build_object(
    'guild', (select jsonb_build_object('id', id, 'name', name, 'tag', tag,
                'join_mode', join_mode, 'ryu_total', ryu_total, 'guild_elo', guild_elo,
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

-- ── Contrôle ───────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns where table_name='guilds' and column_name='guild_elo') as col_guild_elo, -- attendu 1
  to_regproc('public.guild_elo_apply_result')::text as fn_elo_apply,   -- attendu non-null
  to_regproc('public.guild_challenges_cleanup')::text as fn_cleanup,   -- attendu non-null
  to_regclass('public.v_guild_leaderboard')::text as view_leaderboard, -- attendu non-null
  'guild_events_g7_elo OK' as status;
