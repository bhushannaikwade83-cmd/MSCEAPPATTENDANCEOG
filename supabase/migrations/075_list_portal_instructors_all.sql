-- MSCE website: list all institute instructors (attendance_user) across institutes.
-- Bypasses profiles RLS edge cases; same gate as portal onboarding list.

create or replace function public.list_portal_instructors_all()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'email', p.email,
        'phone_number', p.phone_number,
        'status', p.status,
        'institute_id', p.institute_id,
        'created_at', p.created_at,
        'last_login', p.last_login,
        'has_pin', coalesce(p.has_pin, false)
          or (p.pin_hash is not null and length(btrim(p.pin_hash)) > 0),
        'pin_set_at', p.pin_set_at,
        'institute_uuid', i.id,
        'institute_code', coalesce(nullif(btrim(i.institute_code), ''), i.id),
        'institute_name', coalesce(nullif(btrim(i.name), ''), i.id),
        'institute_active', i.is_active
      )
      order by coalesce(nullif(btrim(i.institute_code), ''), i.id), p.name
    ),
    '[]'::jsonb
  )
  from public.profiles p
  left join public.institutes i
    on i.id = p.institute_id
    or i.institute_code = p.institute_id
  where p.role = 'attendance_user'
    and public.can_access_portal_onboarding_list();
$$;

revoke all on function public.list_portal_instructors_all() from public;
grant execute on function public.list_portal_instructors_all() to authenticated;
