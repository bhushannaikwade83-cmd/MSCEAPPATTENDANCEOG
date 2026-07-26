#!/bin/bash
# 🚀 FAST IMPORT 103K STUDENTS (macOS Compatible)

set -e

cd "$(dirname "$0")"

echo "📁 Setting up Python virtual environment..."

# Create venv if it doesn't exist
if [ ! -d "venv_import" ]; then
    python3 -m venv venv_import
    echo "✅ Created virtual environment"
fi

# Activate venv
source venv_import/bin/activate
echo "✅ Virtual environment activated"

echo ""
echo "📦 Installing dependencies..."
pip install -q psycopg[binary] pandas python-dotenv
echo "✅ Dependencies installed"

echo ""
echo "🔌 Testing database connection..."

# Load .env manually
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

DB_URL="${DATABASE_SESSION_POOL_URL:-$DATABASE_URL}"

if [ -z "$DB_URL" ]; then
    echo "❌ DATABASE_SESSION_POOL_URL or DATABASE_URL not set in .env"
    exit 1
fi

python3 << 'PYTHON_CHECK'
import os
import psycopg

db_url = os.getenv('DATABASE_SESSION_POOL_URL') or os.getenv('DATABASE_URL')

if not db_url:
    print("❌ DATABASE_SESSION_POOL_URL or DATABASE_URL not set in .env")
    exit(1)

try:
    import psycopg
    with psycopg.connect(db_url) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT version();")
            print("✅ Database connected!")
except Exception as e:
    print(f"❌ Connection failed: {e}")
    exit(1)
PYTHON_CHECK

echo ""
echo "📊 CSV File Info:"
python3 << 'PYTHON_CSV'
import csv
with open('scripts/STUDENTS.csv') as f:
    rows = list(csv.reader(f))
    print(f"   Columns: {', '.join(rows[0][:6])}...")
    print(f"   Total rows: {len(rows) - 1:,}")
    print(f"   Sample: {rows[1][:6]}")
PYTHON_CSV

echo ""
read -p "✅ Ready to import 103,393 students? Type 'yes': " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Cancelled"
    exit 1
fi

echo ""
echo "🚀 IMPORTING 103K STUDENTS..."
echo "⏱️  Estimated time: 4-6 minutes"
echo ""

time python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \
    --match sr_no \
    --max-subjects 6 \
    --ignore-zero-subject-rows \
    --allow-zero-subjects

echo ""
echo "✅ IMPORT COMPLETE!"
echo ""
echo "📊 Verification:"
python3 << 'PYTHON_VERIFY'
import os
import psycopg

db_url = os.getenv('DATABASE_SESSION_POOL_URL') or os.getenv('DATABASE_URL')

with psycopg.connect(db_url) as conn:
    with conn.cursor() as cur:
        # Total count
        cur.execute("SELECT COUNT(*) FROM students;")
        total = cur.fetchone()[0]
        print(f"   Total students: {total:,}")

        # Per institute
        cur.execute("""
            SELECT COUNT(DISTINCT institute_id)
            FROM students;
        """)
        institutes = cur.fetchone()[0]
        print(f"   Institutes: {institutes}")

        # Sample institutes
        cur.execute("""
            SELECT institute_id, COUNT(*) as cnt
            FROM students
            GROUP BY institute_id
            ORDER BY cnt DESC
            LIMIT 5;
        """)
        print("\n   Top 5 institutes:")
        for inst_id, cnt in cur.fetchall():
            print(f"      Institute {inst_id}: {cnt:,} students")
PYTHON_VERIFY

echo ""
echo "✨ Success! Your students are imported and ready to use."
echo ""
echo "💡 Next time, just run: ./import_students_fast.sh"
