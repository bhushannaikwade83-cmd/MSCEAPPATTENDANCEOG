-- Portal login: gcctbcsupport@gmail.com (and admin@gmail.com) auto-get super_admin profile.
-- Call from website after sign-in via sync_allowlisted_portal_super_admin().

create or replace function public.sync_allowlisted_portal_super_admin()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Not signed in');
  end if;

  select lower(u.email::text) into v_email
  from auth.users u
  where u.id = v_uid;

  if v_email is null or v_email not in ('gcctbcsupport@gmail.com', 'admin@gmail.com') then
    return jsonb_build_object(
      'ok', false,
      'message', 'This sync only applies to MSCE portal accounts (gcctbcsupport@gmail.com / admin@gmail.com)',
      'email', v_email
    );
  end if;

  insert into public.profiles (id, email, role, status, name, institute_id, institute_name, created_at)
  select
    u.id,
    u.email,
    'super_admin',
    'approved',
    case when v_email = 'gcctbcsupport@gmail.com' then 'MSCE Website Support' else 'MSCE Website Admin' end,
    null,
    null,
    now()
  from auth.users u
  where u.id = v_uid
  on conflict (id) do update
  set
    email = excluded.email,
    role = 'super_admin',
    status = 'approved',
    name = excluded.name,
    institute_id = null,
    institute_name = null;

  delete from public.coders where lower(coalesce(email, '')) = v_email;

  return jsonb_build_object(
    'ok', true,
    'message', 'Portal super_admin profile synced',
    'session', public.portal_session_info()
  );
end;
$$;

grant execute on function public.sync_allowlisted_portal_super_admin() to authenticated;
