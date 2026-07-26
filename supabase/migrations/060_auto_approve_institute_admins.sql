-- Institute admins sign in immediately after password setup — no manual portal approval.

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

-- Existing admins stuck on pending can sign in after this migration.
update public.profiles p
set status = 'approved'
where p.role = 'admin'
  and lower(coalesce(p.status, '')) = 'pending';
