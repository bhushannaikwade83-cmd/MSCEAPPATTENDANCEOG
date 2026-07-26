-- Fix foreign key constraint on profiles.institute_id
-- Add ON DELETE CASCADE so profiles are automatically deleted when institute is deleted

-- Step 1: Drop the old foreign key constraint
alter table public.profiles
drop constraint if exists profiles_institute_id_fkey;

-- Step 2: Add the new foreign key with ON DELETE CASCADE
alter table public.profiles
add constraint profiles_institute_id_fkey
  foreign key (institute_id)
  references public.institutes (id)
  on delete cascade;

-- Verify the constraint is in place
-- Run in Supabase: SELECT constraint_name, table_name FROM information_schema.table_constraints
--                  WHERE table_name = 'profiles' AND constraint_type = 'FOREIGN KEY';
