-- ══════════════════════════════════════════════════════════════════
-- TOURNOIS V4 — pilotés par l'ADMIN (refonte P4, Lot A)
--
-- Ce que change cette migration :
--   1. Les JOUEURS ne créent plus de tournois. La création/paramétrage passe
--      par des RPC réservées aux administrateurs (is_admin_user()).
--   2. Un tournoi porte désormais : un PUBLIC (tous / abonnés / freemium), un
--      TYPE (individuel / guilde), un MODE de jeu, un HORAIRE de début, des
--      FENÊTRES d'inscription, un TEXTE de présentation et des RÉCOMPENSES par
--      rang (jsonb) dans une MONNAIE au choix.
--   3. L'inscription respecte le public (abonnés vs freemium) et la fenêtre.
--   4. La remise des récompenses (podium) honore les montants paramétrés.
--
-- Idempotent. À exécuter APRÈS tournaments_v3.sql.
-- Rappel : l'éditeur SQL exécute TOUT en une transaction — si la dernière
-- instruction échoue, rien n'est appliqué. Vérifier le succès complet.
-- ══════════════════════════════════════════════════════════════════

-- ── (1) Nouvelles colonnes (idempotent) ─────────────────────────────
alter table tournaments add column if not exists audience text not null default 'all';
alter table tournaments add column if not exists kind text not null default 'individual';
alter table tournaments add column if not exists game_mode text not null default 'standard';
alter table tournaments add column if not exists starts_at timestamptz;
alter table tournaments add column if not exists registration_opens_at timestamptz;
alter table tournaments add column if not exists registration_closes_at timestamptz;
alter table tournaments add column if not exists presentation text;
-- Récompenses par rang, ex. {"1":80,"2":40,"3":20}. Vide = ancien barème linéaire.
alter table tournaments add column if not exists rewards jsonb not null default '{}'::jsonb;
-- Monnaie de récompense : préfixe d'une colonne <cur>_balance de profiles.
alter table tournaments add column if not exists reward_currency text not null default 'mon';

-- Contraintes de domaine (gardées : create constraint ne connaît pas IF NOT EXISTS).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tournaments_audience_chk') then
    alter table tournaments add constraint tournaments_audience_chk
      check (audience in ('all','subscriber','freemium'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tournaments_kind_chk') then
    alter table tournaments add constraint tournaments_kind_chk
      check (kind in ('individual','guild'));
  end if;
end $$;

-- Monnaies autorisées pour reward_currency (préfixes des colonnes _balance).
-- Centralisé ici pour valider côté serveur.
drop function if exists tournament_reward_currency_ok(text);
create or replace function tournament_reward_currency_ok(p_cur text)
returns boolean language sql immutable as $$
  select p_cur in ('mon','koku','fame','hanafuda','roku','ryu','shiitake','shiso','tamashii');
$$;

-- ── (2) Création par l'ADMIN uniquement ─────────────────────────────
drop function if exists tournament_admin_create(text, text, text, text, integer, integer, integer, integer, timestamptz, timestamptz, timestamptz, text, jsonb, text);
create or replace function tournament_admin_create(
    p_name text,
    p_kind text default 'individual',
    p_audience text default 'all',
    p_game_mode text default 'standard',
    p_timer integer default 5,
    p_total_rounds integer default 3,
    p_max_players integer default 32,
    p_round_minutes integer default 10,
    p_starts_at timestamptz default null,
    p_reg_opens_at timestamptz default null,
    p_reg_closes_at timestamptz default null,
    p_presentation text default null,
    p_rewards jsonb default '{}'::jsonb,
    p_reward_currency text default 'mon'
) returns jsonb language plpgsql security definer set search_path=public as $$
declare new_id bigint;
begin
  if not is_admin_user() then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;
  if coalesce(p_name,'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'name_required');
  end if;
  if p_kind not in ('individual','guild') then p_kind := 'individual'; end if;
  if p_audience not in ('all','subscriber','freemium') then p_audience := 'all'; end if;
  if not tournament_reward_currency_ok(p_reward_currency) then p_reward_currency := 'mon'; end if;

  insert into tournaments(
      name, status, total_rounds, current_round, timer_seconds, max_players,
      round_minutes, created_by, audience, kind, game_mode, starts_at,
      registration_opens_at, registration_closes_at, presentation, rewards, reward_currency)
    values (
      p_name, 'open', greatest(1, coalesce(p_total_rounds,3)), 0,
      greatest(1, coalesce(p_timer,5)), greatest(2, coalesce(p_max_players,32)),
      greatest(1, coalesce(p_round_minutes,10)), auth.uid(),
      p_audience, p_kind, coalesce(p_game_mode,'standard'), p_starts_at,
      p_reg_opens_at, p_reg_closes_at, p_presentation,
      coalesce(p_rewards,'{}'::jsonb), p_reward_currency)
    returning id into new_id;

  return jsonb_build_object('ok', true, 'id', new_id);
end $$;

-- ── (2b) Mise à jour par l'ADMIN (champs optionnels = inchangés) ─────
drop function if exists tournament_admin_update(bigint, text, text, text, text, integer, integer, integer, integer, timestamptz, timestamptz, timestamptz, text, jsonb, text);
create or replace function tournament_admin_update(
    p_id bigint,
    p_name text default null,
    p_kind text default null,
    p_audience text default null,
    p_game_mode text default null,
    p_timer integer default null,
    p_total_rounds integer default null,
    p_max_players integer default null,
    p_round_minutes integer default null,
    p_starts_at timestamptz default null,
    p_reg_opens_at timestamptz default null,
    p_reg_closes_at timestamptz default null,
    p_presentation text default null,
    p_rewards jsonb default null,
    p_reward_currency text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare t record;
begin
  if not is_admin_user() then
    return jsonb_build_object('ok', false, 'reason', 'forbidden');
  end if;
  select * into t from tournaments where id = p_id;
  if t is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  -- On ne modifie plus un tournoi déjà lancé/terminé (garde-fou).
  if t.status <> 'open' then
    return jsonb_build_object('ok', false, 'reason', 'not_editable', 'status', t.status);
  end if;
  if p_kind is not null and p_kind not in ('individual','guild') then p_kind := null; end if;
  if p_audience is not null and p_audience not in ('all','subscriber','freemium') then p_audience := null; end if;
  if p_reward_currency is not null and not tournament_reward_currency_ok(p_reward_currency) then p_reward_currency := null; end if;

  update tournaments set
    name                   = coalesce(p_name, name),
    kind                   = coalesce(p_kind, kind),
    audience               = coalesce(p_audience, audience),
    game_mode              = coalesce(p_game_mode, game_mode),
    timer_seconds          = coalesce(p_timer, timer_seconds),
    total_rounds           = coalesce(p_total_rounds, total_rounds),
    max_players            = coalesce(p_max_players, max_players),
    round_minutes          = coalesce(p_round_minutes, round_minutes),
    starts_at              = coalesce(p_starts_at, starts_at),
    registration_opens_at  = coalesce(p_reg_opens_at, registration_opens_at),
    registration_closes_at = coalesce(p_reg_closes_at, registration_closes_at),
    presentation           = coalesce(p_presentation, presentation),
    rewards                = coalesce(p_rewards, rewards),
    reward_currency        = coalesce(p_reward_currency, reward_currency)
  where id = p_id;

  return jsonb_build_object('ok', true);
end $$;

-- ── (3) La création « joueur » historique est désormais réservée admin ─
-- Même signature (le client existant ne casse pas) mais refuse un non-admin.
create or replace function tournament_create(p_name text, p_timer integer)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not is_admin_user() then
    return jsonb_build_object('ok', false, 'reason', 'forbidden_players_cannot_create');
  end if;
  return tournament_admin_create(p_name, 'individual', 'all', 'standard', coalesce(p_timer,5));
end $$;

-- ── (4) Inscription : respecte public (abonné/freemium) et fenêtre ──
create or replace function tournament_register(p_tournament_id bigint)
returns jsonb language plpgsql security definer set search_path=public as $$
declare uid uuid := auth.uid(); t record; cnt int; sub boolean;
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

  -- Type guilde : l'inscription individuelle ne s'applique pas (Lot C guilde).
  if t.kind = 'guild' then
    return jsonb_build_object('ok', false, 'reason', 'guild_tournament');
  end if;

  select count(*) into cnt from tournament_participants where tournament_id = p_tournament_id;
  if cnt >= coalesce(t.max_players,32) then
    return jsonb_build_object('ok', false, 'reason', 'full', 'max_players', t.max_players);
  end if;

  insert into tournament_participants(tournament_id, player_id)
    values (p_tournament_id, uid) on conflict (tournament_id, player_id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- ── (5) Podium : récompenses paramétrées (jsonb) ou barème linéaire ──
create or replace function tournament_award_podium(p_tournament_id bigint)
returns void language plpgsql security definer set search_path=public as $$
declare r record; rank int := 0; total int; reward int;
        max_r int := 20; min_r int := 3;
        tpl text[] := array[
          '%s remporte le tournoi "%s".',
          '%s soulève le trophée du tournoi "%s".',
          'Le tournoi "%s" s''incline devant %s.'
        ];
        t record; cur text; cust boolean;
        t_name text; winner_pseudo text;
begin
  select * into t from tournaments where id = p_tournament_id;
  if t is null then return; end if;
  t_name := t.name;
  cur := coalesce(t.reward_currency,'mon');
  if not tournament_reward_currency_ok(cur) then cur := 'mon'; end if;
  -- Récompenses personnalisées si l'admin a fourni un barème non vide.
  cust := (t.rewards is not null and t.rewards <> '{}'::jsonb);

  select count(*) into total from tournament_participants
    where tournament_id = p_tournament_id and abandoned = false;
  if total = 0 then return; end if;

  for r in
    select player_id from tournament_participants
    where tournament_id = p_tournament_id and abandoned = false
    order by score desc, wins desc
  loop
    rank := rank + 1;

    if cust then
      -- Montant du rang dans le barème (0 si absent) ; monnaie choisie.
      reward := coalesce((t.rewards ->> rank::text)::int, 0);
      if reward > 0 then
        execute format('update profiles set %I = coalesce(%I,0) + $1 where id = $2',
                       cur||'_balance', cur||'_balance')
          using reward, r.player_id;
      end if;
    else
      -- Ancien barème linéaire (mon), inchangé.
      if total = 1 then reward := max_r;
      else reward := round(min_r + (max_r - min_r) * (total - rank)::numeric / (total - 1)); end if;
      update profiles set mon_balance = mon_balance + reward where id = r.player_id;
    end if;

    if rank = 1 then
      select pseudo into winner_pseudo from profiles where id = r.player_id;
      if winner_pseudo is not null and t_name is not null then
        if random() < 0.667 then
          insert into public.activity_feed(event_type, message)
          values ('victoire_tournoi', format(tpl[1+floor(random()*2)::int], winner_pseudo, t_name));
        else
          insert into public.activity_feed(event_type, message)
          values ('victoire_tournoi', format(tpl[3], t_name, winner_pseudo));
        end if;
      end if;
    end if;
  end loop;
end $$;

-- ── (6) La liste expose les nouveaux champs (présentation, public, etc.) ─
drop function if exists tournament_list();
create or replace function tournament_list()
returns jsonb language plpgsql security definer set search_path=public as $$
declare rows jsonb;
begin
  perform tournament_cleanup();
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into rows from (
    select t.id, t.name, t.status, t.total_rounds, t.current_round, t.timer_seconds,
           t.max_players, t.round_minutes, t.round_deadline, t.created_by,
           t.audience, t.kind, t.game_mode, t.starts_at,
           t.registration_opens_at, t.registration_closes_at, t.presentation,
           t.rewards, t.reward_currency,
           (select count(*) from tournament_participants tp where tp.tournament_id = t.id) as players
    from tournaments t
    where t.status in ('open','running')
    order by coalesce(t.starts_at, t.created_at) desc
    limit 20
  ) x;
  return jsonb_build_object('ok', true, 'tournaments', rows);
end $$;

-- ── Fin. Vérif rapide (facultatif) :
--   select id,name,audience,kind,game_mode,reward_currency,rewards,starts_at
--   from tournaments order by created_at desc limit 5;
