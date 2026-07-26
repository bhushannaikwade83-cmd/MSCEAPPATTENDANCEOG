-- Fix portal Admins & Access list: clearer auth check + session diagnostic + re-apply super_admin rows.

-- 1) Re-ensure known website portal auth users are super_admin (run after creating user in Auth dashboard).
insert into public.profiles (id, email, role, status, name, created_at)
select u.id, u.email, 'super_admin', 'approved', 'MSCE Website Admin', now()
from auth.users u
where lower(u.email) in ('admin@gmail.com', 'gcctbcsupport@gmail.com')
on conflict (id) do update
set
  email = excluded.email,
  role = 'super_admin',
  status = 'approved',
  name = coalesce(public.profiles.name, excluded.name);

delete from public.coders
where lower(coalesce(email, '')) in ('admin@gmail.com', 'gcctbcsupport@gmail.com');

-- 2) Who can open the onboarding list (super_admin profile or legacy coder table).
create or replace function public.can_access_portal_onboarding_list()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    auth.uid() is not null
    and (
      public.is_super_admin()
      or public.is_coder()
      or exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and lower(coalesce(p.role, '')) = 'super_admin'
          and lower(coalesce(p.status, '')) in ('approved', 'active', 'pending')
      )
    );
$$;

grant execute on function public.can_access_portal_onboarding_list() to authenticated;

-- 3) Debug helper for the website (shows why list RPC may fail).
create or replace function public.portal_session_info()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_role text;
  v_status text;
  v_institute_id text;
begin
  if v_uid is null then
    return jsonb_build_object(
      'authenticated', false,
      'can_list_onboarding', false,
      'message', 'Not signed in'
    );
  end if;

  select lower(u.email::text) into v_email from auth.users u where u.id = v_uid;

  select p.role, p.status, p.institute_id
  into v_role, v_status, v_institute_id
  from public.profiles p
  where p.id = v_uid;

  return jsonb_build_object(
    'authenticated', true,
    'user_id', v_uid,
    'email', v_email,
    'profile_role', v_role,
    'profile_status', v_status,
    'institute_id', v_institute_id,
    'is_super_admin_fn', public.is_super_admin(),
    'is_coder_fn', public.is_coder(),
    'can_list_onboarding', public.can_access_portal_onboarding_list(),
    'message',
      case
        when public.can_access_portal_onboarding_list() then 'OK — portal onboarding list allowed'
        when v_role is null then 'No profiles row — run migration 058 or insert super_admin profile for this auth user'
        when lower(coalesce(v_role, '')) <> 'super_admin' then
          format('profiles.role is "%s" — website portal needs super_admin (not institute admin)', v_role)
        when lower(coalesce(v_status, '')) not in ('approved', 'active', 'pending') then
          format('profiles.status is "%s" — set to approved', v_status)
        else 'Access denied — contact MSCE tech support'
      end
  );
end;
$$;

grant execute on function public.portal_session_info() to authenticated;

-- 4) Onboarding list uses the relaxed gate.
create or replace function public.list_institute_admin_onboarding_portal()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
  v_info jsonb;
begin
  if not public.can_access_portal_onboarding_list() then
    v_info := public.portal_session_info();
    raise exception '%', coalesce(v_info->>'message', 'Forbidden: super_admin required for portal admin onboarding list');
  end if;

  select coalesce(
    jsonb_agg(row_data order by institute_name nulls last, institute_id),
    '[]'::jsonb
  )
  into v_rows
  from (
    select jsonb_build_object(
      'institute_id', i.id,
      'institute_name', coalesce(nullif(trim(i.name), ''), i.id),
      'institute_code', i.institute_code,
      'institute_active', coalesce(i.is_active, true),
      'invite_id', ai.id,
      'invite_full_name', ai.full_name,
      'invite_phone', ai.phone,
      'invite_email', ai.email,
      'invite_claimed', coalesce(ai.claimed, false),
      'invite_claimed_at', ai.claimed_at,
      'invite_created_at', ai.created_at,
      'profile_id', p.id,
      'profile_name', p.name,
      'profile_email', p.email,
      'profile_phone', p.phone_number,
      'profile_status', p.status,
      'profile_created_at', p.created_at,
      'setup_complete',
        exists (
          select 1
          from public.profiles p2
          where lower(coalesce(p2.role, '')) = 'admin'
            and p2.institute_id = i.id
            and lower(coalesce(p2.status, '')) in ('approved', 'active')
            and nullif(trim(coalesce(p2.email::text, '')), '') is not null
        )
    ) as row_data,
    coalesce(nullif(trim(i.name), ''), i.id) as institute_name,
    i.id as institute_id
    from public.institutes i
    left join lateral (
      select *
      from public.admin_invites ai0
      where ai0.institute_id = i.id
      order by ai0.created_at desc nulls last
      limit 1
    ) ai on true
    left join lateral (
      select *
      from public.profiles p0
      where lower(coalesce(p0.role, '')) = 'admin'
        and p0.institute_id = i.id
      order by p0.created_at desc nulls last
      limit 1
    ) p on true
    where ai.id is not null or p.id is not null
  ) s;

  return v_rows;
end;
$$;

grant execute on function public.list_institute_admin_onboarding_portal() to authenticated;
