-- Website Admins & Access: single source of truth for invite + profile onboarding.
-- Bypasses RLS safely for super_admin only (security definer).

create or replace function public.list_institute_admin_onboarding_portal()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.is_super_admin() then
    raise exception 'Forbidden: super_admin role required for portal admin onboarding list';
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
