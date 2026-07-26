-- Fix all foreign key constraints referencing institutes table
-- Ensure all have ON DELETE CASCADE to allow deletion of institutes

-- 1. Fix batches table
alter table if exists public.batches
drop constraint if exists batches_institute_id_fkey;

alter table if exists public.batches
add constraint batches_institute_id_fkey
  foreign key (institute_id)
  references public.institutes (id)
  on delete cascade;

-- 2. Fix institute_subjects table
alter table if exists public.institute_subjects
drop constraint if exists institute_subjects_institute_id_fkey;

alter table if exists public.institute_subjects
add constraint institute_subjects_institute_id_fkey
  foreign key (institute_id)
  references public.institutes (id)
  on delete cascade;

-- 3. Fix user_credentials table
alter table if exists public.user_credentials
drop constraint if exists user_credentials_institute_id_fkey;

alter table if exists public.user_credentials
add constraint user_credentials_institute_id_fkey
  foreign key (institute_id)
  references public.institutes (id)
  on delete cascade;

-- 4. Fix admin_invites table
alter table if exists public.admin_invites
drop constraint if exists admin_invites_institute_id_fkey;

alter table if exists public.admin_invites
add constraint admin_invites_institute_id_fkey
  foreign key (institute_id)
  references public.institutes (id)
  on delete cascade;

-- 5. Fix institute_attendance_staff table (if exists)
alter table if exists public.institute_attendance_staff
drop constraint if exists institute_attendance_staff_institute_id_fkey;

alter table if exists public.institute_attendance_staff
add constraint institute_attendance_staff_institute_id_fkey
  foreign key (institute_id)
  references public.institutes (id)
  on delete cascade;

-- Summary: All tables that reference institutes now have ON DELETE CASCADE
-- This allows safe deletion of institute records without foreign key errors
