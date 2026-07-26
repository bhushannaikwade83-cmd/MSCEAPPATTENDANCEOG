-- ============================================
-- Auto Schema Initialization Functions
-- ============================================

-- Function to get all column names from a table
CREATE OR REPLACE FUNCTION get_table_columns(p_table_name TEXT)
RETURNS TABLE(column_name TEXT) AS $$
BEGIN
  RETURN QUERY
  SELECT information_schema.columns.column_name::TEXT
  FROM information_schema.columns
  WHERE table_name = p_table_name
    AND table_schema = 'public';
END;
$$ LANGUAGE plpgsql;

-- Function to execute arbitrary SQL (for schema updates)
-- ⚠️ CAUTION: Only use in development/testing
-- In production, use proper migrations instead
CREATE OR REPLACE FUNCTION execute_sql(p_sql TEXT)
RETURNS TABLE(success BOOLEAN, message TEXT) AS $$
DECLARE
  v_error_msg TEXT;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RETURN QUERY SELECT true, 'SQL executed successfully'::TEXT;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error_msg = MESSAGE_TEXT;
    RETURN QUERY SELECT false, v_error_msg;
  END;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions to authenticated users
GRANT EXECUTE ON FUNCTION get_table_columns(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION execute_sql(TEXT) TO authenticated;
