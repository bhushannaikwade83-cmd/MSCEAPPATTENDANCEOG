-- Portal super_admin / coder: update students (name, subjects, year) from MSCE admin website.

drop policy if exists "students_super_admin_all" on public.students;

create policy "students_super_admin_all"
  on public.students for all
  to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());
