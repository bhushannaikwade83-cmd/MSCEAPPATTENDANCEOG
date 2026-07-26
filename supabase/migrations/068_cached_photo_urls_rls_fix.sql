-- Fix Security Advisor: "RLS Disabled in Public" on public.cached_photo_urls
-- Migration 045 enabled RLS; re-apply safely if the table was created without it or RLS was turned off.
-- Note: This linter issue does NOT by itself make PostgREST unhealthy (check API logs / compute / connections).

create table if not exists public.cached_photo_urls (
  id uuid primary key default gen_random_uuid(),
  object_path text not null,
  photo_url text not null,
  authorization_token text,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint cached_photo_urls_object_path_unique unique (object_path)
);

create index if not exists idx_cached_photo_urls_expires_at
  on public.cached_photo_urls (expires_at);

alter table public.cached_photo_urls enable row level security;

-- B2 paths are `{institute_id}/year/roll/...` (see B2BStorageService.generatePhotoPath).
create or replace function public.cached_photo_url_path_allowed(p_object_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select nullif(btrim(coalesce(p_object_path, '')), '') is not null
    and (
      public.is_coder()
      or (
        auth.uid() is not null
        and (
          btrim(p_object_path) like btrim(coalesce(public.current_profile_institute_id(), '')) || '/%'
          or btrim(p_object_path) like btrim(coalesce(public.current_profile_institute_code(), '')) || '/%'
        )
      )
    );
$$;

revoke all on function public.cached_photo_url_path_allowed(text) from public;
grant execute on function public.cached_photo_url_path_allowed(text) to authenticated;

drop policy if exists "authenticated_all_cached_photo_urls" on public.cached_photo_urls;
drop policy if exists "cached_photo_urls_select" on public.cached_photo_urls;
drop policy if exists "cached_photo_urls_insert" on public.cached_photo_urls;
drop policy if exists "cached_photo_urls_update" on public.cached_photo_urls;
drop policy if exists "cached_photo_urls_delete" on public.cached_photo_urls;

create policy "cached_photo_urls_select"
  on public.cached_photo_urls for select
  to authenticated
  using (public.cached_photo_url_path_allowed(object_path));

create policy "cached_photo_urls_insert"
  on public.cached_photo_urls for insert
  to authenticated
  with check (public.cached_photo_url_path_allowed(object_path));

create policy "cached_photo_urls_update"
  on public.cached_photo_urls for update
  to authenticated
  using (public.cached_photo_url_path_allowed(object_path))
  with check (public.cached_photo_url_path_allowed(object_path));

create policy "cached_photo_urls_delete"
  on public.cached_photo_urls for delete
  to authenticated
  using (public.cached_photo_url_path_allowed(object_path));

-- No anon access to signed-URL cache rows.
revoke all on table public.cached_photo_urls from anon;
