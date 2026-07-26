-- List all tables that might contain attendance data
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name LIKE '%attendance%'
   OR table_name LIKE '%photo%'
   OR table_name LIKE '%entry%'
   OR table_name LIKE '%exit%'
ORDER BY table_name;
