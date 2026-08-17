-- ═══════════════════════════════════════════════════════════════════
-- MONBAN RÉACTIF — lot G0, docs/ROADMAP_GUILD_BATTLE.md § 3
--
-- Jusqu'ici, Monban ne rejouait qu'au rythme du worker GitHub Actions
-- (scripts/bot-army.mjs, cron 10 min — .github/workflows/bot-army.yml),
-- ou plus vite s'il tournait déjà en continu (mode backfill). Ce script
-- ajoute un déclenchement RÉACTIF (sous la seconde visée) : dès qu'une
-- partie d'invasion active passe au tour de Noir (le défenseur), un
-- trigger Postgres appelle l'Edge Function monban-move via pg_net
-- (asynchrone, non-bloquant pour la transaction).
--
-- Ce trigger ne REMPLACE PAS le worker existant : il ne fait qu'accélérer
-- le cas où la requête est déjà passée en statut 'monban'. La fenêtre
-- d'acceptation de 15 s (bascule 'awaiting_accept' → 'monban') et le
-- nettoyage restent gérés par driveInvasions() côté worker, inchangé —
-- décision du cadrage : ne pas empiler deux inconnues sur le chemin
-- critique, valider d'abord la seule partie neuve (la réactivité).
-- Les deux mécanismes sont redondants par construction : si l'un des
-- deux gagne la course (le trigger arrivera presque toujours en premier,
-- pg_net étant appelé dans la même transaction que le coup qui vient
-- d'être joué), l'autre trouvera simplement `status <> 'monban'` ou
-- `turn <> 'black'` et ne fera rien (idempotent des deux côtés).
--
-- Secret partagé (même valeur que TRIGGER_SECRET côté monban-move/index.ts) :
-- ce n'est PAS une vraie frontière de sécurité (la clé service_role n'est
-- jamais transmise ici, elle reste lue par l'Edge Function via Deno.env),
-- juste un frein contre un appel accidentel/externe de l'endpoint — la
-- pire conséquence d'une fuite est de faire jouer un coup Monban légal en
-- avance sur une partie d'invasion existante, aucune écriture arbitraire.
-- ═══════════════════════════════════════════════════════════════════

create extension if not exists pg_net;

create or replace function public.invasion_dispatch_monban()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  perform net.http_post(
    url := 'https://ikssbshpvpqlcgrbjldz.supabase.co/functions/v1/monban-move',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-monban-secret', '1ea0943dfd093ee488eaca6cf49d2e7811de6474a7f6e0d6'
    ),
    body := jsonb_build_object('game_id', new.id)
  );
  return new;
end;
$$;

drop trigger if exists invasion_dispatch_monban_trg on public.online_games;
create trigger invasion_dispatch_monban_trg
  after update of turn on public.online_games
  for each row
  when (new.is_invasion = true and new.status = 'active' and new.turn = 'black' and old.turn is distinct from new.turn)
  execute function public.invasion_dispatch_monban();

-- ── Contrôle ───────────────────────────────────────────────────────
select
  (select extname from pg_extension where extname = 'pg_net') as ext_pg_net, -- attendu 'pg_net'
  to_regproc('public.invasion_dispatch_monban')::text as fn_dispatch,        -- attendu non-null
  (select count(*) from pg_trigger where tgname = 'invasion_dispatch_monban_trg') as trg_count, -- attendu 1
  'invasion_reactive_monban OK' as status;
