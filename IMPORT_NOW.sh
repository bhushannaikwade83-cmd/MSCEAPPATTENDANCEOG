#!/bin/bash
# 🚀 IMPORT 103K STUDENTS NOW

set -e

cd "$(dirname "$0")"

echo "🔧 Installing dependencies..."
python3 -m pip install -q psycopg[binary] pandas python-dotenv 2>/dev/null || python3 -m pip install psycopg[binary] pandas python-dotenv

echo "📖 Testing database connection..."
python3 << 'PYTHON_CHECK'
import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()
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
    print(f"   Columns: {', '.join(rows[0])}")
    print(f"   Total rows: {len(rows) - 1:,}")
    print(f"   Sample row: {rows[1][:6]}")
PYTHON_CSV

echo ""
echo "🧪 DRY RUN (preview only - no changes):"
python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \
    --match sr_no \
    --max-subjects 6 \
    --ignore-zero-subject-rows \
    --dry-run

echo ""
read -p "✅ Ready to import? Type 'yes' to confirm: " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Import cancelled"
    exit 1
fi

echo ""
echo "🚀 STARTING IMPORT OF 103K STUDENTS..."
echo "⏱️  Estimated time: 4-6 minutes"
echo ""

time python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \
    --match sr_no \
    --max-subjects 6 \
    --ignore-zero-subject-rows \
    --copy-chunk-rows 10000 \
    --prefer-ipv4

echo ""
echo "✅ IMPORT COMPLETE!"
echo ""
echo "📊 Verification:"
python3 << 'PYTHON_VERIFY'
import os
from dotenv import load_dotenv
import psycopg

load_dotenv()
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
echo "✨ All done! Your students are ready to use."
