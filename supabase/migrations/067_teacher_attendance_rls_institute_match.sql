-- Fix RLS violations on teacher_attendance when marking attendance.
-- Rows often store institutes.institute_code in teacher_attendance.institute_id while
-- profiles.institute_id may be institutes.id (or vice versa). Mirror gps_settings fix (062).
-- Also consolidate split policies from 015 + 030 and allow enrolled students self-mark.

create or replace function public.teacher_attendance_institute_matches(p_institute_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select nullif(btrim(coalesce(p_institute_id, '')), '') is not null
    and (
      btrim(p_institute_id) = nullif(btrim(coalesce(public.current_profile_institute_id(), '')), '')
      or btrim(p_institute_id) = nullif(btrim(coalesce(public.current_profile_institute_code(), '')), '')
    );
$$;

revoke all on function public.teacher_attendance_institute_matches(text) from public;
grant execute on function public.teacher_attendance_institute_matches(text) to authenticated;

create or replace function public.student_owns_teacher_attendance(
  p_student_id text,
  p_institute_id text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.students s
    where (
      s.user_id = auth.uid()::text
      or s.id = auth.uid()::text
    )
      and public.teacher_attendance_institute_matches(p_institute_id)
      and public.teacher_attendance_institute_matches(s.institute_id)
      and nullif(btrim(coalesce(p_student_id, '')), '') is not null
      and (
        btrim(p_student_id) = btrim(s.id)
        or btrim(p_student_id) = btrim(coalesce(s.sr_no, ''))
        or btrim(p_student_id) = auth.uid()::text
        or btrim(p_student_id) = btrim(coalesce(s.user_id, ''))
      )
  );
$$;

revoke all on function public.student_owns_teacher_attendance(text, text) from public;
grant execute on function public.student_owns_teacher_attendance(text, text) to authenticated;

-- Drop all known teacher_attendance policies (permissive OR stack was inconsistent).
drop policy if exists "authenticated_all_teacher_att" on public.teacher_attendance;
drop policy if exists "teacher_attendance_all" on public.teacher_attendance;
drop policy if exists "teacher_attendance_select" on public.teacher_attendance;
drop policy if exists "teacher_attendance_insert" on public.teacher_attendance;
drop policy if exists "teacher_attendance_update" on public.teacher_attendance;
drop policy if exists "teacher_attendance_delete_coder_only" on public.teacher_attendance;
drop policy if exists "teacher_attendance_super_admin_select" on public.teacher_attendance;

create policy "teacher_attendance_select"
  on public.teacher_attendance for select
  to authenticated
  using (
    public.is_coder()
    or public.is_super_admin()
    or (
      public.is_institute_admin_or_attendance_user()
      and public.teacher_attendance_institute_matches(institute_id)
    )
    or public.student_owns_teacher_attendance(student_id, institute_id)
  );

create policy "teacher_attendance_insert"
  on public.teacher_attendance for insert
  to authenticated
  with check (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and public.teacher_attendance_institute_matches(institute_id)
    )
    or public.student_owns_teacher_attendance(student_id, institute_id)
  );

create policy "teacher_attendance_update"
  on public.teacher_attendance for update
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and public.teacher_attendance_institute_matches(institute_id)
    )
    or public.student_owns_teacher_attendance(student_id, institute_id)
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and public.teacher_attendance_institute_matches(institute_id)
    )
    or public.student_owns_teacher_attendance(student_id, institute_id)
  );

create policy "teacher_attendance_delete_coder_only"
  on public.teacher_attendance for delete
  to authenticated
  using (public.is_coder());

-- attendance_in_out: allow institute_code column to match profile id OR code (marking flow).
drop policy if exists "attendance_in_out_all_institute_admin" on public.attendance_in_out;

create policy "attendance_in_out_all_institute_admin"
  on public.attendance_in_out for all
  to authenticated
  using (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and (
        institute_code = public.current_profile_institute_code()
        or institute_code = public.current_profile_institute_id()
      )
    )
    or exists (
      select 1
      from public.students s
      where s.id = attendance_in_out.student_id
        and (
          s.user_id = auth.uid()::text
          or s.id = auth.uid()::text
        )
        and (
          attendance_in_out.institute_code = public.current_profile_institute_id()
          or attendance_in_out.institute_code = public.current_profile_institute_code()
          or public.teacher_attendance_institute_matches(s.institute_id)
        )
    )
  )
  with check (
    public.is_coder()
    or (
      public.is_institute_admin_or_attendance_user()
      and (
        institute_code = public.current_profile_institute_code()
        or institute_code = public.current_profile_institute_id()
      )
    )
    or exists (
      select 1
      from public.students s
      where s.id = attendance_in_out.student_id
        and (
          s.user_id = auth.uid()::text
          or s.id = auth.uid()::text
        )
        and (
          attendance_in_out.institute_code = public.current_profile_institute_id()
          or attendance_in_out.institute_code = public.current_profile_institute_code()
          or public.teacher_attendance_institute_matches(s.institute_id)
        )
    )
  );
