-- ⚡ PERFORMANCE OPTIMIZATION: Indexes for 300K students + 3K institutes
-- Run this migration on Supabase to enable fast querying

-- 1. CRITICAL: Index for attendance marking (most frequent query)
CREATE INDEX IF NOT EXISTS idx_students_institute_registered
ON students(institute_id, face_registration_status)
WHERE face_registration_status = 'registered';

-- 2. Index for student lookup by roll number
CREATE INDEX IF NOT EXISTS idx_students_sr_no
ON students(sr_no);

-- 3. Index for attendance entry/exit detection
CREATE INDEX IF NOT EXISTS idx_attendance_sr_no_date
ON attendance(sr_no, attendance_date);

-- 3b. CRITICAL: Covers the exact entry-check query (sr_no + date + record_type)
-- Without this, step 7 (entry/exit check) falls back to a slower index scan + filter
CREATE INDEX IF NOT EXISTS idx_attendance_sr_no_date_type
ON attendance(sr_no, attendance_date, record_type);

-- 4. Index for daily attendance reports
CREATE INDEX IF NOT EXISTS idx_attendance_institute_date
ON attendance(institute_id, attendance_date);

-- 5. Index for student name search
CREATE INDEX IF NOT EXISTS idx_students_name
ON students(fname, lname);

-- 6. Composite index for registration status check (FAST!)
CREATE INDEX IF NOT EXISTS idx_students_id_status
ON students(id, face_registration_status);

-- Optional: Partial index for face-registered students (very selective)
CREATE INDEX IF NOT EXISTS idx_students_registered
ON students(institute_id)
WHERE face_registration_status = 'registered';

-- Check index creation status
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE tablename IN ('students', 'attendance')
ORDER BY idx_scan DESC;
