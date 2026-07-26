-- Admin institute-based password authentication (Institute ID + Password login)
-- Replaces email-based authentication for admins

create extension if not exists "pgcrypto";

create table if not exists public.admin_passwords (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  institute_id text not null references public.institutes(id) on delete cascade,
  password_hash text not null, -- bcrypt hash (12+ rounds)
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists idx_admin_passwords_institute on public.admin_passwords (institute_id);
create index if not exists idx_admin_passwords_profile on public.admin_passwords (profile_id);

alter table public.admin_passwords enable row level security;

-- Only authenticated admins can read/update their own password record
drop policy if exists "admin_passwords_own_access" on public.admin_passwords;
create policy "admin_passwords_own_access"
  on public.admin_passwords
  for all
  to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- Coders can manage all admin passwords
drop policy if exists "admin_passwords_coder_access" on public.admin_passwords;
create policy "admin_passwords_coder_access"
  on public.admin_passwords
  for all
  to authenticated
  using (public.is_coder())
  with check (public.is_coder());

-- Function to verify admin login by institute_id + password
-- Returns: {success: bool, profile_id: uuid, message: string}
create or replace function public.admin_login_by_institute(
  p_institute_key text,  -- numeric institute_id or institute_code
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
  v_status text;
  v_role text;
begin
  -- Step 1: Resolve institute_id from key (numeric ID or code)
  select i.id into v_institute_id
  from public.institutes i
  where trim(i.id::text) = trim(p_institute_key)
     or trim(coalesce(i.institute_code, '')) = trim(p_institute_key)
  limit 1;

  if v_institute_id is null then
    return json_build_object(
      'success', false,
      'message', 'Institute not found'
    );
  end if;

  -- Step 2: Find admin profile for this institute
  select p.id, p.status, p.role into v_profile_id, v_status, v_role
  from public.profiles p
  where p.institute_id = v_institute_id
    and p.role = 'admin'
    and p.status in ('approved', 'active')
  limit 1;

  if v_profile_id is null then
    return json_build_object(
      'success', false,
      'message', 'No active admin found for this institute'
    );
  end if;

  -- Step 3: Fetch password hash
  select ap.password_hash into v_password_hash
  from public.admin_passwords ap
  where ap.profile_id = v_profile_id;

  if v_password_hash is null then
    return json_build_object(
      'success', false,
      'message', 'Admin password not set up'
    );
  end if;

  -- Step 4: Verify password (using crypt extension)
  if not (v_password_hash = crypt(p_password, v_password_hash)) then
    -- Log failed attempt if this optional table exists.
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

    return json_build_object(
      'success', false,
      'message', 'Invalid password'
    );
  end if;

  -- Step 5: Success - return profile info
  return json_build_object(
    'success', true,
    'profile_id', v_profile_id,
    'institute_id', v_institute_id,
    'message', 'Login successful'
  );
end;
$$;

grant execute on function public.admin_login_by_institute(text, text) to anon, authenticated;

-- Function to set admin password (during registration or reset)
create or replace function public.set_admin_password(
  p_profile_id uuid,
  p_new_password text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institute_id text;
  v_password_hash text;
begin
  -- Verify caller is the admin or a coder
  if not (auth.uid() = p_profile_id or public.is_coder()) then
    return json_build_object(
      'success', false,
      'message', 'Not authorized to set this password'
    );
  end if;

  -- Validate password strength (8+ chars)
  if length(p_new_password) < 8 then
    return json_build_object(
      'success', false,
      'message', 'Password must be at least 8 characters'
    );
  end if;

  -- Get institute_id
  select institute_id into v_institute_id
  from public.profiles
  where id = p_profile_id;

  if v_institute_id is null then
    return json_build_object(
      'success', false,
      'message', 'Profile not found'
    );
  end if;

  -- Hash password using bcrypt (12 rounds)
  v_password_hash := crypt(p_new_password, gen_salt('bf', 12));

  -- Insert or update password
  insert into public.admin_passwords (profile_id, institute_id, password_hash)
  values (p_profile_id, v_institute_id, v_password_hash)
  on conflict (profile_id) do update set
    password_hash = excluded.password_hash,
    updated_at = now();

  return json_build_object(
    'success', true,
    'message', 'Password set successfully'
  );
end;
$$;

grant execute on function public.set_admin_password(uuid, text) to authenticated;
