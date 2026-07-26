-- When an attendance_user Auth row is created, refresh profile name/phone if a stub row
-- already exists (edge function also upserts; this keeps trigger-only signups correct).

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
  invite_uuid uuid;
begin
  iid := nullif(btrim(coalesce(new.raw_user_meta_data->>'institute_id', '')), '');
  app_role := nullif(lower(btrim(coalesce(new.raw_user_meta_data->>'app_role', ''))), '');

  if app_role = 'attendance_user' and iid is not null then
    full_name := coalesce(nullif(btrim(new.raw_user_meta_data->>'full_name'), ''), 'Staff');
    iname := coalesce(new.raw_user_meta_data->>'institute_name', '');
    phone := nullif(btrim(coalesce(new.raw_user_meta_data->>'phone_number', '')), '');

    if exists (select 1 from public.profiles p where p.id = new.id) then
      update public.profiles
         set name = coalesce(nullif(btrim(full_name), ''), name),
             email = coalesce(new.email, email),
             institute_id = coalesce(iid, institute_id),
             institute_name = coalesce(iname, institute_name),
             phone_number = coalesce(phone, phone_number),
             role = 'attendance_user',
             status = case
               when lower(coalesce(status, '')) in ('approved', 'active') then status
               else 'active'
             end,
             has_pin = true
       where id = new.id;
      return new;
    end if;

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
      phone,
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

  begin
    invite_uuid := (nullif(btrim(coalesce(new.raw_user_meta_data->>'invite_id', '')), ''))::uuid;
  exception when others then
    invite_uuid := null;
  end;

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
    'approved',
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

-- Repair existing instructors: restore full name from Auth metadata when profile.name is short/empty.
update public.profiles p
   set name = coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'), ''), p.name),
       phone_number = coalesce(
         nullif(btrim(u.raw_user_meta_data->>'phone_number'), ''),
         p.phone_number
       )
  from auth.users u
 where p.id = u.id
   and p.role = 'attendance_user'
   and coalesce(u.raw_user_meta_data->>'app_role', '') = 'attendance_user'
   and (
     p.name is null
     or btrim(p.name) = ''
     or p.name = 'Staff'
     or length(btrim(p.name)) < length(coalesce(nullif(btrim(u.raw_user_meta_data->>'full_name'), ''), p.name))
   );
