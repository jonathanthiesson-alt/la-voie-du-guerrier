-- ═══════════════════════════════════════════════════════════════════
-- JOURNAL DE GUILDE — lot G1, docs/ROADMAP_GUILD_BATTLE.md § 7 (décision U)
--
-- « Un journal des choses qui se passent dans la guilde » — toute la vie de
-- la guilde : arrivées, départs, exclusions, changements de grade,
-- déclarations/résolutions de Défi inter-guildes. Livrable et utile seul,
-- indépendamment du reste du chantier Combat de guilde (rien d'autre n'est
-- codé à ce stade).
--
-- ⚠ À NE PAS CONFONDRE avec `player_journal` (V0.87.0, table déjà existante,
-- journal PERSONNEL d'un joueur, écrit directement par le client via
-- logJournalEvent()). Le journal de guilde est un historique COLLECTIF,
-- partagé par tous les membres — il ne peut donc PAS être écrit par le
-- client (n'importe quel membre pourrait alors y insérer n'importe quoi).
-- Toute écriture passe par guild_journal_log(), une fonction INTERNE
-- (EXECUTE révoqué pour authenticated, même patron que invasion_resolve_
-- internal) appelée depuis l'intérieur des RPC de guilde déjà existantes,
-- elles-mêmes SECURITY DEFINER.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.guild_journal (
  id         bigint generated always as identity primary key,
  guild_id   bigint not null references public.guilds(id) on delete cascade,
  created_at timestamptz not null default now(),
  event_type text not null,
  actor_id   uuid references public.profiles(id),
  target_id  uuid references public.profiles(id),
  message    text not null
);
create index if not exists guild_journal_guild_idx on public.guild_journal(guild_id, created_at desc);

alter table public.guild_journal enable row level security;
drop policy if exists guild_journal_select_members on public.guild_journal;
create policy guild_journal_select_members on public.guild_journal
  for select using (exists (
    select 1 from guild_members gm where gm.guild_id = guild_journal.guild_id and gm.player_id = auth.uid()
  ));
-- Aucune politique INSERT/UPDATE/DELETE : écriture exclusivement via
-- guild_journal_log() (SECURITY DEFINER, appelée en interne).
--
-- 🔴 BUG DE PRODUCTION DÉCOUVERT PENDANT LE TEST (indépendant du journal) :
-- guild_join()/guild_approve() insérait encore role='member', mais la
-- contrainte guild_members_role_check (posée par guild_ranks.sql, déjà
-- exécuté) n'autorise plus QUE 'leader'/'g1'/'g2'/'g3'/'g4'. Conséquence :
-- personne ne peut plus rejoindre une guilde depuis l'exécution de
-- guild_ranks.sql — ni en direct (guilde ouverte), ni via validation du
-- chef (guild_approve), l'insertion lève une exception Postgres brute que
-- le client affiche comme un « Erreur. » générique. Confirmé en base :
-- guild_members ne contient AUCUNE ligne role='member' (0), toutes les
-- lignes non-chef sont déjà 'g4' — cohérent avec des membres insérés
-- directement en SQL (fixtures « Les Quinze ») plutôt que via ces RPC.
-- Corrigé ci-dessous : role='g4' (grade par défaut le plus bas) au lieu de
-- 'member'.

-- ── Écriture interne (jamais appelable directement par un client) ──────
create or replace function public.guild_journal_log(p_guild_id bigint, p_event_type text, p_actor_id uuid, p_target_id uuid, p_message text)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  insert into guild_journal(guild_id, event_type, actor_id, target_id, message)
    values (p_guild_id, p_event_type, p_actor_id, p_target_id, p_message);
end; $$;
revoke execute on function public.guild_journal_log(bigint, text, uuid, uuid, text) from public, authenticated;

-- ── guild_create : fondation ────────────────────────────────────────────
create or replace function public.guild_create(p_name text, p_tag text, p_join_mode text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; already int; v_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select count(*) into already from guild_members where player_id = uid;
  if already > 0 then return jsonb_build_object('ok', false, 'reason', 'already_in_guild'); end if;
  insert into guilds(name, tag, join_mode, created_by)
    values (p_name, coalesce(nullif(p_tag,''), left(p_name,3)), coalesce(p_join_mode,'open'), uid)
    returning id into gid;
  insert into guild_members(guild_id, player_id, role) values (gid, uid, 'leader');
  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  perform guild_journal_log(gid, 'guild_created', uid, null, '🏯 Guilde fondée par ' || coalesce(v_pseudo,'un joueur') || '.');
  return jsonb_build_object('ok', true, 'guild_id', gid);
end $$;

-- ── guild_join : arrivée directe (guilde ouverte) ──────────────────────
create or replace function public.guild_join(p_guild_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); mode text; already int; cnt int; v_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select count(*) into already from guild_members where player_id = uid;
  if already > 0 then return jsonb_build_object('ok', false, 'reason', 'already_in_guild'); end if;
  select join_mode into mode from guilds where id = p_guild_id;
  if mode is null then raise exception 'guild not found'; end if;
  select count(*) into cnt from guild_members where guild_id = p_guild_id;
  if cnt >= 20 then return jsonb_build_object('ok', false, 'reason', 'full'); end if;
  if mode = 'open' then
    insert into guild_members(guild_id, player_id, role) values (p_guild_id, uid, 'g4');
    select p.pseudo into v_pseudo from profiles p where p.id = uid;
    perform guild_journal_log(p_guild_id, 'guild_joined', uid, null, '🚪 ' || coalesce(v_pseudo,'Un joueur') || ' a rejoint la guilde.');
    return jsonb_build_object('ok', true, 'joined', true);
  else
    insert into guild_requests(guild_id, player_id) values (p_guild_id, uid)
      on conflict (guild_id, player_id) do nothing;
    return jsonb_build_object('ok', true, 'requested', true);
  end if;
end $$;

-- ── guild_approve : arrivée validée par le chef (guilde sur demande) ──
create or replace function public.guild_approve(p_request_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); req record; myrole text; cnt int; v_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into req from guild_requests where id = p_request_id;
  if req is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select role into myrole from guild_members where guild_id = req.guild_id and player_id = uid;
  if myrole is distinct from 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  select count(*) into cnt from guild_members where guild_id = req.guild_id;
  if cnt >= 20 then return jsonb_build_object('ok', false, 'reason', 'full'); end if;
  insert into guild_members(guild_id, player_id, role) values (req.guild_id, req.player_id, 'g4')
    on conflict (player_id) do nothing;
  delete from guild_requests where id = p_request_id;
  select p.pseudo into v_pseudo from profiles p where p.id = req.player_id;
  perform guild_journal_log(req.guild_id, 'guild_joined', req.player_id, null, '🚪 ' || coalesce(v_pseudo,'Un joueur') || ' a rejoint la guilde.');
  return jsonb_build_object('ok', true);
end $$;

-- ── guild_leave : départ (+ promotion éventuelle) ──────────────────────
create or replace function public.guild_leave()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); g bigint; myrole text; nextm uuid; v_pseudo text; v_next_pseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select guild_id, role into g, myrole from guild_members where player_id = uid;
  if g is null then return jsonb_build_object('ok', false, 'reason', 'not_in_guild'); end if;
  select p.pseudo into v_pseudo from profiles p where p.id = uid;
  delete from guild_members where player_id = uid;
  -- Si le chef part, on promeut le plus ancien membre restant.
  if myrole = 'leader' then
    select player_id into nextm from guild_members where guild_id = g order by joined_at asc limit 1;
    if nextm is not null then
      update guild_members set role = 'leader' where guild_id = g and player_id = nextm;
      select p.pseudo into v_next_pseudo from profiles p where p.id = nextm;
      perform guild_journal_log(g, 'guild_left', uid, null, '🚪 ' || coalesce(v_pseudo,'Un joueur') || ' a quitté la guilde.');
      perform guild_journal_log(g, 'guild_leader_changed', nextm, null, '👑 ' || coalesce(v_next_pseudo,'Un membre') || ' devient chef de guilde.');
    else
      delete from guilds where id = g;  -- guilde vide → supprimée (plus personne pour lire le journal)
    end if;
  else
    perform guild_journal_log(g, 'guild_left', uid, null, '🚪 ' || coalesce(v_pseudo,'Un joueur') || ' a quitté la guilde.');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ── guild_kick : exclusion par le chef ─────────────────────────────────
create or replace function public.guild_kick(p_player_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; myrole text; targetrole text; actorpseudo text; targetpseudo text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if myrole <> 'leader' then return jsonb_build_object('ok', false, 'reason', 'not_leader'); end if;
  if p_player_id = uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  select role into targetrole from guild_members where guild_id = gid and player_id = p_player_id;
  if targetrole is null then return jsonb_build_object('ok', false, 'reason', 'not_member'); end if;
  -- Un chef ne peut pas être retiré (il doit transmettre le rôle ou dissoudre).
  if targetrole = 'leader' then return jsonb_build_object('ok', false, 'reason', 'cant_kick_leader'); end if;
  delete from guild_members where guild_id = gid and player_id = p_player_id;
  select p.pseudo into actorpseudo from profiles p where p.id = uid;
  select p.pseudo into targetpseudo from profiles p where p.id = p_player_id;
  perform guild_journal_log(gid, 'guild_kicked', uid, p_player_id, '⛔ ' || coalesce(targetpseudo,'Un membre') || ' a été exclu(e) par ' || coalesce(actorpseudo,'le chef') || '.');
  return jsonb_build_object('ok', true);
end $$;

-- ── guild_set_member_rank : changement de grade ────────────────────────
create or replace function public.guild_set_member_rank(p_player_id uuid, p_rank text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); gid bigint; myrole text; targetrole text;
  my_n int; target_n int; new_n int; actorpseudo text; targetpseudo text; ranklabel text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_rank not in ('g1','g2','g3','g4') then return jsonb_build_object('ok', false, 'reason', 'bad_rank'); end if;
  select gm.guild_id, gm.role into gid, myrole from guild_members gm where gm.player_id = uid;
  if gid is null then return jsonb_build_object('ok', false, 'reason', 'no_guild'); end if;
  if p_player_id = uid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  select role into targetrole from guild_members where guild_id = gid and player_id = p_player_id;
  if targetrole is null then return jsonb_build_object('ok', false, 'reason', 'not_member'); end if;
  if targetrole = 'leader' then return jsonb_build_object('ok', false, 'reason', 'cant_edit_leader'); end if;

  if myrole = 'leader' then
    update guild_members set role = p_rank where guild_id = gid and player_id = p_player_id;
    select p.pseudo into actorpseudo from profiles p where p.id = uid;
    select p.pseudo into targetpseudo from profiles p where p.id = p_player_id;
    select (g.rank_names->>p_rank) into ranklabel from guilds g where g.id = gid;
    perform guild_journal_log(gid, 'guild_rank_changed', uid, p_player_id, '🎖 ' || coalesce(targetpseudo,'Un membre') || ' passe au grade ' || coalesce(ranklabel, p_rank) || ' (par ' || coalesce(actorpseudo,'le chef') || ').');
    return jsonb_build_object('ok', true);
  end if;

  if not public.guild_member_permission(gid, uid, 'edit_lower_ranks') then
    return jsonb_build_object('ok', false, 'reason', 'no_permission');
  end if;
  my_n := substring(myrole from 2)::int;
  target_n := substring(targetrole from 2)::int;
  new_n := substring(p_rank from 2)::int;
  if target_n <= my_n then return jsonb_build_object('ok', false, 'reason', 'target_not_lower'); end if;
  if new_n < my_n then return jsonb_build_object('ok', false, 'reason', 'cant_promote_above_self'); end if;
  update guild_members set role = p_rank where guild_id = gid and player_id = p_player_id;
  select p.pseudo into actorpseudo from profiles p where p.id = uid;
  select p.pseudo into targetpseudo from profiles p where p.id = p_player_id;
  select (g.rank_names->>p_rank) into ranklabel from guilds g where g.id = gid;
  perform guild_journal_log(gid, 'guild_rank_changed', uid, p_player_id, '🎖 ' || coalesce(targetpseudo,'Un membre') || ' passe au grade ' || coalesce(ranklabel, p_rank) || ' (par ' || coalesce(actorpseudo,'un officier') || ').');
  return jsonb_build_object('ok', true);
end $$;

-- ── guild_challenge : déclaration d'un Défi inter-guildes (48h) ───────
create or replace function public.guild_challenge(p_target_guild bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare uid uuid := auth.uid(); g bigint; myrole text; already int; tid bigint;
  myname text; targetname text;
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
  select name into myname from guilds where id = g;
  select name into targetname from guilds where id = p_target_guild;
  perform guild_journal_log(g, 'guild_war_declared', uid, null, '⚔ Défi lancé contre ' || coalesce(targetname,'une guilde rivale') || '.');
  return jsonb_build_object('ok', true, 'id', tid);
end $$;

-- ── guild_challenge_respond : acceptation → la guerre commence ───────
-- (reprend aussi les notifications de guild_war_notifications.sql, déjà
-- exécuté — même fonction, ajout du journal en plus.)
create or replace function public.guild_challenge_respond(p_challenge_id bigint, p_accept boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
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

    perform guild_journal_log(t.guild_a, 'guild_war_started', uid, null, '⚔ La guerre contre ' || coalesce(name_b,'la guilde adverse') || ' commence (48 h).');
    perform guild_journal_log(t.guild_b, 'guild_war_started', uid, null, '⚔ La guerre contre ' || coalesce(name_a,'la guilde adverse') || ' commence (48 h).');
  else
    update guild_tournaments set status = 'declined' where id = p_challenge_id;
  end if;
  return jsonb_build_object('ok', true, 'accepted', p_accept);
end $$;

grant execute on function public.guild_challenge_respond(bigint, boolean) to authenticated;

-- ── guild_challenges_cleanup : clôture → journal du résultat ──────────
create or replace function public.guild_challenges_cleanup()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
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
  get diagnostics e = row_count;
  return jsonb_build_object('closed', n, 'expired', e);
end $$;

-- ── Lecture : les N dernières entrées du journal de MA guilde ─────────
-- Simple wrapper pratique (la RLS suffirait pour un select direct, mais un
-- RPC évite au client de connaître son guild_id à l'avance).
create or replace function public.guild_journal_list(p_limit int default 50)
returns setof public.guild_journal
language sql security definer set search_path to 'public' as $$
  select gj.* from guild_journal gj
  join guild_members gm on gm.guild_id = gj.guild_id and gm.player_id = auth.uid()
  order by gj.created_at desc
  limit greatest(1, least(coalesce(p_limit,50), 200));
$$;
grant execute on function public.guild_journal_list(int) to authenticated;

-- ── Contrôle ───────────────────────────────────────────────────────
select
  to_regclass('public.guild_journal')::text as tbl,                       -- attendu non-null
  to_regproc('public.guild_journal_log')::text as fn_log,                 -- attendu non-null
  to_regproc('public.guild_journal_list')::text as fn_list,               -- attendu non-null
  to_regproc('public.guild_create')::text as fn_create,                   -- attendu non-null
  to_regproc('public.guild_join')::text as fn_join,                       -- attendu non-null
  to_regproc('public.guild_leave')::text as fn_leave,                     -- attendu non-null
  to_regproc('public.guild_kick')::text as fn_kick,                       -- attendu non-null
  to_regproc('public.guild_set_member_rank')::text as fn_rank,            -- attendu non-null
  to_regproc('public.guild_challenge')::text as fn_challenge,             -- attendu non-null
  'guild_journal OK' as status;
