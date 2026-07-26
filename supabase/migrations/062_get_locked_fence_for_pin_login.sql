-- Instructor / admin PIN login runs before Supabase auth: client uses anon key.
-- RLS on gps_settings only allows authenticated roles, so fence reads return 0 rows.
-- This SECURITY DEFINER RPC returns only the locked fence point (+ admin_id for gate logic).

create or replace function public.get_locked_fence_for_pin_login(p_institute_key text)
returns table (latitude double precision, longitude double precision, admin_id text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  k text;
  canon_id text;
  inst_code text;
begin
  k := trim(p_institute_key);
  if k = '' then
    return;
  end if;

  select i.id::text, nullif(trim(both from i.institute_code::text), '')
  into canon_id, inst_code
  from public.institutes i
  where i.id::text = k
     or trim(both from i.institute_code::text) = k
  limit 1;

  return query
  select
    g.latitude::double precision,
    g.longitude::double precision,
    g.admin_id::text
  from public.gps_settings g
  where g.is_locked = true
    and g.latitude is not null
    and g.longitude is not null
    and (abs(g.latitude) > 1e-9 or abs(g.longitude) > 1e-9)
    and (
      trim(both from g.institute_id::text) = k
      or (canon_id is not null and trim(both from g.institute_id::text) = canon_id)
      or (inst_code is not null and trim(both from g.institute_id::text) = inst_code)
    )
  order by g.locked_at desc nulls last
  limit 1;
end;
$$;

revoke all on function public.get_locked_fence_for_pin_login(text) from public;
grant execute on function public.get_locked_fence_for_pin_login(text) to anon, authenticated;

comment on function public.get_locked_fence_for_pin_login(text) is
  'Locked attendance fence for PIN login (institute UUID or institute_code). Callable by anon.';

-- Rows often use institute_code in gps_settings.institute_id (e.g. "99099") while profiles use UUID.
drop policy if exists "gps_settings_all" on public.gps_settings;
create policy "gps_settings_all"
  on public.gps_settings for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and (
        institute_id = public.current_profile_institute_id()
        or institute_id = public.current_profile_institute_code()
      )
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and (
        institute_id = public.current_profile_institute_id()
        or institute_id = public.current_profile_institute_code()
      )
    )
  );

drop policy if exists "gps_settings_select_attendance_user" on public.gps_settings;
create policy "gps_settings_select_attendance_user"
  on public.gps_settings for select
  to authenticated
  using (
    public.is_attendance_user()
    and (
      institute_id = public.current_profile_institute_id()
      or institute_id = public.current_profile_institute_code()
    )
  );
