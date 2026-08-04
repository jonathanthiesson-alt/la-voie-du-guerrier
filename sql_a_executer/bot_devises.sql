-- ══════════════════════════════════════════════════════════════════
-- BOT-ARMY — devises charismatiques (voix courte de chaque bot, ≤60 car.
-- pour passer le trigger enforce_devise). Distinct du haïku (bot_roster.haiku)
-- et du lore profond (docs/LORE.md, bouton Lore de la fiche). Appliqué via MCP.
-- ══════════════════════════════════════════════════════════════════

update bot_roster b set devise = v.d
from (values
  ('01', $d$Un pied dans la boue — mais le premier pas est mien.$d$),
  ('02', $d$L'ombre m'a tout appris — sauf à qui elle appartient.$d$),
  ('03', $d$On ne franchit pas mon pont sans y laisser un nom.$d$),
  ('04', $d$Je garde des vies. La mienne, je l'ai oubliée.$d$),
  ('05', $d$Je portais ces cicatrices avant la première bataille.$d$),
  ('06', $d$Ma lame se souvient de ce que ma bouche tait.$d$),
  ('07', $d$La chance ? Je la martèle moi-même, à froid.$d$),
  ('08', $d$Je sers un maître absent — cet absent, c'était moi.$d$),
  ('09', $d$Je porte la bannière d'un seigneur qui n'est plus.$d$),
  ('10', $d$Intendant d'une maison vide, je compte du vent.$d$),
  ('11', $d$Un dieu m'a montré où finit l'acier. Je m'y tiens.$d$),
  ('12', $d$Je règne sur des provinces perdues sans le savoir.$d$),
  ('13', $d$Quand je lève la main, le ciel baisse les yeux.$d$),
  ('14', $d$On me prie, on me craint — je ne suis plus vraiment là.$d$),
  ('15', $d$Je tiens la Voie droite — et je cherche mon cœur.$d$),
  ('00', $d$Sans maître, sans nom. Quinze éclats de moi errent.$d$)
) as v(num, d)
where b.num = v.num;

-- Recopie sur le profil affiché (le trigger enforce_devise valide ≤60 car.).
update profiles p set devise = b.devise
from bot_roster b where b.profile_id = p.id and b.devise is not null;
