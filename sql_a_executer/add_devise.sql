-- ══════════════════════════════════════════════════════════════════
-- DEVISE DE PROFIL — phrase libre affichée sur le profil du joueur.
--
-- Ajoute profiles.devise (≤ 60 car.) + une MODÉRATION SERVEUR (trigger) qui
-- refuse racisme, discriminations et insultes. Le client (moderateDevise dans
-- index.html) fait un premier filtre, mais un client est contournable : ce
-- trigger est le garde-fou qui compte, rejoué à chaque écriture.
--
-- Idempotent. À exécuter quand tu veux (aucune dépendance d'ordre).
-- ══════════════════════════════════════════════════════════════════

alter table public.profiles add column if not exists devise text;

-- Normalisation anti-contournement : minuscules, accents aplatis, leet
-- (0→o, 1→i, 3→e, 4→a, 5→s, 7→t, @→a, $→s), puis on ne garde que a-z0-9.
-- Pas de dépendance à l'extension unaccent : on translitère à la main.
create or replace function public.devise_normalize(txt text)
returns text language sql immutable as $$
  select regexp_replace(
    translate(
      lower(coalesce(txt,'')),
      'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ0134577@$',
      'aaaaaaceeeeiiiinooooouuuuyyoieasst' || 'a' || 's'
    ),
    '[^a-z0-9]', '', 'g'
  );
$$;

-- Liste bannie (miroir du client). Comparaison en sous-chaîne sur la forme
-- « collée ». Extensible : ajoute des termes dans le array ci-dessous.
create or replace function public.devise_is_allowed(txt text)
returns boolean language plpgsql immutable as $$
declare
  norm text := public.devise_normalize(txt);
  banned text[] := array[
    'negre','niger','nigger','nigga','bougnoule','bicot','chinetoque',
    'youpin','feuj','raton','melon','tapette','tarlouze','pede','pedale',
    'faggot','tranny','mongolien','gogol',
    'connard','conard','connasse','salope','pute','putain','encule','enfoire','batard',
    'ntm','fdp','filsdepute','bastard','bitch','whore','asshole','cunt','motherfucker'
  ];
  w text;
begin
  if norm = '' then
    return true; -- devise vide = autorisée (efface)
  end if;
  foreach w in array banned loop
    if position(public.devise_normalize(w) in norm) > 0 then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

-- Trigger : borne la longueur et applique la modération à chaque écriture.
create or replace function public.enforce_devise()
returns trigger language plpgsql as $$
begin
  if new.devise is not null then
    new.devise := btrim(regexp_replace(new.devise, '\s+', ' ', 'g'));
    if new.devise = '' then
      new.devise := null;
    elsif char_length(new.devise) > 60 then
      raise exception 'Devise trop longue (60 caractères max).';
    elsif not public.devise_is_allowed(new.devise) then
      raise exception 'Devise refusée : racisme, discriminations et insultes sont bannis.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_devise on public.profiles;
create trigger trg_enforce_devise
  before insert or update of devise on public.profiles
  for each row execute function public.enforce_devise();

-- Vérif rapide (doit renvoir false, true) :
--   select public.devise_is_allowed('sale conn4rd'), public.devise_is_allowed('La lame suit la volonté');
