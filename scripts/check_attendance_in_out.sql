-- Check columns in attendance_in_out table
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'attendance_in_out'
ORDER BY ordinal_position;
