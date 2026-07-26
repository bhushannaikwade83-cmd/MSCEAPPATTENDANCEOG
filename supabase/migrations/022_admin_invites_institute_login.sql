-- Website-provisioned admin onboarding + institute-key login resolution.
-- anon can read pending invites (for app onboarding only).

create extension if not exists "pgcrypto";

create table if not exists public.admin_invites (
  id uuid primary key default gen_random_uuid(),
  institute_id text not null references public.institutes(id) on delete cascade,
  full_name text not null,
  phone text not null,
  email text not null,
  claimed boolean not null default false,
  claimed_at timestamptz,
  created_at timestamptz default now()
);

create unique index if not exists ux_admin_invites_institute_pending
  on public.admin_invites (institute_id)
  where claimed = false;

create index if not exists idx_admin_invites_institute on public.admin_invites (institute_id);

alter table public.admin_invites enable row level security;

drop policy if exists "admin_invites_select_anon_unclaimed" on public.admin_invites;
create policy "admin_invites_select_anon_unclaimed"
  on public.admin_invites for select
  to anon
  using (claimed = false);

drop policy if exists "admin_invites_auth_coders" on public.admin_invites;
create policy "admin_invites_auth_coders"
  on public.admin_invites for all
  to authenticated
  using (
    public.is_coder()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.institute_id = public.admin_invites.institute_id
    )
  )
  with check (
    public.is_coder()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.institute_id = public.admin_invites.institute_id
    )
  );

-- Resolve Supabase login email from institute id or institute_code (caller uses password separately).
create or replace function public.get_admin_email_for_institute_login(p_key text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select trim(p.email::text)
  from public.profiles p
  join public.institutes i on i.id = p.institute_id
  where p.role = 'admin'
    and nullif(trim(p.email::text), '') is not null
    and lower(coalesce(p.status,'')) in ('approved','active')
    and (
      trim(i.id::text) = trim(p_key)
      or trim(coalesce(i.institute_code,'')) = trim(p_key)
    )
  order by p.last_login desc nulls last, p.created_at desc
  limit 1;
$$;

grant execute on function public.get_admin_email_for_institute_login(text) to anon, authenticated;

-- Replace signup trigger: honor website invite metadata + approve + claim invite row.

create or replace function public.handle_institute_admin_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  iid text;
  iname text;
  uname text;
  phone text;
  invite_uuid uuid;
  use_status text;
begin
  iid := nullif(btrim(coalesce(new.raw_user_meta_data->>'institute_id', '')), '');
  if iid is null then
    return new;
  end if;

  iname := coalesce(new.raw_user_meta_data->>'institute_name', '');
  uname := coalesce(new.raw_user_meta_data->>'name', '');
  phone := coalesce(new.raw_user_meta_data->>'phone_number', '');

  begin
    invite_uuid := (nullif(btrim(coalesce(new.raw_user_meta_data->>'invite_id', '')), ''))::uuid;
  exception when others then
    invite_uuid := null;
  end;

  if coalesce(new.raw_user_meta_data->>'website_invite', '') = 'true' then
    use_status := 'approved';
  elsif invite_uuid is not null then
    use_status := 'approved';
  else
    use_status := 'pending';
  end if;

  if exists (select 1 from public.profiles p where p.id = new.id) then
    return new;
  end if;

  insert into public.profiles (
    id,
    email,
    name,
    role,
    institute_id,
    institute_name,
    phone_number,
    status,
    created_at,
    last_login
  )
  values (
    new.id,
    new.email,
    uname,
    'admin',
    iid,
    iname,
    phone,
    use_status,
    now(),
    null
  );

  if invite_uuid is not null then
    update public.admin_invites
       set claimed = true,
           claimed_at = coalesce(public.admin_invites.claimed_at, now())
     where id = invite_uuid
       and institute_id = iid
       and claimed = false;
  end if;

  if not exists (select 1 from public.user_credentials where profile_id = new.id) then
    insert into public.user_credentials (institute_id, profile_id, email, email_sent)
    values (iid, new.id, new.email, false);
  end if;

  return new;
end;
$$;

