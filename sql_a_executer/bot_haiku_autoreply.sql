-- ══════════════════════════════════════════════════════════════════
-- BOT-ARMY — chaque bot a son HAÏKU, et répond automatiquement en haïku
-- quand un joueur lui écrit un message privé.
--
-- Lore : les 16 bots sont les éclats d'une seule âme (voir docs/LORE.md).
-- Le haïku est la « voix » de chaque fragment.
--
-- Mécanique : trigger AFTER INSERT sur direct_messages. Si le DESTINATAIRE
-- est un bot du roster (et l'expéditeur un humain), on insère aussitôt une
-- réponse (bot → expéditeur) avec le haïku du bot. Pas de cascade : la
-- réponse a un destinataire humain, et on ignore tout message dont
-- l'expéditeur est déjà un bot. SECURITY DEFINER → contourne la RLS.
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════

alter table bot_roster add column if not exists haiku text;

update bot_roster b set haiku = v.h
from (values
  ('01', $h$Premier pas dans l'herbe —
la lance est trop lourde
pour l'ombre qu'il fut.$h$),
  ('02', $h$Sous la lune basse
l'apprenti compte ses souffles :
un maître y dormait.$h$),
  ('03', $h$Le pont ne cède pas.
Un fragment monte la garde
d'un nom oublié.$h$),
  ('04', $h$Quatre sonne la mort ;
le corps qu'il protège encore
n'est plus tout à fait.$h$),
  ('05', $h$À mi-chemin, la pluie —
il connaît chaque cicatrice
sans savoir de qui.$h$),
  ('06', $h$La lame dit son nom
avant sa bouche : un éclat
de l'âme brisée.$h$),
  ('07', $h$Sept feux au dojo —
il forge sa propre chance
d'un métal ancien.$h$),
  ('08', $h$Huit grues sur la soie ;
il sert un seigneur absent —
lui-même, jadis.$h$),
  ('09', $h$La bannière claque.
Neuf pas sous le vent du nord —
le seigneur n'est plus.$h$),
  ('10', $h$Dix clefs à sa ceinture,
il garde une maison vide
où rôde une voix.$h$),
  ('11', $h$Le saint ne tranche pas :
l'air s'ouvre avant le fer —
un dieu le lui apprit.$h$),
  ('12', $h$Douze vallées ploient.
Il règne sur ce qu'il perdit
et ne le sait plus.$h$),
  ('13', $h$Treize corbeaux se taisent.
Le général lève la main —
le ciel obéit.$h$),
  ('14', $h$On brûle l'encens.
Ni tout à fait homme ni dieu :
un éclat qui prie.$h$),
  ('15', $h$Au sommet, le vide.
Le Guerrier tient la Voie droite —
et cherche son cœur.$h$),
  ('00', $h$Sans maître, sans nom,
il erre après quinze lunes —
son âme, en morceaux.$h$)
) as v(num, h)
where b.num = v.num;

-- ── Trigger de réponse automatique ────────────────────────────────
create or replace function bot_haiku_autoreply()
returns trigger
language plpgsql security definer set search_path=public as $$
declare h text; sender_is_bot boolean;
begin
  -- On ne répond jamais à un bot (pas de cascade bot ↔ bot).
  select coalesce(p.is_bot,false) into sender_is_bot from profiles p where p.id = new.sender_id;
  if sender_is_bot then return new; end if;
  -- Le destinataire est-il un bot du roster ? Sinon rien.
  select br.haiku into h from bot_roster br where br.profile_id = new.recipient_id;
  if h is null then return new; end if;
  -- Réponse immédiate : le bot renvoie son haïku à l'expéditeur.
  insert into direct_messages(sender_id, recipient_id, body, read)
    values (new.recipient_id, new.sender_id, h, false);
  return new;
end $$;

drop trigger if exists trg_bot_haiku_autoreply on direct_messages;
create trigger trg_bot_haiku_autoreply
  after insert on direct_messages
  for each row execute function bot_haiku_autoreply();

-- Contrôle : 16 haïkus posés, trigger présent.
select
  (select count(*) from bot_roster where haiku is not null) as haikus,
  (select count(*) from pg_trigger where tgname='trg_bot_haiku_autoreply') as trigger_present;
