-- ════════════════════════════════════════════════════════════════════════
-- PUZZLE MODERATION & ECONOMY — lots P6 (achat d'emplacement), P7 (le seul
-- déblocable de création concret décidé à ce jour), P8 (volet admin)
-- docs/ROADMAP_PUZZLE_INVASION.md
-- ════════════════════════════════════════════════════════════════════════
-- ⚠️ P7 « déblocables de création » n'a jamais eu de catalogue figé au-delà
-- de la note vague « borderless via saison Sumo, etc. » — aucun système de
-- saison/pass n'existe dans le projet pour l'instant. Le seul déblocable
-- concret et sans risque de contredire un futur design : un emplacement de
-- publication supplémentaire (décision N), payé en monnaie puzzle. Le reste
-- de P7 reste à cadrer avec Wurmz/Thomas avant d'être codé.
-- ════════════════════════════════════════════════════════════════════════

-- ── P6 : achat d'un emplacement de publication supplémentaire ──────────
-- Coût croissant avec le nombre d'emplacements déjà possédés (même logique
-- anti-inflation que le plafond quotidien de puzzle_record_attempt) — à
-- recalibrer après mesure réelle, comme documenté au § 6 de la roadmap.
create or replace function public.puzzle_buy_slot()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare cur_slots integer; cost integer; new_slots integer;
begin
  select puzzle_slots into cur_slots from profiles where id = auth.uid();
  cur_slots := coalesce(cur_slots, 1);
  cost := cur_slots * 15;
  update profiles set puzzle_coin_balance = puzzle_coin_balance - cost, puzzle_slots = puzzle_slots + 1
    where id = auth.uid() and puzzle_coin_balance >= cost
    returning puzzle_slots into new_slots;
  if new_slots is null then raise exception 'Solde insuffisant (% pièces requises)', cost; end if;
  return new_slots;
end; $$;

-- ── P8 : volet admin — signalements de puzzles ──────────────────────────
-- Même patron que admin_get_reports/admin_resolve_report (joueurs), mais
-- table distincte (puzzle_reports, voir puzzles_core.sql). puzzle_admin_hide
-- existe déjà (dépublie + résout tous les signalements du puzzle) ; il ne
-- manquait qu'un moyen de LISTER les signalements ouverts et de rejeter un
-- signalement sans dépublier (faux signalement).
create or replace function public.admin_get_puzzle_reports()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare result jsonb;
begin
  if not is_admin_user() then return jsonb_build_object('ok', false); end if;
  select jsonb_build_object('ok', true, 'reports', coalesce(jsonb_agg(row_data), '[]'::jsonb))
    into result
  from (
    select pr.id, pr.puzzle_id, p.title as puzzle_title, pr.reason, pr.created_at,
           rp.pseudo as reporter, cp.pseudo as creator
    from puzzle_reports pr
    join puzzles p on p.id = pr.puzzle_id
    left join profiles rp on rp.id = pr.reporter_id
    left join profiles cp on cp.id = p.creator_id
    where pr.resolved = false
    order by pr.created_at asc
  ) row_data;
  return result;
end; $$;

create or replace function public.puzzle_admin_dismiss_report(p_report_id bigint)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not is_admin_user() then raise exception 'admin only'; end if;
  update puzzle_reports set resolved = true where id = p_report_id;
end; $$;

-- Contrôle de fin de script.
select 'puzzle_moderation_economy OK' as status;
