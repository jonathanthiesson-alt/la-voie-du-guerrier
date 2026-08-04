-- ══════════════════════════════════════════════════════════════════
-- BOT-ARMY — demandes d'ami : les 15 fragments ACCEPTENT aussitôt (→ on peut
-- leur écrire → réponse en haïku, voir bot_haiku_autoreply.sql). 0-Rōnin
-- (num 00) n'accepte JAMAIS : la demande reste 'pending' à vie (lore : le
-- vide n'a pas d'amis). Trigger BEFORE INSERT, SECURITY DEFINER. Idempotent.
--
-- Rappel : la messagerie exige une amitié acceptée. Donc écrire à un bot
-- suppose d'abord de l'avoir DÉBLOQUÉ dans la Bot-Army (il apparaît alors
-- dans la liste « Joueurs »), puis de lui envoyer une demande d'ami.
-- ══════════════════════════════════════════════════════════════════

create or replace function bot_friend_autoaccept()
returns trigger language plpgsql security definer set search_path=public as $$
declare bnum text;
begin
  if new.status is distinct from 'pending' then return new; end if;
  select br.num into bnum from bot_roster br where br.profile_id = new.addressee_id;
  if bnum is null then return new; end if;   -- destinataire : pas un bot du roster
  if bnum = '00' then return new; end if;    -- le Rōnin n'accepte jamais
  new.status := 'accepted';                  -- les 15 acceptent d'emblée
  return new;
end $$;

drop trigger if exists trg_bot_friend_autoaccept on friendships;
create trigger trg_bot_friend_autoaccept
  before insert on friendships
  for each row execute function bot_friend_autoaccept();
