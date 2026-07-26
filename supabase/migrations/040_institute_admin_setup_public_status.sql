-- Onboarding UX: anon cannot read claimed admin_invites or profiles, but the app must show
-- "admin already registered" instead of "no pending website registration".

create or replace function public.institute_admin_setup_public_status(p_institute_id text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'setup_complete',
    exists (
      select 1
      from public.profiles p
      where p.role = 'admin'
        and p.institute_id = trim(p_institute_id)
        and lower(coalesce(p.status, '')) in ('approved', 'active')
        and nullif(trim(p.email::text), '') is not null
    ),
    'registered_admin_name',
    case
      when exists (
        select 1
        from public.profiles p
        where p.role = 'admin'
          and p.institute_id = trim(p_institute_id)
          and lower(coalesce(p.status, '')) in ('approved', 'active')
          and nullif(trim(p.email::text), '') is not null
          and nullif(trim(coalesce(p.name, '')), '') is not null
      )
      then (
        select trim(coalesce(p.name, ''))
        from public.profiles p
        where p.role = 'admin'
          and p.institute_id = trim(p_institute_id)
          and lower(coalesce(p.status, '')) in ('approved', 'active')
          and nullif(trim(p.email::text), '') is not null
        order by p.last_login desc nulls last, p.created_at desc
        limit 1
      )
      else 'Registered administrator'
    end,
    'invite_claimed',
    exists (
      select 1
      from public.admin_invites ai
      where ai.institute_id = trim(p_institute_id)
        and ai.claimed = true
    )
  );
$$;

grant execute on function public.institute_admin_setup_public_status(text) to anon, authenticated;
