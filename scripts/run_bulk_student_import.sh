#!/bin/bash
#
# 🚀 QUICK BULK IMPORT SCRIPT FOR 1 LAKH+ STUDENTS
#
# Usage:
#   ./scripts/run_bulk_student_import.sh STUDENTS.csv [institute_id]
#
# Examples:
#   # Import all institutes from CSV
#   ./scripts/run_bulk_student_import.sh STUDENTS.csv
#
#   # Import specific institute only
#   ./scripts/run_bulk_student_import.sh STUDENTS.csv 11061
#
# Requirements:
#   - DATABASE_SESSION_POOL_URL or DATABASE_URL in .env
#   - STUDENTS.csv with columns: instid, formserialno, fname, mname, lname, SUBJECT_1-5

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# Parse arguments
CSV_FILE="${1:?❌ Usage: $0 STUDENTS.csv [institute_id]}"
INSTITUTE_ID="${2:-}"

# Validate CSV exists
if [ ! -f "$CSV_FILE" ]; then
    log_error "CSV file not found: $CSV_FILE"
fi

CSV_ROWS=$(wc -l < "$CSV_FILE")
log_info "Found CSV file: $CSV_FILE ($CSV_ROWS rows)"

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
    log_success "Loaded .env configuration"
else
    log_warning "No .env file found, using environment variables"
fi

# Check database connection
if [ -z "$DATABASE_SESSION_POOL_URL" ] && [ -z "$DATABASE_URL" ]; then
    log_error "DATABASE_SESSION_POOL_URL or DATABASE_URL not set. Set in .env or environment."
fi

DB_URL="${DATABASE_SESSION_POOL_URL:-$DATABASE_URL}"
log_success "Database URL configured"

# Install dependencies
log_info "Installing Python dependencies..."
cd "$PROJECT_DIR"
pip install -q -r scripts/requirements-fast-pg-load.txt 2>/dev/null || {
    log_warning "Could not auto-install requirements. Running pip install..."
    pip install psycopg[binary] pandas python-dotenv
}
log_success "Dependencies ready"

# Test database connection
log_info "Testing database connection..."
python3 << EOF
import psycopg
try:
    with psycopg.connect("$DB_URL") as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT version();")
            version = cur.fetchone()[0]
            print(f"✅ Connected! PostgreSQL version: {version[:50]}...")
except Exception as e:
    print(f"❌ Connection failed: {e}")
    exit(1)
EOF
[ $? -ne 0 ] && log_error "Database connection test failed"

log_success "Database connection verified"

# Run dry-run
log_info ""
log_info "========================================="
log_info "STEP 1: DRY RUN (No changes to database)"
log_info "========================================="
log_info ""

python3 scripts/fast_load_students_pg_copy.py "$CSV_FILE" \
    --match sr_no \
    --max-subjects 5 \
    --ignore-zero-subject-rows \
    --dry-run

read -p "$(echo -e "${YELLOW}Continue with REAL import? (yes/no): ${NC}")" -n 3 response
echo ""
if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
    log_error "Import cancelled by user"
fi

# Run actual import
log_info ""
log_info "========================================="
log_info "STEP 2: STARTING REAL IMPORT"
log_info "========================================="
log_info ""
log_warning "This will INSERT/UPDATE students in the database"
log_warning "Estimated time: ~30 seconds per 10,000 students"
log_info ""

START_TIME=$(date +%s)

python3 scripts/fast_load_students_pg_copy.py "$CSV_FILE" \
    --match sr_no \
    --max-subjects 5 \
    --ignore-zero-subject-rows \
    --copy-chunk-rows 10000 \
    --prefer-ipv4

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_success "Import completed in ${DURATION}s"

# Verify import
log_info ""
log_info "========================================="
log_info "STEP 3: VERIFICATION"
log_info "========================================="
log_info ""

python3 << EOF
import psycopg
from psycopg.rows import tuple_row

try:
    with psycopg.connect("$DB_URL") as conn:
        with conn.cursor(row_factory=tuple_row) as cur:
            # Total count
            cur.execute("SELECT COUNT(*) FROM students;")
            total = cur.fetchone()[0]
            print(f"✅ Total students: {total:,}")

            # Per institute
            cur.execute("""
                SELECT institute_id, COUNT(*) as cnt
                FROM students
                GROUP BY institute_id
                ORDER BY cnt DESC
                LIMIT 10;
            """)
            print("\nTop 10 institutes by student count:")
            for inst_id, cnt in cur.fetchall():
                print(f"   Institute {inst_id}: {cnt:,} students")

            # Check for missing data
            cur.execute("""
                SELECT
                    COUNT(CASE WHEN name IS NULL OR name = '' THEN 1 END) as missing_names,
                    COUNT(CASE WHEN subject IS NULL OR subject = '' THEN 1 END) as missing_subjects
                FROM students;
            """)
            missing_names, missing_subjects = cur.fetchone()
            if missing_names > 0:
                print(f"\n⚠️  Missing names: {missing_names:,}")
            if missing_subjects > 0:
                print(f"⚠️  Missing subjects: {missing_subjects:,}")
            if missing_names == 0 and missing_subjects == 0:
                print("\n✅ No missing critical data")

except Exception as e:
    print(f"❌ Verification failed: {e}")
    exit(1)
EOF

log_success ""
log_success "========================================="
log_success "✨ IMPORT SUCCESSFUL! ✨"
log_success "========================================="
log_info ""
log_info "📊 Import Summary:"
log_info "   Total rows imported: ~$(($CSV_ROWS - 1))"
log_info "   Time taken: ${DURATION}s"
log_info "   Speed: ~$(( (($CSV_ROWS - 1) * 60) / $DURATION ))/min"
log_info ""
log_info "Next steps:"
log_info "   1. Verify data in Supabase Dashboard"
log_info "   2. Run: scripts/reconcile_institute_student_counts.sql"
log_info "   3. Test app with new student data"
log_info ""
