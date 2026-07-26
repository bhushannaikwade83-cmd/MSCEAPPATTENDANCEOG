-- Recover admin setup helper rows after a first-login reset.
--
-- This cannot restore deleted password hashes, PIN hashes, GPS coordinates,
-- or old auth sessions. Those must be set again by admins.
--
-- It does rebuild setup helper rows from surviving admin profiles:
--   - public.admin_invites
--   - public.user_credentials
--
-- Important: the app's anon RPC `institute_admin_setup_public_status` sets
-- invite_claimed = true if ANY admin_invites row exists with claimed = true.
-- Leaving old claimed rows breaks the fallback UI (no OTP). So for institutes
-- we rebuild from profiles (admin + email), we delete ALL admin_invites rows
-- for that institute_id first, then insert one fresh claimed = false row.
--
-- It does NOT delete institutes, profiles, auth users, students, or attendance.

begin;

do $$
begin
  if to_regclass('public.admin_invites') is not null
     and to_regclass('public.profiles') is not null then
    delete from public.admin_invites ai
    where ai.institute_id in (
      select distinct p.institute_id
      from public.profiles p
      where lower(coalesce(p.role, '')) = 'admin'
        and nullif(btrim(coalesce(p.institute_id, '')), '') is not null
        and nullif(btrim(coalesce(p.email, '')), '') is not null
    );

    insert into public.admin_invites (
      institute_id,
      full_name,
      phone,
      email,
      claimed,
      claimed_at,
      updated_at
    )
    select distinct on (p.institute_id)
      p.institute_id,
      coalesce(nullif(btrim(p.name), ''), nullif(btrim(p.email), ''), 'Admin') as full_name,
      coalesce(nullif(btrim(p.phone_number), ''), '') as phone,
      lower(nullif(btrim(p.email), '')) as email,
      false as claimed,
      null as claimed_at,
      now() as updated_at
    from public.profiles p
    where lower(coalesce(p.role, '')) = 'admin'
      and nullif(btrim(coalesce(p.institute_id, '')), '') is not null
      and nullif(btrim(coalesce(p.email, '')), '') is not null
    order by p.institute_id, p.created_at nulls last
    on conflict (institute_id) where claimed = false
    do update set
      full_name = excluded.full_name,
      phone = excluded.phone,
      email = excluded.email,
      claimed = false,
      claimed_at = null,
      updated_at = now();
  end if;

  if to_regclass('public.user_credentials') is not null
     and to_regclass('public.profiles') is not null then
    insert into public.user_credentials (
      institute_id,
      profile_id,
      email,
      email_sent,
      email_sent_at
    )
    select
      p.institute_id,
      p.id,
      lower(nullif(btrim(p.email), '')) as email,
      false as email_sent,
      null as email_sent_at
    from public.profiles p
    where lower(coalesce(p.role, '')) = 'admin'
      and nullif(btrim(coalesce(p.institute_id, '')), '') is not null
      and nullif(btrim(coalesce(p.email, '')), '') is not null
      and not exists (
        select 1
        from public.user_credentials uc
        where uc.profile_id = p.id
      );
  end if;

  if to_regclass('public.profiles') is not null then
    update public.profiles
       set status = 'pending',
           pin_hash = null,
           encrypted_password = null,
           has_pin = false,
           pin_set_at = null,
           last_login = null,
           last_login_ip = null
     where lower(coalesce(role, '')) = 'admin';
  end if;
end $$;

commit;

-- Check what still exists. Optional tables are handled safely.
create temp table recover_admin_setup_report (
  institute_id text,
  institute_name text,
  profile_id text,
  admin_name text,
  admin_email text,
  admin_phone text,
  status text,
  has_pin boolean,
  has_admin_password boolean default false,
  has_pending_admin_invite boolean default false,
  has_user_credentials_row boolean default false
);

insert into recover_admin_setup_report (
  institute_id,
  institute_name,
  profile_id,
  admin_name,
  admin_email,
  admin_phone,
  status,
  has_pin
)
select
  p.institute_id,
  i.name as institute_name,
  p.id::text as profile_id,
  p.name as admin_name,
  p.email as admin_email,
  p.phone_number as admin_phone,
  p.status,
  p.has_pin
from public.profiles p
left join public.institutes i on i.id = p.institute_id
where lower(coalesce(p.role, '')) = 'admin';

do $$
begin
  if to_regclass('public.admin_passwords') is not null then
    update recover_admin_setup_report r
       set has_admin_password = true
       where exists (
       select 1
       from public.admin_passwords ap
       where ap.profile_id::text = r.profile_id
     );
  end if;

  if to_regclass('public.admin_invites') is not null then
    update recover_admin_setup_report r
       set has_pending_admin_invite = true
     where exists (
       select 1
       from public.admin_invites ai
       where ai.institute_id = r.institute_id
         and ai.claimed = false
     );
  end if;

  if to_regclass('public.user_credentials') is not null then
    update recover_admin_setup_report r
       set has_user_credentials_row = true
       where exists (
       select 1
       from public.user_credentials uc
       where uc.profile_id::text = r.profile_id
     );
  end if;
end $$;

select *
from recover_admin_setup_report
order by institute_id, admin_email;

-- Quick sanity check for the mobile “pending website registration” flow:
-- anon RLS only returns rows where claimed = false.
-- select institute_id, claimed, email, full_name from public.admin_invites order by institute_id;
