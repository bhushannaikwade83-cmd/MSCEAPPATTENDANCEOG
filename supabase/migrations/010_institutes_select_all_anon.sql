-- Institute directory: show all rows (including is_active = false) for anon + institute admins.
-- Before this, anon could not see inactive institutes, so the web portal looked empty when
-- every institute was still "pending". Super-admin policies from 007 stay as-is.

drop policy if exists "institutes_select_anon_active" on public.institutes;
drop policy if exists "institutes_select_anon_all" on public.institutes;

create policy "institutes_select_anon_all"
  on public.institutes for select
  to anon
  using (true);

drop policy if exists "institutes_select_authenticated" on public.institutes;

create policy "institutes_select_authenticated"
  on public.institutes for select
  to authenticated
  using (
    public.is_super_admin()
    or public.is_institute_admin()
    or coalesce(is_active, true)
  );
