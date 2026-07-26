-- Security operations hardening:
-- - Auth rate limit + lockout controls
-- - Security incidents store
-- - RPCs for app-side enforcement / incident reporting

create extension if not exists pgcrypto;

create table if not exists public.auth_rate_limits (
  id uuid primary key default gen_random_uuid(),
  identifier text not null,
  action_type text not null,
  success boolean not null default false,
  institute_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_auth_rate_limits_lookup
  on public.auth_rate_limits (identifier, action_type, created_at desc);

create table if not exists public.auth_lockouts (
  id uuid primary key default gen_random_uuid(),
  identifier text not null,
  action_type text not null,
  locked_until timestamptz not null,
  reason text,
  institute_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (identifier, action_type)
);

create index if not exists idx_auth_lockouts_active
  on public.auth_lockouts (identifier, action_type, locked_until desc);

create table if not exists public.security_incidents (
  id uuid primary key default gen_random_uuid(),
  institute_id text,
  category text not null,
  severity text not null default 'medium'
    check (severity in ('low', 'medium', 'high', 'critical')),
  title text not null,
  description text,
  status text not null default 'open'
    check (status in ('open', 'investigating', 'resolved', 'ignored')),
  actor_user_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists idx_security_incidents_inst_time
  on public.security_incidents (institute_id, created_at desc);
create index if not exists idx_security_incidents_status
  on public.security_incidents (status, severity, created_at desc);

alter table public.auth_rate_limits enable row level security;
alter table public.auth_lockouts enable row level security;
alter table public.security_incidents enable row level security;

drop policy if exists "auth_rate_limits_select" on public.auth_rate_limits;
create policy "auth_rate_limits_select"
  on public.auth_rate_limits for select
  to authenticated
  using (public.is_coder());

drop policy if exists "auth_rate_limits_insert" on public.auth_rate_limits;
create policy "auth_rate_limits_insert"
  on public.auth_rate_limits for insert
  to authenticated
  with check (public.is_coder());

drop policy if exists "auth_lockouts_select" on public.auth_lockouts;
create policy "auth_lockouts_select"
  on public.auth_lockouts for select
  to authenticated
  using (public.is_coder());

drop policy if exists "auth_lockouts_write" on public.auth_lockouts;
create policy "auth_lockouts_write"
  on public.auth_lockouts for all
  to authenticated
  using (public.is_coder())
  with check (public.is_coder());

drop policy if exists "security_incidents_select" on public.security_incidents;
create policy "security_incidents_select"
  on public.security_incidents for select
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

drop policy if exists "security_incidents_insert" on public.security_incidents;
create policy "security_incidents_insert"
  on public.security_incidents for insert
  to authenticated
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and (
        institute_id is null
        or institute_id = public.current_profile_institute_id()
      )
    )
  );

drop policy if exists "security_incidents_update" on public.security_incidents;
create policy "security_incidents_update"
  on public.security_incidents for update
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

create or replace function public.is_auth_locked(
  p_identifier text,
  p_action_type text
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.auth_lockouts l
    where l.identifier = p_identifier
      and l.action_type = p_action_type
      and l.locked_until > now()
  );
$$;

grant execute on function public.is_auth_locked(text, text) to authenticated, anon;

create or replace function public.record_auth_attempt(
  p_identifier text,
  p_action_type text,
  p_success boolean,
  p_institute_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_window interval := interval '15 minutes';
  v_fail_count int := 0;
  v_lock_minutes int := 0;
  v_locked_until timestamptz;
begin
  insert into public.auth_rate_limits (
    identifier, action_type, success, institute_id, metadata, created_at
  ) values (
    p_identifier, p_action_type, p_success, p_institute_id, coalesce(p_metadata, '{}'::jsonb), v_now
  );

  -- Keep table bounded (rolling 30 days)
  delete from public.auth_rate_limits
  where created_at < (v_now - interval '30 days');

  if p_success then
    delete from public.auth_lockouts
    where identifier = p_identifier and action_type = p_action_type;
    return jsonb_build_object('success', true, 'locked', false, 'fail_count', 0);
  end if;

  select count(*) into v_fail_count
  from public.auth_rate_limits
  where identifier = p_identifier
    and action_type = p_action_type
    and success = false
    and created_at >= (v_now - v_window);

  if v_fail_count >= 10 then
    v_lock_minutes := 60;
  elsif v_fail_count >= 7 then
    v_lock_minutes := 30;
  elsif v_fail_count >= 5 then
    v_lock_minutes := 15;
  end if;

  if v_lock_minutes > 0 then
    v_locked_until := v_now + make_interval(mins => v_lock_minutes);
    insert into public.auth_lockouts (
      identifier, action_type, locked_until, reason, institute_id, metadata, created_at, updated_at
    ) values (
      p_identifier,
      p_action_type,
      v_locked_until,
      format('Too many failed attempts (%s in 15 minutes)', v_fail_count),
      p_institute_id,
      jsonb_build_object('failCount', v_fail_count, 'lockMinutes', v_lock_minutes) || coalesce(p_metadata, '{}'::jsonb),
      v_now,
      v_now
    )
    on conflict (identifier, action_type)
    do update set
      locked_until = excluded.locked_until,
      reason = excluded.reason,
      institute_id = excluded.institute_id,
      metadata = excluded.metadata,
      updated_at = v_now;
  end if;

  return jsonb_build_object(
    'success', true,
    'locked', v_lock_minutes > 0,
    'lock_minutes', v_lock_minutes,
    'fail_count', v_fail_count
  );
end;
$$;

grant execute on function public.record_auth_attempt(text, text, boolean, text, jsonb)
  to authenticated, anon;

create or replace function public.report_security_incident(
  p_institute_id text,
  p_category text,
  p_severity text,
  p_title text,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.security_incidents (
    institute_id, category, severity, title, description, actor_user_id, metadata, created_at
  ) values (
    p_institute_id,
    p_category,
    coalesce(nullif(trim(p_severity), ''), 'medium'),
    p_title,
    p_description,
    auth.uid(),
    coalesce(p_metadata, '{}'::jsonb),
    now()
  )
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.report_security_incident(text, text, text, text, text, jsonb)
  to authenticated, anon;
