-- Admin tamper controls:
-- 1) Immutable audit log for sensitive tables
-- 2) Dual-approval workflow for sensitive override actions
-- 3) MFA + dual-approval enforcement on sensitive state changes
-- 4) Stricter RLS for teacher_attendance and institute_daily_status

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- MFA helper (Supabase JWT AAL claim)
-- ---------------------------------------------------------------------------

create or replace function public.is_mfa_verified()
returns boolean
language sql
stable
as $$
  select coalesce((auth.jwt() ->> 'aal') = 'aal2', false);
$$;

grant execute on function public.is_mfa_verified() to authenticated;

-- ---------------------------------------------------------------------------
-- Immutable audit log
-- ---------------------------------------------------------------------------

create table if not exists public.security_audit_log (
  id uuid primary key default gen_random_uuid(),
  table_name text not null,
  row_pk text not null,
  institute_id text,
  action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  old_data jsonb,
  new_data jsonb,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  context jsonb not null default '{}'::jsonb
);

create index if not exists idx_security_audit_log_inst_time
  on public.security_audit_log (institute_id, changed_at desc);
create index if not exists idx_security_audit_log_table_pk
  on public.security_audit_log (table_name, row_pk, changed_at desc);

alter table public.security_audit_log enable row level security;

drop policy if exists "security_audit_log_select" on public.security_audit_log;
create policy "security_audit_log_select"
  on public.security_audit_log for select
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

drop policy if exists "security_audit_log_insert_deny_clients" on public.security_audit_log;
create policy "security_audit_log_insert_deny_clients"
  on public.security_audit_log for insert
  to authenticated
  with check (false);

drop policy if exists "security_audit_log_update_deny_all" on public.security_audit_log;
create policy "security_audit_log_update_deny_all"
  on public.security_audit_log for update
  to authenticated
  using (false)
  with check (false);

drop policy if exists "security_audit_log_delete_deny_all" on public.security_audit_log;
create policy "security_audit_log_delete_deny_all"
  on public.security_audit_log for delete
  to authenticated
  using (false);

create or replace function public.audit_log_block_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'security_audit_log is immutable';
end;
$$;

drop trigger if exists trg_audit_log_no_update on public.security_audit_log;
create trigger trg_audit_log_no_update
before update on public.security_audit_log
for each row execute function public.audit_log_block_mutation();

drop trigger if exists trg_audit_log_no_delete on public.security_audit_log;
create trigger trg_audit_log_no_delete
before delete on public.security_audit_log
for each row execute function public.audit_log_block_mutation();

-- ---------------------------------------------------------------------------
-- Dual-approval requests for sensitive override operations
-- ---------------------------------------------------------------------------

create table if not exists public.admin_override_requests (
  id uuid primary key default gen_random_uuid(),
  institute_id text not null references public.institutes(id) on delete cascade,
  action_type text not null,
  target_table text not null,
  target_id text not null,
  reason text not null,
  requested_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'expired', 'consumed')),
  approved_by_1 uuid references auth.users(id) on delete set null,
  approved_by_2 uuid references auth.users(id) on delete set null,
  approvals_count int not null default 0,
  approval_notes jsonb not null default '[]'::jsonb,
  approved_at timestamptz,
  consumed_at timestamptz,
  rejected_at timestamptz,
  rejected_by uuid references auth.users(id) on delete set null,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_override_requests_inst_status
  on public.admin_override_requests (institute_id, status, created_at desc);
create index if not exists idx_override_requests_target
  on public.admin_override_requests (institute_id, action_type, target_table, target_id, status);

alter table public.admin_override_requests enable row level security;

drop policy if exists "override_requests_select" on public.admin_override_requests;
create policy "override_requests_select"
  on public.admin_override_requests for select
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

drop policy if exists "override_requests_insert_admin" on public.admin_override_requests;
create policy "override_requests_insert_admin"
  on public.admin_override_requests for insert
  to authenticated
  with check (
    public.is_institute_admin()
    and institute_id = public.current_profile_institute_id()
    and requested_by = auth.uid()
  );

drop policy if exists "override_requests_update_admin" on public.admin_override_requests;
create policy "override_requests_update_admin"
  on public.admin_override_requests for update
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

drop policy if exists "override_requests_delete_coder" on public.admin_override_requests;
create policy "override_requests_delete_coder"
  on public.admin_override_requests for delete
  to authenticated
  using (public.is_coder());

create or replace function public.touch_override_request_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_override_request_updated_at on public.admin_override_requests;
create trigger trg_touch_override_request_updated_at
before update on public.admin_override_requests
for each row execute function public.touch_override_request_updated_at();

-- Create request
create or replace function public.request_admin_override(
  p_institute_id text,
  p_action_type text,
  p_target_table text,
  p_target_id text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_institute_admin() and not public.is_coder() then
    raise exception 'Only institute admins can request overrides';
  end if;

  if not public.is_coder() and p_institute_id <> public.current_profile_institute_id() then
    raise exception 'Institute mismatch';
  end if;

  insert into public.admin_override_requests (
    institute_id, action_type, target_table, target_id, reason, requested_by
  ) values (
    p_institute_id, p_action_type, p_target_table, p_target_id, p_reason, auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.request_admin_override(text, text, text, text, text) to authenticated;

-- Approve request (requires MFA AAL2)
create or replace function public.approve_admin_override(
  p_request_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req public.admin_override_requests%rowtype;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_mfa_verified() then
    raise exception 'MFA verification required (AAL2)';
  end if;

  select * into v_req
  from public.admin_override_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Override request not found';
  end if;

  if v_req.status not in ('pending', 'approved') then
    raise exception 'Request is not approvable (status=%)', v_req.status;
  end if;

  if v_req.expires_at <= now() then
    update public.admin_override_requests
    set status = 'expired'
    where id = p_request_id;
    raise exception 'Request expired';
  end if;

  if not public.is_coder() and v_req.institute_id <> public.current_profile_institute_id() then
    raise exception 'Institute mismatch';
  end if;

  if v_req.requested_by = v_uid then
    raise exception 'Requester cannot self-approve';
  end if;

  if v_req.approved_by_1 = v_uid or v_req.approved_by_2 = v_uid then
    return jsonb_build_object('success', true, 'status', v_req.status, 'approvals_count', v_req.approvals_count);
  end if;

  if v_req.approved_by_1 is null then
    update public.admin_override_requests
    set approved_by_1 = v_uid,
        approvals_count = approvals_count + 1,
        approval_notes = approval_notes || jsonb_build_array(
          jsonb_build_object('approvedBy', v_uid, 'note', coalesce(p_note, ''), 'at', now())
        )
    where id = p_request_id;
  elsif v_req.approved_by_2 is null then
    update public.admin_override_requests
    set approved_by_2 = v_uid,
        approvals_count = approvals_count + 1,
        status = 'approved',
        approved_at = now(),
        approval_notes = approval_notes || jsonb_build_array(
          jsonb_build_object('approvedBy', v_uid, 'note', coalesce(p_note, ''), 'at', now())
        )
    where id = p_request_id;
  end if;

  return (
    select jsonb_build_object(
      'success', true,
      'status', status,
      'approvals_count', approvals_count,
      'approved_at', approved_at
    )
    from public.admin_override_requests
    where id = p_request_id
  );
end;
$$;

grant execute on function public.approve_admin_override(uuid, text) to authenticated;

-- Consume an approved request exactly once
create or replace function public.consume_admin_override_if_approved(
  p_institute_id text,
  p_action_type text,
  p_target_table text,
  p_target_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req_id uuid;
begin
  select id into v_req_id
  from public.admin_override_requests r
  where r.institute_id = p_institute_id
    and r.action_type = p_action_type
    and r.target_table = p_target_table
    and r.target_id = p_target_id
    and r.status = 'approved'
    and r.consumed_at is null
    and r.expires_at > now()
  order by r.approved_at desc nulls last, r.created_at desc
  limit 1
  for update skip locked;

  if v_req_id is null then
    return false;
  end if;

  update public.admin_override_requests
  set consumed_at = now(),
      status = 'consumed'
  where id = v_req_id;

  return true;
end;
$$;

grant execute on function public.consume_admin_override_if_approved(text, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Trigger-based enforcement for sensitive tampering actions
-- ---------------------------------------------------------------------------

create or replace function public.enforce_sensitive_tamper_controls_teacher_attendance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text := old.status;
  v_new_status text := new.status;
  v_inst text := coalesce(new.institute_id, old.institute_id);
  v_ok boolean := false;
begin
  -- Protect finalized auto-absent rows from being converted silently.
  if coalesce(old.payload ->> 'autoMarkedOnInstituteClose', 'false') = 'true'
     and v_old_status = 'absent'
     and v_new_status is distinct from v_old_status then
    if not public.is_mfa_verified() then
      raise exception 'MFA (AAL2) required for changing finalized auto-absent attendance';
    end if;
    v_ok := public.consume_admin_override_if_approved(
      v_inst,
      'attendance_status_override',
      'teacher_attendance',
      old.id
    );
    if not v_ok then
      raise exception 'Dual approval required for finalized attendance status change (request action: attendance_status_override)';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_sensitive_tamper_teacher_attendance on public.teacher_attendance;
create trigger trg_enforce_sensitive_tamper_teacher_attendance
before update on public.teacher_attendance
for each row
execute function public.enforce_sensitive_tamper_controls_teacher_attendance();

create or replace function public.enforce_sensitive_tamper_controls_daily_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text := old.payload ->> 'status';
  v_new_status text := new.payload ->> 'status';
  v_old_finalized boolean := coalesce((old.payload ->> 'dayFinalized')::boolean, false);
  v_ok boolean := false;
begin
  -- Re-open of a finalized day is sensitive: require MFA + dual approval.
  if v_old_finalized and v_old_status = 'closed' and v_new_status = 'open' then
    if not public.is_mfa_verified() then
      raise exception 'MFA (AAL2) required for reopening a finalized day';
    end if;
    v_ok := public.consume_admin_override_if_approved(
      new.institute_id,
      'reopen_finalized_day',
      'institute_daily_status',
      old.id::text
    );
    if not v_ok then
      raise exception 'Dual approval required for reopening finalized day (request action: reopen_finalized_day)';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_sensitive_tamper_daily_status on public.institute_daily_status;
create trigger trg_enforce_sensitive_tamper_daily_status
before update on public.institute_daily_status
for each row
execute function public.enforce_sensitive_tamper_controls_daily_status();

-- ---------------------------------------------------------------------------
-- Audit triggers for sensitive tables
-- ---------------------------------------------------------------------------

create or replace function public.write_security_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_table text := tg_table_name::text;
  v_action text := tg_op::text;
  v_row_pk text;
  v_inst text;
  v_old jsonb;
  v_new jsonb;
begin
  if tg_op = 'INSERT' then
    v_new := to_jsonb(new);
    v_old := null;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
  else
    v_old := to_jsonb(old);
    v_new := null;
  end if;

  v_row_pk := coalesce(v_new ->> 'id', v_old ->> 'id', 'unknown');
  v_inst := coalesce(v_new ->> 'institute_id', v_old ->> 'institute_id');

  insert into public.security_audit_log (
    table_name,
    row_pk,
    institute_id,
    action,
    old_data,
    new_data,
    changed_by,
    context
  ) values (
    v_table,
    v_row_pk,
    v_inst,
    v_action,
    v_old,
    v_new,
    auth.uid(),
    jsonb_build_object(
      'mfaAal2', public.is_mfa_verified(),
      'txid', txid_current()
    )
  );

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_audit_teacher_attendance on public.teacher_attendance;
create trigger trg_audit_teacher_attendance
after insert or update or delete on public.teacher_attendance
for each row execute function public.write_security_audit_log();

drop trigger if exists trg_audit_institute_daily_status on public.institute_daily_status;
create trigger trg_audit_institute_daily_status
after insert or update or delete on public.institute_daily_status
for each row execute function public.write_security_audit_log();

-- ---------------------------------------------------------------------------
-- Stricter RLS for sensitive tables: no direct delete by institute admins
-- ---------------------------------------------------------------------------

drop policy if exists "teacher_attendance_all" on public.teacher_attendance;
drop policy if exists "institute_daily_status_all" on public.institute_daily_status;

create policy "teacher_attendance_select"
  on public.teacher_attendance for select
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "teacher_attendance_insert"
  on public.teacher_attendance for insert
  to authenticated
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id is not null
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "teacher_attendance_update"
  on public.teacher_attendance for update
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

create policy "teacher_attendance_delete_coder_only"
  on public.teacher_attendance for delete
  to authenticated
  using (public.is_coder());

create policy "institute_daily_status_select"
  on public.institute_daily_status for select
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "institute_daily_status_insert"
  on public.institute_daily_status for insert
  to authenticated
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "institute_daily_status_update"
  on public.institute_daily_status for update
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin()
      and institute_id = public.current_profile_institute_id()
    )
  );

create policy "institute_daily_status_delete_coder_only"
  on public.institute_daily_status for delete
  to authenticated
  using (public.is_coder());
