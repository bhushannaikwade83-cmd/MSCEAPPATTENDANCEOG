-- Attendance staff: no username — one account per institute, login = Institute ID + PIN.
-- Email: att.{institute_id}@staff.msce-attendance.app (see app AttendanceStaffAuth).

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
  app_role text;
  full_name text;
begin
  iid := nullif(btrim(coalesce(new.raw_user_meta_data->>'institute_id', '')), '');
  app_role := nullif(lower(btrim(coalesce(new.raw_user_meta_data->>'app_role', ''))), '');

  if app_role = 'attendance_user' and iid is not null then
    if exists (select 1 from public.profiles p where p.id = new.id) then
      return new;
    end if;

    full_name := coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'), ''), 'Staff');
    iname := coalesce(new.raw_user_meta_data->>'institute_name', '');

    insert into public.profiles (
      id,
      email,
      name,
      role,
      institute_id,
      institute_name,
      user_id,
      phone_number,
      status,
      has_pin,
      created_at,
      last_login
    )
    values (
      new.id,
      new.email,
      full_name,
      'attendance_user',
      iid,
      iname,
      null,
      null,
      'active',
      true,
      now(),
      null
    );

    return new;
  end if;

  if iid is null then
    return new;
  end if;

  iname := coalesce(new.raw_user_meta_data->>'institute_name', '');
  uname := coalesce(new.raw_user_meta_data->>'name', '');
  phone := coalesce(new.raw_user_meta_data->>'phone_number', '');

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
    'pending',
    now(),
    null
  );

  if not exists (select 1 from public.user_credentials where profile_id = new.id) then
    insert into public.user_credentials (institute_id, profile_id, email, email_sent)
    values (iid, new.id, new.email, false);
  end if;

  return new;
end;
$$;
