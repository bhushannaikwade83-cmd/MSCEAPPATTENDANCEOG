Supabase migration (Firebase → Postgres + Supabase Auth)
=========================================================

1) Create a project at https://supabase.com

2) If Table Editor shows "Failed to load tables" or connection errors: restore/resume
   the project (free tier pauses), wait until healthy, try another browser/network.

3) In Supabase Dashboard → SQL Editor, run IN ORDER:
   a) migrations/000_smoke_test.sql  → you should see table "smoke_test" in Table Editor
   b) migrations/001_initial_schema.sql → full app tables
   c) migrations/003_students_extras.sql, 004_batches_institute_timing.sql (if present).
      On existing databases, also run migrations/037_remove_batches_and_rename_lecture_columns.sql
      to drop `batches`, remove student batch columns, and rename institute timing fields to lecture_* .
   d) migrations/005_aux_firestore_parity.sql → GPS, teacher_attendance, coders, etc.
   e) migrations/006_rls_production.sql → production Row Level Security (replaces permissive policies)
   f) migrations/007_super_admin_access.sql → adds super_admin cross-institute access overlay
   g) migrations/008–010 as needed (email queue, institute_code, RLS tweaks)
   h) migrations/011_institutes_pincode.sql → adds institutes.pincode (required for admin portal pincode field/list)
   i) migrations/012_institute_admin_signup_trigger.sql → DB trigger for in-app institute admin signup (fixes RLS when email confirm is on)
   j) migrations/013_institute_admin_approve_increment.sql → when web portal approves a pending admin, increment institute user_count

   If (a) works but (b) fails, read the RED error message — fix that line, then re-run (b).
   Re-running 001 after 006 is not recommended without dropping 006 policies first.

4) In Project Settings → API, copy:
   - Project URL  → add to your app .env as SUPABASE_URL=
   - anon public key → SUPABASE_ANON_KEY=

5) Flutter: keys are loaded from .env (also used for B2). Example lines:
   SUPABASE_URL=https://xxxx.supabase.co
   SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

6) The app requires Supabase (main.dart calls SupabaseEnv.initializeRequired()).

7) Production RLS (006):
   - Institute-scoped data for admins (profiles.institute_id + role admin + status approved/active).
   - Coders: extra access via public.coders; first coder row must be inserted with SQL
     or service role (RLS has no client INSERT on coders).
   - Anon: SELECT active institutes only; optional limited INSERT on error_logs for pre-login errors.
   - Helper functions: current_profile_institute_id(), current_profile_institute_code(),
     is_institute_admin(), is_coder(), profile_has_no_institute() (SECURITY DEFINER).

8) Super admin access (007):
   - Add this if you use super admin screens to create/manage institutes across tenants.
   - User must have `profiles.role = 'super_admin'` and status `approved`/`active`.

9) One-time data migration from Firestore: export to CSV/JSON and import into Postgres (ETL).

10) Auth — email confirmation (recommended OFF for this app):
   Registration is already verified on your website / in-app (e.g. OTP). You do not need a second
   confirmation in Supabase.
   In Supabase Dashboard → Authentication → Providers → Email:
   - Turn OFF “Confirm email” (so signUp returns a session and users can log in immediately).
   This matches direct institute admin signup and avoids duplicate “confirm” steps.
