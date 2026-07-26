-- 🟢 RESET DATA: Institute 11039 - KEEP INSTITUTE, DELETE ALL DATA INSIDE
-- This will delete ALL data FOR institute 11039 but KEEP the institute itself
-- Next time you log in, it will be like FIRST LOGIN - fresh registration

-- ⚠️ WARNING: THIS IS PERMANENT - YOU CANNOT UNDO THIS!
-- Make sure 11039 is the right institute before running!

-- STEP 1: Delete all attendance records for this institute
DELETE FROM public.attendance_in_out
WHERE institute_code = '11039';

-- STEP 2: Delete all face embeddings/photos for students
DELETE FROM public.face_embeddings
WHERE student_id IN (
  SELECT id FROM public.students WHERE institute_id = '11039'
);

-- STEP 3: Delete all student data
DELETE FROM public.students
WHERE institute_id = '11039';

-- STEP 4: Delete all batches
DELETE FROM public.batches
WHERE institute_id = '11039';

-- STEP 5: KEEP admin/staff profiles - Don't delete!
-- Admins stay in the system for next login

-- STEP 6: Delete GPS settings
DELETE FROM public.gps_settings
WHERE institute_id = '11039';

-- STEP 7: Delete geofence data
DELETE FROM public.institute_geofence
WHERE institute_id = '11039';

-- STEP 8: KEEP admin invites - Don't delete!
-- Admin details stay for next login

-- STEP 9: KEEP THE INSTITUTE - Don't delete it!
-- The institute 11039 still exists, but all data inside is cleared

-- VERIFICATION: Confirm student data is deleted, but admins & institute kept
SELECT 'Attendance records' as table_name, COUNT(*) as remaining
FROM public.attendance_in_out
WHERE institute_code = '11039'
UNION ALL
SELECT 'Students', COUNT(*)
FROM public.students
WHERE institute_id = '11039'
UNION ALL
SELECT 'GPS Settings', COUNT(*)
FROM public.gps_settings
WHERE institute_id = '11039'
UNION ALL
SELECT 'Geofence', COUNT(*)
FROM public.institute_geofence
WHERE institute_id = '11039'
UNION ALL
SELECT 'Profiles (Admins - KEPT)', COUNT(*)
FROM public.profiles
WHERE institute_id = '11039'
UNION ALL
SELECT 'Institute (KEPT)', COUNT(*)
FROM public.institutes
WHERE id = '11039';

-- Expected result:
-- Attendance records: 0 ✅ (deleted)
-- Students: 0 ✅ (deleted)
-- GPS Settings: 0 ✅ (deleted)
-- Geofence: 0 ✅ (deleted)
-- Profiles (Admins): > 0 ✅ (KEPT!)
-- Institute: 1 ✅ (KEPT!)

-- Next login: Admins can log back in, fresh student list!

