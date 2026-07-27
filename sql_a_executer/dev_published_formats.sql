-- ════════════════════════════════════════════════════════════════════════
-- dev_published_formats — registre de modes de jeu publiés (milestone 5 ①)
-- ════════════════════════════════════════════════════════════════════════
-- Permet aux admins (Jonathan / Thomas) de PUBLIER un format construit dans le
-- Labo et de le PARTAGER entre eux : il est stocké côté serveur (pas juste en
-- localStorage local) et rechargeable dans le Labo de l'autre. Premier maillon
-- de la boucle « forger → tester → publier » ; ne touche PAS au moteur live.

create table if not exists public.dev_published_formats (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  format      jsonb not null,          -- descripteur de format VALIDÉ (labValidateFormat)
  author      text,                    -- pseudo du publieur (affichage)
  created_by  uuid,                    -- auth.uid() du publieur
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique(name)                         -- republier le même nom = mise à jour
);

alter table public.dev_published_formats enable row level security;

-- Lecture réservée aux admins (comme dev_balance_stats). Le navigateur lit en
-- direct via select ; les non-admins ne voient rien.
drop policy if exists dev_published_read on public.dev_published_formats;
create policy dev_published_read on public.dev_published_formats
  for select using (is_admin_user());

-- Publication (upsert par nom) — admin uniquement, rôle vérifié côté serveur.
create or replace function public.dev_publish_format(p_name text, p_format jsonb)
returns public.dev_published_formats
language plpgsql security definer set search_path to 'public' as $$
declare r public.dev_published_formats;
begin
  if not is_admin_user() then raise exception 'admin only'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'nom requis'; end if;
  insert into public.dev_published_formats (name, format, author, created_by)
    values (trim(p_name), p_format,
            coalesce((select pseudo from public.profiles where id = auth.uid()), 'admin'),
            auth.uid())
  on conflict (name) do update
    set format = excluded.format, author = excluded.author,
        created_by = excluded.created_by, updated_at = now()
  returning * into r;
  return r;
end; $$;

-- Suppression — admin uniquement.
create or replace function public.dev_delete_published_format(p_id uuid)
returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not is_admin_user() then raise exception 'admin only'; end if;
  delete from public.dev_published_formats where id = p_id;
end; $$;
