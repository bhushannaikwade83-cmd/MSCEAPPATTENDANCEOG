#!/bin/bash

# Load environment
export $(cat .env | grep -v '^#' | xargs)

# Run migration
python3 << 'PYTHON_EOF'
import urllib.request
import json
import sys
import os

db_url = os.getenv('DATABASE_SESSION_POOL_URL')
if not db_url:
    print("❌ DATABASE_SESSION_POOL_URL not found in .env")
    sys.exit(1)

# Read SQL
with open('ADD_FACE_EMBEDDING_TO_STUDENTS.sql', 'r') as f:
    sql = f.read()

# Execute via curl (no Python psycopg2 needed)
import subprocess
result = subprocess.run([
    'curl', '-X', 'POST',
    f'{os.getenv("SUPABASE_URL")}/rest/v1/rpc/exec_sql',
    '-H', f'apikey: {os.getenv("SUPABASE_SERVICE_ROLE_KEY")}',
    '-H', 'Content-Type: application/json',
    '-d', json.dumps({'sql': sql})
], capture_output=True, text=True)

if result.returncode == 0:
    print("✅ Migration applied successfully")
    print(result.stdout)
else:
    print("❌ Migration failed")
    print(result.stderr)
    sys.exit(1)

PYTHON_EOF
