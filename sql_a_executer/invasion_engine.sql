-- ════════════════════════════════════════════════════════════════════════
-- INVASION ENGINE — lots I2 à I5 (défense serveur, file, économie du vol)
-- docs/ROADMAP_PUZZLE_INVASION.md. Réutilise online_games telle quelle
-- (décision : une invasion EST une partie en ligne normale, taguée) plutôt
-- que de dupliquer l'infrastructure de partie — l'envahisseur joue TOUJOURS
-- Blanc, le défenseur TOUJOURS Noir (simplification V1, jamais annoncée
-- comme figée dans les décisions A-W mais nécessaire pour garder le moteur
-- worker simple : Monban ne joue qu'un camp fixe).
-- ════════════════════════════════════════════════════════════════════════

-- ── online_games : marquage invasion ────────────────────────────────────
alter table public.online_games add column if not exists is_invasion boolean not null default false;
alter table public.online_games add column if not exists invasion_attacker_id uuid references public.profiles(id);
alter table public.online_games add column if not exists invasion_defender_id uuid references public.profiles(id);
alter table public.online_games add column if not exists invasion_resolved boolean not null default false;

-- ── invasion_history : traçabilité de la partie résolue ─────────────────
alter table public.invasion_history add column if not exists game_id uuid references public.online_games(id);

-- ── File d'acceptation (décision D : 15 s pour accepter, sinon Monban) ──
-- Aucune politique INSERT/UPDATE : toute écriture passe par les RPC
-- ci-dessous (SECURITY DEFINER) — même schéma que puzzles/monban_profiles.
create table if not exists public.invasion_requests (
  id           bigint generated always as identity primary key,
  game_id      uuid references public.online_games(id) on delete cascade,
  attacker_id  uuid not null references public.profiles(id) on delete cascade,
  defender_id  uuid not null references public.profiles(id) on delete cascade,
  status       text not null default 'awaiting_accept', -- awaiting_accept | accepted | monban | resolved
  expires_at   timestamptz not null,
  created_at   timestamptz not null default now()
);
create index if not exists invasion_requests_defender_idx on public.invasion_requests(defender_id, status);
create index if not exists invasion_requests_game_idx on public.invasion_requests(game_id);

alter table public.invasion_requests enable row level security;
drop policy if exists invasion_requests_select_own on public.invasion_requests;
create policy invasion_requests_select_own on public.invasion_requests
  for select using (attacker_id = auth.uid() or defender_id = auth.uid());

-- ── RPC : autorise + amorce une invasion (vérifie TOUTES les gardes) ────
-- Décision C (limite 24h côté attaquant), décision W (72h par couple),
-- bouclier du défenseur. Ne crée PAS encore la partie (le client la
-- construit ensuite avec le moteur local, comme createOnlineGame) — évite
-- de dupliquer la logique de plateau de départ côté SQL.
create or replace function public.invasion_authorize(p_defender_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_attacker uuid := auth.uid();
  v_last_invasion timestamptz;
  v_shield timestamptz;
  v_recent_pair int;
  v_request_id bigint;
  v_expires timestamptz;
begin
  if v_attacker is null then raise exception 'Non authentifié.'; end if;
  if v_attacker = p_defender_id then raise exception 'Impossible de s''envahir soi-même.'; end if;

  select last_invasion_at into v_last_invasion from profiles where id = v_attacker;
  if v_last_invasion is not null and v_last_invasion > now() - interval '24 hours' then
    raise exception 'Une seule invasion par jour — reviens plus tard.';
  end if;

  select shield_until into v_shield from profiles where id = p_defender_id;
  if v_shield is not null and v_shield > now() then
    raise exception 'Ce joueur est protégé par un bouclier.';
  end if;

  select count(*) into v_recent_pair from invasion_history
    where attacker_id = v_attacker and defender_id = p_defender_id and created_at > now() - interval '72 hours';
  if v_recent_pair > 0 then
    raise exception 'Tu as déjà envahi ce joueur récemment — réessaie plus tard.';
  end if;

  update profiles set last_invasion_at = now() where id = v_attacker;

  v_expires := now() + interval '15 seconds';
  insert into invasion_requests (attacker_id, defender_id, status, expires_at)
    values (v_attacker, p_defender_id, 'awaiting_accept', v_expires)
    returning id into v_request_id;

  insert into notifications (user_id, type, title, body, payload)
    values (p_defender_id, 'invasion_incoming', 'Invasion !',
            'Un envahisseur attaque ton dojo — 15 secondes pour te défendre en personne, sinon Monban prend le relais.',
            jsonb_build_object('request_id', v_request_id));

  return jsonb_build_object('request_id', v_request_id, 'expires_at', v_expires);
end; $$;

-- ── RPC : attache la partie fraîchement créée par le client attaquant ───
create or replace function public.invasion_attach_game(p_request_id bigint, p_game_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  update invasion_requests set game_id = p_game_id
    where id = p_request_id and attacker_id = auth.uid() and game_id is null;
end; $$;

-- ── RPC : réponse du défenseur (accepter = rejoindre en direct) ─────────
create or replace function public.invasion_respond(p_request_id bigint, p_accept boolean)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r record; g record;
begin
  select * into r from invasion_requests where id = p_request_id and defender_id = auth.uid() for update;
  if not found then raise exception 'Invasion introuvable.'; end if;
  if r.status <> 'awaiting_accept' or r.expires_at < now() or r.game_id is null then
    raise exception 'Trop tard — Monban a déjà pris le relais.';
  end if;
  update invasion_requests set status = (case when p_accept then 'accepted' else 'monban' end) where id = p_request_id;
  if not p_accept then return jsonb_build_object('accepted', false); end if;
  select * into g from online_games where id = r.game_id;
  return jsonb_build_object('accepted', true, 'game_id', g.id, 'white_player_id', g.white_player_id,
    'game_state', g.game_state, 'turn', g.turn, 'timer_seconds', g.timer_seconds, 'ranked', g.ranked);
end; $$;

-- ── Résolution partagée (transfert de monnaie, stats, notifs, journal) ──
-- PAS exposée directement : EXECUTE révoqué ci-dessous pour anon/authenticated.
-- Décision I/J, V1 : le vainqueur ne CHOISIT pas encore la monnaie (ça
-- suppose une UI de choix côté vainqueur, hors scope de cette passe) —
-- toujours la monnaie la MIEUX FOURNIE du perdant, jamais le Koku.
create or replace function public.invasion_resolve_internal(p_game_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare
  g record; v_winner_id uuid; v_loser_id uuid; v_currency text; v_col text; v_amt int := 1;
  names text[] := array['shiso_balance','tamashii_balance','mon_balance','ryu_balance','hanafuda_balance','shiitake_balance','fame_balance','roku_balance'];
  vals int[]; i int; best_i int := 1; best_v int := -1; v int;
  v_was_live boolean;
begin
  select * into g from online_games where id = p_game_id and is_invasion = true and coalesce(invasion_resolved,false) = false;
  if not found or g.winner is null then return; end if;

  v_winner_id := case when g.winner = 'white' then g.white_player_id else g.black_player_id end;
  v_loser_id  := case when g.winner = 'white' then g.black_player_id else g.white_player_id end;

  select array[shiso_balance,tamashii_balance,mon_balance,ryu_balance,hanafuda_balance,shiitake_balance,fame_balance,roku_balance]
    into vals from profiles where id = v_loser_id;
  for i in 1..array_length(names,1) loop
    v := coalesce(vals[i], 0);
    if v > best_v then best_v := v; best_i := i; end if;
  end loop;
  v_col := names[best_i];
  v_currency := replace(v_col, '_balance', '');

  execute format('update profiles set %I = greatest(0, %I - $1) where id = $2', v_col, v_col) using v_amt, v_loser_id;
  execute format('update profiles set %I = %I + $1 where id = $2', v_col, v_col) using v_amt, v_winner_id;

  select (status = 'accepted') into v_was_live from invasion_requests where game_id = p_game_id order by created_at desc limit 1;

  insert into invasion_history (attacker_id, defender_id, winner_id, currency, amount, live, game_id)
    values (g.invasion_attacker_id, g.invasion_defender_id, v_winner_id, v_currency, v_amt, coalesce(v_was_live,false), p_game_id);

  -- Décision : les stats de défense comptent que le défenseur ait joué en
  -- personne ou que Monban ait pris le relais — c'est le dojo qui est jugé.
  insert into monban_stats (user_id, defends_won, defends_lost, updated_at)
    values (g.invasion_defender_id,
            case when v_winner_id = g.invasion_defender_id then 1 else 0 end,
            case when v_winner_id = g.invasion_defender_id then 0 else 1 end,
            now())
    on conflict (user_id) do update set
      defends_won = monban_stats.defends_won + excluded.defends_won,
      defends_lost = monban_stats.defends_lost + excluded.defends_lost,
      updated_at = now();

  insert into notifications (user_id, type, title, body, ref_id, payload) values
    (g.invasion_defender_id,
     case when v_winner_id = g.invasion_defender_id then 'invasion_defended' else 'invasion_lost' end,
     case when v_winner_id = g.invasion_defender_id then 'Invasion repoussée !' else 'Invasion perdue' end,
     case when v_winner_id = g.invasion_defender_id then 'Ton dojo a tenu bon.' else 'Ton dojo est tombé — 1 '||v_currency||' perdu.' end,
     p_game_id, jsonb_build_object('currency', v_currency, 'amount', v_amt)),
    (g.invasion_attacker_id,
     case when v_winner_id = g.invasion_attacker_id then 'invasion_won' else 'invasion_repelled' end,
     case when v_winner_id = g.invasion_attacker_id then 'Invasion réussie !' else 'Invasion repoussée' end,
     case when v_winner_id = g.invasion_attacker_id then 'Tu as pillé 1 '||v_currency||'.' else 'Le défenseur a tenu bon.' end,
     p_game_id, jsonb_build_object('currency', v_currency, 'amount', v_amt));

  insert into player_journal (user_id, event_type, message) values
    (g.invasion_defender_id,
     case when v_winner_id = g.invasion_defender_id then 'invasion_defended' else 'invasion_lost' end,
     case when v_winner_id = g.invasion_defender_id then 'A repoussé une invasion.' else 'A perdu une invasion ('||v_currency||').' end),
    (g.invasion_attacker_id,
     case when v_winner_id = g.invasion_attacker_id then 'invasion_won' else 'invasion_repelled' end,
     case when v_winner_id = g.invasion_attacker_id then 'A réussi une invasion ('||v_currency||').' else 'A été repoussé en tentant une invasion.' end);

  update online_games set invasion_resolved = true, status = 'finished' where id = p_game_id;
  update invasion_requests set status = 'resolved' where game_id = p_game_id;
end; $$;
revoke execute on function public.invasion_resolve_internal(uuid) from public, anon, authenticated;

-- ── RPC serveur : résolution normale (worker uniquement) ────────────────
-- Appelée par bot-army.mjs (service_role) une fois qu'une partie d'invasion
-- se termine (humain ou Monban) — online_games.winner a été écrit par le
-- déroulement légitime de la partie, jamais fabriqué par ce garde.
create or replace function public.invasion_resolve(p_game_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.role() <> 'service_role' then raise exception 'Réservé au serveur.'; end if;
  perform invasion_resolve_internal(p_game_id);
end; $$;

-- ── RPC : abandon = défaite (décision S) ─────────────────────────────────
-- Auto-déclaration : je ne peux déclarer QUE ma propre défaite, donc non
-- exploitable pour léser un adversaire. Pas de fenêtre de reconnexion (45 s)
-- dans cette V1 — seul le clic explicite "Quitter le combat" déclenche un
-- forfait ; une simple coupure réseau ne perd pas encore automatiquement
-- (chantier futur, voir docs/ROADMAP_PUZZLE_INVASION.md).
create or replace function public.invasion_forfeit(p_game_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare g record; v_my_color text;
begin
  select * into g from online_games where id = p_game_id and is_invasion = true and coalesce(invasion_resolved,false) = false;
  if not found then return; end if;
  if auth.uid() = g.white_player_id then v_my_color := 'white';
  elsif auth.uid() = g.black_player_id then v_my_color := 'black';
  else raise exception 'Tu ne participes pas à cette invasion.'; end if;

  update online_games set winner = (case when v_my_color = 'white' then 'black' else 'white' end), status = 'finished'
    where id = p_game_id;
  perform invasion_resolve_internal(p_game_id);
end; $$;

-- ── RPC : candidats à l'invasion (décision K : sélecteur de tranche) ────
-- Exclut moi-même, les boucliers actifs, les joueurs envahis par moi dans
-- les 72h (décision W). N'exclut PAS encore les joueurs en tournoi/guerre de
-- guilde (décision L, "sauf objection") — chantier futur documenté dans la
-- roadmap, pas un oubli silencieux.
create or replace function public.invasion_candidates(p_elo_min int, p_elo_max int)
returns table(id uuid, pseudo text, elo_5s int) language sql security definer set search_path to 'public' as $$
  select p.id, p.pseudo, coalesce(p.elo_5s,1200) as elo_5s
  from profiles p
  where p.id <> auth.uid()
    and p.is_bot = false
    and coalesce(p.elo_5s,1200) between p_elo_min and p_elo_max
    and (p.shield_until is null or p.shield_until < now())
    and not exists (
      select 1 from invasion_history h
      where h.attacker_id = auth.uid() and h.defender_id = p.id and h.created_at > now() - interval '72 hours'
    )
  order by p.last_seen desc nulls last
  limit 20;
$$;

select 'invasion_engine OK' as status;
