-- DANGER: FULL DATA RESET
-- This wipes Supabase app data for fresh testing.
-- It keeps schema, functions, policies, and migrations, but deletes data.
--
-- What it clears:
-- - all rows in public tables
-- - auth users, identities, sessions, refresh tokens, MFA records
-- - storage object metadata is NOT deleted here because Supabase blocks direct SQL deletes
--
-- Run only if you want the project to behave like first-time testing.

begin;

-- Remove auth/session-related data first.
do $$
begin
  if to_regclass('auth.mfa_amr_claims') is not null then
    execute 'delete from auth.mfa_amr_claims';
  end if;
  if to_regclass('auth.mfa_challenges') is not null then
    execute 'delete from auth.mfa_challenges';
  end if;
  if to_regclass('auth.mfa_factors') is not null then
    execute 'delete from auth.mfa_factors';
  end if;
  if to_regclass('auth.one_time_tokens') is not null then
    execute 'delete from auth.one_time_tokens';
  end if;
  if to_regclass('auth.sessions') is not null then
    execute 'delete from auth.sessions';
  end if;
  if to_regclass('auth.refresh_tokens') is not null then
    execute 'delete from auth.refresh_tokens';
  end if;
  if to_regclass('auth.flow_state') is not null then
    execute 'delete from auth.flow_state';
  end if;
  if to_regclass('auth.identities') is not null then
    execute 'delete from auth.identities';
  end if;
  if to_regclass('auth.audit_log_entries') is not null then
    execute 'delete from auth.audit_log_entries';
  end if;
  if to_regclass('auth.users') is not null then
    execute 'delete from auth.users';
  end if;
end;
$$;

-- Storage files must be cleared separately using the Supabase Storage API or dashboard.

-- Truncate every public table except PostGIS/system leftovers if present.
do $$
declare
  stmt text;
begin
  select string_agg(
           format('truncate table %I.%I restart identity cascade', schemaname, tablename),
           '; '
         )
    into stmt
  from pg_tables
  where schemaname = 'public'
    and tablename not in (
      'spatial_ref_sys',
      'geography_columns',
      'geometry_columns',
      'raster_columns',
      'raster_overviews'
    );

  if stmt is not null and stmt <> '' then
    execute stmt;
  end if;
end;
$$;

commit;
