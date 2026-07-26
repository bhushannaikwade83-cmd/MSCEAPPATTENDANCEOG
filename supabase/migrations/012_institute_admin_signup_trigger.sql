-- Institute admin self-registration from the mobile app:
-- When "Confirm email" is enabled, signUp() often returns no session, so RLS blocks
-- client inserts into profiles / user_credentials. This trigger runs as SECURITY DEFINER
-- on auth.users insert when raw_user_meta_data contains institute_id.

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
begin
  iid := nullif(btrim(coalesce(new.raw_user_meta_data->>'institute_id', '')), '');
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

  -- user_count is incremented when status becomes approved/active (see migration 013).

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

drop policy if exists "user_credentials_insert_own" on public.user_credentials;
create policy "user_credentials_insert_own"
  on public.user_credentials for insert
  to authenticated
  with check (profile_id = auth.uid());
