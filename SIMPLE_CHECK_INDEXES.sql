-- ================================================================
-- SIMPLE: Just show what columns exist
-- ================================================================

-- Show the structure of pg_stat_user_indexes
SELECT * FROM pg_stat_user_indexes LIMIT 1;

-- OR simpler - just list all indexes on students table
SELECT * FROM pg_indexes WHERE tablename = 'students';

-- OR even simpler - check if our indexes exist
SELECT indexname FROM pg_indexes
WHERE indexname LIKE 'idx_students%' OR indexname LIKE 'idx_attendance%';
