-- ═══════════════════════════════════════════════════════════════════
-- Easter egg « Trouver Wurmz » — le bousier qui passe la tête sur
-- l'écran d'accueil (1 fois sur 100), à la manière du Dan Forden de
-- Mortal Kombat. Le cliquer rapporte 400 Koku + le succès secret.
--
-- Pourquoi un RPC plutôt qu'un simple += côté client : le Koku a pour
-- source de vérité profiles.koku_balance. Laisser le client annoncer
-- « donne-moi 400 Koku » reproduirait EXACTEMENT la faille
-- guild_contribute_ryu (montant libre = triche illimitée). Ici le client
-- ne fournit RIEN : le montant est en dur côté serveur, et le drapeau
-- profiles.wurmz_found garantit un seul versement par compte.
--
-- À exécuter en une fois dans l'éditeur SQL Supabase.
-- ═══════════════════════════════════════════════════════════════════

alter table public.profiles
  add column if not exists wurmz_found boolean not null default false;

create or replace function public.claim_wurmz_egg()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare uid uuid := auth.uid(); deja boolean; prime int := 400;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- for update : deux clics très rapprochés (ou deux onglets) ne doivent
  -- pas pouvoir encaisser la prime deux fois.
  select wurmz_found into deja from profiles where id = uid for update;
  if deja then
    return jsonb_build_object('ok', true, 'already', true, 'koku', 0);
  end if;

  update profiles
     set wurmz_found = true,
         koku_balance = coalesce(koku_balance, 0) + prime
   where id = uid;

  return jsonb_build_object('ok', true, 'already', false, 'koku', prime,
                            'balance', (select koku_balance from profiles where id = uid));
end $function$;

grant execute on function public.claim_wurmz_egg() to authenticated;
