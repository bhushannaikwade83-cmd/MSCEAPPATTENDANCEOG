-- Persist B2 object path for registration photos (signed URLs in photo_url expire).
alter table public.students add column if not exists registration_photo_path text;

-- 007 only granted super_admin SELECT on attendance_in_out; allow full access for support / cross-institute flows.
drop policy if exists "attendance_in_out_super_admin_all" on public.attendance_in_out;
create policy "attendance_in_out_super_admin_all"
  on public.attendance_in_out for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());
