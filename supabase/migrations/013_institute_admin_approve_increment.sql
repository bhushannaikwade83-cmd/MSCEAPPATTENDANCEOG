-- When an institute admin is approved (pending → approved/active), bump institutes.user_count.
-- Signup (012) no longer increments user_count until approval.

create or replace function public.handle_profile_admin_approved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from 'admin' or new.institute_id is null then
    return new;
  end if;
  if lower(coalesce(new.status, '')) not in ('approved', 'active') then
    return new;
  end if;
  if lower(coalesce(old.status, '')) in ('approved', 'active') then
    return new;
  end if;

  update public.institutes
  set user_count = coalesce(user_count, 0) + 1,
      updated_at = now()
  where id = new.institute_id;

  return new;
end;
$$;

drop trigger if exists trg_profile_admin_approved on public.profiles;
create trigger trg_profile_admin_approved
  after update on public.profiles
  for each row
  execute function public.handle_profile_admin_approved();
