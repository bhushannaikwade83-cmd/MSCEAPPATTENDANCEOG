-- Database performance for ~3k DAU: indexes for hot paths + lightweight dashboard RPC.
-- Safe to re-run (IF NOT EXISTS). Run ANALYZE after deploy.

-- ---------------------------------------------------------------------------
-- Students: roll / sr_no lookups within an institute (attendance, registration)
-- ---------------------------------------------------------------------------
create index if not exists idx_students_institute_sr_no
  on public.students (institute_id, sr_no)
  where sr_no is not null and btrim(sr_no) <> '';

create index if not exists idx_students_institute_user_id
  on public.students (institute_id, user_id)
  where user_id is not null and btrim(user_id) <> '';

-- ---------------------------------------------------------------------------
-- attendance_in_out: daily institute roster + per-student history
-- ---------------------------------------------------------------------------
create index if not exists idx_att_in_out_inst_date_sr
  on public.attendance_in_out (institute_code, attendance_date, sr_no);

create index if not exists idx_att_in_out_inst_date_student
  on public.attendance_in_out (institute_code, attendance_date, student_id);

-- teacher_attendance: composite covers institute+date filter + student_id map
create index if not exists idx_teacher_att_inst_date_student
  on public.teacher_attendance (institute_id, date, student_id);

-- ---------------------------------------------------------------------------
-- profiles: instructors per institute (admin list + count RPC)
-- ---------------------------------------------------------------------------
create index if not exists idx_profiles_attendance_user_institute
  on public.profiles (institute_id)
  where role = 'attendance_user';

-- ---------------------------------------------------------------------------
-- institutes: resolve id <-> code without seq scan
-- ---------------------------------------------------------------------------
create index if not exists idx_institutes_code
  on public.institutes (institute_code)
  where institute_code is not null and btrim(institute_code) <> '';

-- ---------------------------------------------------------------------------
-- institute_daily_status: polled by institute_status_service
-- ---------------------------------------------------------------------------
create index if not exists idx_institute_daily_status_inst_date
  on public.institute_daily_status (institute_id, date)
  where institute_id is not null;

-- ---------------------------------------------------------------------------
-- RPC: one round-trip for admin dashboard counts (avoids SELECT all ids)
-- ---------------------------------------------------------------------------
create or replace function public.institute_dashboard_stats(
  p_institute_key text,
  p_date date default (current_date)
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_inst_id text;
  v_code text;
  v_date text := to_char(p_date, 'YYYY-MM-DD');
  v_students int := 0;
  v_in_out_rows int := 0;
  v_distinct_marked int := 0;
begin
  if btrim(coalesce(p_institute_key, '')) = '' then
    return jsonb_build_object(
      'student_count', 0,
      'today_in_out_rows', 0,
      'today_distinct_students', 0,
      'attendance_date', v_date
    );
  end if;

  if not (
    public.is_super_admin()
    or public.is_coder()
    or (
      public.is_institute_admin()
      and public.profile_institute_matches(p_institute_key)
    )
    or (
      exists (
        select 1 from public.profiles p
        where p.id = auth.uid()
          and p.role = 'attendance_user'
          and public.profile_institute_matches(p_institute_key)
      )
    )
  ) then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  select i.id::text,
         coalesce(nullif(btrim(i.institute_code), ''), i.id::text)
    into v_inst_id, v_code
  from public.institutes i
  where i.id::text = btrim(p_institute_key)
     or i.institute_code = btrim(p_institute_key)
  limit 1;

  if v_inst_id is null then
    return jsonb_build_object(
      'student_count', 0,
      'today_in_out_rows', 0,
      'today_distinct_students', 0,
      'attendance_date', v_date
    );
  end if;

  select count(*)::int
    into v_students
  from public.students s
  where s.institute_id = v_inst_id;

  select count(*)::int,
         count(distinct coalesce(nullif(btrim(a.sr_no), ''), a.student_id::text))::int
    into v_in_out_rows, v_distinct_marked
  from public.attendance_in_out a
  where a.attendance_date = v_date
    and (
      a.institute_code = v_code
      or a.institute_code = v_inst_id
    );

  return jsonb_build_object(
    'student_count', v_students,
    'today_in_out_rows', v_in_out_rows,
    'today_distinct_students', v_distinct_marked,
    'attendance_date', v_date,
    'institute_id', v_inst_id,
    'institute_code', v_code
  );
end;
$$;

revoke all on function public.institute_dashboard_stats(text, date) from public;
grant execute on function public.institute_dashboard_stats(text, date) to authenticated;

-- Refresh planner stats after new indexes.
analyze public.students;
analyze public.attendance_in_out;
analyze public.teacher_attendance;
analyze public.profiles;
analyze public.institutes;
