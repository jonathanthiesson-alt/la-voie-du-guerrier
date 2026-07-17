-- ═══════════════════════════════════════════════════════════════════
-- Guildes v2 — bouche la faille Ryu et rend les défis inter-guildes
-- réellement fonctionnels.
--
-- Constat de l'audit (2026-07-14) :
--   1. guild_contribute_ryu(p_amount) acceptait un montant ARBITRAIRE
--      du client (triche illimitée) — et n'était de toute façon jamais
--      appelé : le Ryu n'était jamais gagné.
--   2. guild_tournaments : les scores n'étaient jamais écrits, le
--      statut jamais clos, et la policy INSERT permettait à n'importe
--      quel membre de créer un défi par écriture directe.
--
-- Fonctionnement mis en place :
--   · Chaque victoire EN LIGNE CLASSÉE d'un membre rapporte +2 Ryu
--     (perso + total de guilde), via guild_report_win(p_game_id) qui
--     VÉRIFIE la partie en base (finie, gagnée par l'appelant, classée,
--     pas déjà comptée) — rien n'est laissé au déclaratif client.
--   · Si un défi inter-guildes est actif, la même victoire ajoute +1
--     au score du camp du joueur.
--   · Un défi dure 48 h ; seul le CHEF peut défier ; clôture
--     automatique par pg_cron (+30 Ryu de prime à la guilde gagnante).
--
-- À exécuter en une fois dans l'éditeur SQL Supabase.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Suppression de la faille : le RPC à montant libre disparaît.
drop function if exists public.guild_contribute_ryu(integer);

-- 2. Une victoire ne doit être comptée qu'UNE fois (les deux clients
--    appellent le report en fin de partie, comme pour les tournois).
alter table public.online_games
  add column if not exists guild_counted boolean not null default false;

-- 3. Cycle de vie des défis.
alter table public.guild_tournaments
  add column if not exists deadline timestamptz;
alter table public.guild_tournaments
  add column if not exists winner_guild bigint;

-- L'INSERT direct client est fermé : la création passe par le RPC
-- guild_challenge (chef uniquement).
drop policy if exists guild_tournaments_insert on public.guild_tournaments;

-- 4. Défier une autre guilde — chef uniquement, un seul défi actif à la
--    fois par guilde, 48 h.
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
  select count(*) into already from guild_tournaments
    where status = 'active' and (guild_a in (g, p_target_guild) or guild_b in (g, p_target_guild));
  if already > 0 then return jsonb_build_object('ok', false, 'reason', 'busy'); end if;
  insert into guild_tournaments(guild_a, guild_b, status, deadline)
    values (g, p_target_guild, 'active', now() + interval '48 hours')
    returning id into tid;
  return jsonb_build_object('ok', true, 'id', tid);
end $function$;

grant execute on function public.guild_challenge(bigint) to authenticated;

-- 5. Report d'une victoire — SERVEUR-AUTORITAIRE : tout est vérifié sur
--    la ligne de partie, le client ne fournit que l'identifiant.
create or replace function public.guild_report_win(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); gm record; game record; amount int := 2; t record; my_side text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id into gm from guild_members where player_id = uid;
  if gm.guild_id is null then return jsonb_build_object('ok', false, 'reason', 'not_in_guild'); end if;

  select * into game from online_games where id = p_game_id for update;
  if game is null then return jsonb_build_object('ok', false, 'reason', 'game_not_found'); end if;
  if game.guild_counted then return jsonb_build_object('ok', true, 'already', true); end if;
  if game.status is distinct from 'finished' or game.winner is null then
    return jsonb_build_object('ok', false, 'reason', 'not_finished');
  end if;
  if coalesce(game.ranked, true) = false then
    return jsonb_build_object('ok', false, 'reason', 'friendly');
  end if;
  -- L'appelant doit être LE gagnant de cette partie.
  if not ((game.winner = 'white' and game.white_player_id = uid)
       or (game.winner = 'black' and game.black_player_id = uid)) then
    return jsonb_build_object('ok', false, 'reason', 'not_winner');
  end if;

  update online_games set guild_counted = true where id = p_game_id;

  update guilds set ryu_total = ryu_total + amount where id = gm.guild_id;
  update guild_members set contributed_ryu = contributed_ryu + amount where player_id = uid;
  update profiles set ryu_balance = ryu_balance + amount where id = uid;

  -- Défi actif ? La victoire marque un point pour mon camp.
  select * into t from guild_tournaments
    where status = 'active' and (guild_a = gm.guild_id or guild_b = gm.guild_id)
    order by created_at desc limit 1;
  if t.id is not null and (t.deadline is null or now() < t.deadline) then
    if t.guild_a = gm.guild_id then
      update guild_tournaments set score_a = score_a + 1 where id = t.id;
      my_side := 'a';
    else
      update guild_tournaments set score_b = score_b + 1 where id = t.id;
      my_side := 'b';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'ryu', amount, 'defi_point', my_side is not null);
end $function$;

grant execute on function public.guild_report_win(uuid) to authenticated;

-- 6. Clôture automatique des défis expirés (+30 Ryu à la guilde
--    gagnante). Appelée par pg_cron toutes les minutes.
create or replace function public.guild_challenges_cleanup()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare t record; n int := 0; w bigint;
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
  return jsonb_build_object('closed', n);
end $function$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'guild_challenges_tick') then
    perform cron.unschedule('guild_challenges_tick');
  end if;
end $$;

select cron.schedule('guild_challenges_tick', '60 seconds', $$select public.guild_challenges_cleanup();$$);
