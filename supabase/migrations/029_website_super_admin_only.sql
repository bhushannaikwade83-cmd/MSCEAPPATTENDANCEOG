-- Website portal should use only a super_admin-style account, not coder roles.

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
  if not public.is_super_admin() then
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

drop policy if exists "admin_invites_auth_coders" on public.admin_invites;
drop policy if exists "admin_invites_auth_super_admins" on public.admin_invites;
create policy "admin_invites_auth_super_admins"
  on public.admin_invites for all
  to authenticated
  using (
    public.is_super_admin()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.institute_id = public.admin_invites.institute_id
    )
  )
  with check (
    public.is_super_admin()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and p.role = 'admin'
        and p.institute_id = public.admin_invites.institute_id
    )
  );

-- Optional helper: if auth user admin@gmail.com exists, make it the website super admin.
insert into public.profiles (
  id,
  email,
  role,
  status,
  name,
  created_at
)
select
  u.id,
  u.email,
  'super_admin',
  'approved',
  'Website Admin',
  now()
from auth.users u
where lower(u.email) = 'admin@gmail.com'
on conflict (id) do update
set
  email = excluded.email,
  role = 'super_admin',
  status = 'approved',
  name = excluded.name;

delete from public.coders
where lower(coalesce(email, '')) = 'admin@gmail.com';
