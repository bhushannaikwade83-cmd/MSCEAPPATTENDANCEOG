-- Force existing admins to stop using old PIN-based login secrets
-- without deleting institute, student, or attendance data.
--
-- What this does:
-- 1. Clears old PIN login fields from public.profiles for admin accounts
-- 2. Revokes current auth sessions for those admins
--
-- After running:
-- - Existing institutes remain intact
-- - Existing data remains intact
-- - Admins must sign in once with password
-- - App will show "Set PIN" again after password login

begin;

-- Phase 1: clear old PIN login state for all approved/active admins.
update public.profiles
set pin_hash = null,
    encrypted_password = null,
    has_pin = false,
    pin_set_at = null
where role = 'admin'
  and coalesce(lower(status), '') in ('', 'approved', 'active');

-- Phase 2: revoke current sessions so already-logged-in admins must re-authenticate.
do $$
begin
  if to_regclass('auth.sessions') is not null then
    delete from auth.sessions s
    using public.profiles p
    where p.id = s.user_id
      and p.role = 'admin'
      and coalesce(lower(p.status), '') in ('', 'approved', 'active');
  end if;
end $$;

commit;
