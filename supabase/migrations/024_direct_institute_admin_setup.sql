-- Direct website-provisioned institute admin setup.
-- Website stores institute + admin contact details; app verifies OTP and creates password.

create extension if not exists "pgcrypto";

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'is_coder'
      and pg_get_function_identity_arguments(p.oid) = ''
  ) then
    execute $fn$
      create function public.is_coder()
      returns boolean
      language plpgsql
      stable
      security definer
      set search_path = public
      as $body$
      begin
        if to_regclass('public.coders') is null then
          return false;
        end if;
        return exists (select 1 from public.coders c where c.id = auth.uid());
      end;
      $body$
    $fn$;
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'is_super_admin'
      and pg_get_function_identity_arguments(p.oid) = ''
  ) then
    execute $fn$
      create function public.is_super_admin()
      returns boolean
      language sql
      stable
      security definer
      set search_path = public
      as $body$
        select exists (
          select 1
          from public.profiles p
          where p.id = auth.uid()
            and p.role = 'super_admin'
            and lower(coalesce(p.status, 'approved')) in ('approved', 'active')
        )
        or public.is_coder();
      $body$
    $fn$;
  end if;
end;
$$;

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

create index if not exists idx_admin_invites_institute
  on public.admin_invites (institute_id);

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
    or public.is_super_admin()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.institute_id = public.admin_invites.institute_id
    )
  )
  with check (
    public.is_coder()
    or public.is_super_admin()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.institute_id = public.admin_invites.institute_id
    )
  );

alter table public.admin_invites
  add column if not exists updated_at timestamptz default now();

-- Store/refresh an institute and its single pending admin setup record.
-- Call this from the website while signed in as a coder/super_admin.
create or replace function public.create_institute_admin_setup(
  p_institute_id text,
  p_institute_name text,
  p_institute_address text,
  p_institute_city text,
  p_institute_mobile text,
  p_admin_full_name text,
  p_admin_mobile text,
  p_admin_email text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institute_id text := nullif(btrim(coalesce(p_institute_id, '')), '');
  v_institute_name text := nullif(btrim(coalesce(p_institute_name, '')), '');
  v_admin_name text := nullif(btrim(coalesce(p_admin_full_name, '')), '');
  v_admin_mobile text := nullif(btrim(coalesce(p_admin_mobile, '')), '');
  v_admin_email text := lower(nullif(btrim(coalesce(p_admin_email, '')), ''));
  v_invite_id uuid;
begin
  if not (public.is_coder() or public.is_super_admin()) then
    return json_build_object('success', false, 'message', 'Not authorized');
  end if;

  if v_institute_id is null or v_institute_name is null then
    return json_build_object('success', false, 'message', 'Institute ID and name are required');
  end if;

  if v_institute_id !~ '^[0-9]+$' then
    return json_build_object('success', false, 'message', 'Institute ID must be numeric only');
  end if;

  if v_admin_name is null or v_admin_mobile is null or v_admin_email is null then
    return json_build_object('success', false, 'message', 'Admin name, mobile, and email are required');
  end if;

  if v_admin_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then
    return json_build_object('success', false, 'message', 'Enter a valid admin email');
  end if;

  insert into public.institutes (
    id,
    institute_code,
    name,
    address,
    city,
    mobile_no,
    is_active,
    updated_at
  )
  values (
    v_institute_id,
    v_institute_id,
    v_institute_name,
    nullif(btrim(coalesce(p_institute_address, '')), ''),
    nullif(btrim(coalesce(p_institute_city, '')), ''),
    nullif(btrim(coalesce(p_institute_mobile, '')), ''),
    true,
    now()
  )
  on conflict (id) do update set
    institute_code = excluded.institute_code,
    name = excluded.name,
    address = excluded.address,
    city = excluded.city,
    mobile_no = excluded.mobile_no,
    is_active = true,
    updated_at = now();

  update public.admin_invites
     set full_name = v_admin_name,
         phone = v_admin_mobile,
         email = v_admin_email,
         updated_at = now()
   where institute_id = v_institute_id
     and claimed = false
   returning id into v_invite_id;

  if v_invite_id is null then
    insert into public.admin_invites (
      institute_id,
      full_name,
      phone,
      email,
      claimed,
      claimed_at,
      updated_at
    )
    values (
      v_institute_id,
      v_admin_name,
      v_admin_mobile,
      v_admin_email,
      false,
      null,
      now()
    )
    returning id into v_invite_id;
  end if;

  return json_build_object(
    'success', true,
    'message', 'Institute admin setup saved',
    'institute_id', v_institute_id,
    'invite_id', v_invite_id
  );
end;
$$;

grant execute on function public.create_institute_admin_setup(text, text, text, text, text, text, text, text) to authenticated;

-- Keep the trigger aligned with direct website setup details.
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

  if coalesce(new.raw_user_meta_data->>'website_invite', '') = 'true' or invite_uuid is not null then
    use_status := 'approved';
  else
    use_status := 'pending';
  end if;

  if exists (select 1 from public.profiles p where p.id = new.id) then
    return new;
  end if;

  if invite_uuid is not null then
    select coalesce(nullif(uname, ''), ai.full_name),
           coalesce(nullif(phone, ''), ai.phone),
           coalesce(nullif(iname, ''), i.name)
      into uname, phone, iname
      from public.admin_invites ai
      join public.institutes i on i.id = ai.institute_id
     where ai.id = invite_uuid
       and ai.institute_id = iid
     limit 1;
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
           claimed_at = coalesce(public.admin_invites.claimed_at, now()),
           updated_at = now()
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

drop trigger if exists trg_institute_admin_signup on auth.users;
create trigger trg_institute_admin_signup
  after insert on auth.users
  for each row
  execute function public.handle_institute_admin_signup();

-- Avoid failing login attempts when the optional security_logs table is not present.
create or replace function public.admin_login_by_institute(
  p_institute_key text,
  p_password text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_institute_id text;
  v_password_hash text;
begin
  select i.id into v_institute_id
  from public.institutes i
  where trim(i.id::text) = trim(p_institute_key)
     or trim(coalesce(i.institute_code, '')) = trim(p_institute_key)
  limit 1;

  if v_institute_id is null then
    return json_build_object('success', false, 'message', 'Institute not found');
  end if;

  select p.id into v_profile_id
  from public.profiles p
  where p.institute_id = v_institute_id
    and p.role = 'admin'
    and lower(coalesce(p.status, '')) in ('approved', 'active')
  order by p.last_login desc nulls last, p.created_at desc
  limit 1;

  if v_profile_id is null then
    return json_build_object('success', false, 'message', 'No active admin found for this institute');
  end if;

  select ap.password_hash into v_password_hash
  from public.admin_passwords ap
  where ap.profile_id = v_profile_id;

  if v_password_hash is null then
    return json_build_object('success', false, 'message', 'Admin password not set up');
  end if;

  if not (v_password_hash = crypt(p_password, v_password_hash)) then
    begin
      if to_regclass('public.security_logs') is not null then
        insert into public.security_logs (action, details, created_at)
        values (
          'admin_login_failed',
          json_build_object('institute_id', v_institute_id, 'reason', 'invalid_password'),
          now()
        );
      end if;
    exception when others then
      null;
    end;

    return json_build_object('success', false, 'message', 'Invalid password');
  end if;

  return json_build_object(
    'success', true,
    'profile_id', v_profile_id,
    'institute_id', v_institute_id,
    'message', 'Login successful'
  );
end;
$$;

grant execute on function public.admin_login_by_institute(text, text) to anon, authenticated;
