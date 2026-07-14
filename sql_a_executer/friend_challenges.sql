-- ═══════════════════════════════════════════════════════════════════
-- Défis entre amis : mode (partie rapide / Arène) + choix compétitif
-- ou amical (aucun impact ELO/monnaies/XP si amical).
--
-- À exécuter en une fois dans l'éditeur SQL Supabase.
-- ═══════════════════════════════════════════════════════════════════

alter table public.challenges
  add column if not exists mode text not null default 'quick';
alter table public.challenges
  add column if not exists ranked boolean not null default true;

alter table public.online_games
  add column if not exists ranked boolean not null default true;

alter table public.arena_matches
  add column if not exists ranked boolean not null default true;

-- L'Arène n'accorde jamais d'ELO (déjà le cas), mais un défi d'Arène
-- "amical" ne doit pas non plus rapporter de 石 (Koku) — sinon un joueur
-- pourrait fermer et rouvrir des défis amicaux entre comptes pour
-- farmer la monnaie sans risque.
create or replace function public.record_arena_round_win(p_arena_match_id uuid, p_winner_color text, p_timer_seconds integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare m record; new_ww integer; new_wb integer; tokens integer; done boolean; wid uuid; new_round integer;
begin
  select * into m from arena_matches where id=p_arena_match_id for update;
  if m is null then raise exception 'Match arène introuvable'; end if;
  if p_winner_color='white' then
    new_ww:=m.wins_white+1; new_wb:=m.wins_black; wid:=m.white_player_id;
  else
    new_ww:=m.wins_white; new_wb:=m.wins_black+1; wid:=m.black_player_id;
  end if;
  -- Montants corrigés : la cadence la plus rapide (3s, la plus exigeante)
  -- rapporte le plus de 石. Rien en Arène amicale (voir commentaire ci-dessus).
  if coalesce(m.ranked, true) then
    tokens := case p_timer_seconds when 3 then 4 when 5 then 3 when 10 then 2 else 2 end;
    update profiles set koku_balance = koku_balance + tokens where id = wid;
  else
    tokens := 0;
  end if;
  done := (new_ww>=2 or new_wb>=2);
  new_round := case when done then m.round_number else m.round_number+1 end;
  update arena_matches set
    wins_white=new_ww, wins_black=new_wb,
    status = case when done then 'finished' else status end,
    winner_id = case when done then wid else winner_id end,
    round_number = new_round,
    ready_white=false, ready_black=false
  where id=p_arena_match_id;
  return jsonb_build_object('wins_white',new_ww,'wins_black',new_wb,'match_done',done,'tokens_awarded',tokens,'winner_id',wid,'round_number',new_round);
end $function$;
