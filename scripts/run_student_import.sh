#!/usr/bin/env bash
# Load **student** records into Supabase (`public.students`), tied to each institute via CSV `instid`.
# This is NOT the institutes import — institutes import only creates parent rows + invites.
#
# Loads .env from repo root by default (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY).
#
# Prerequisites:
#   1. Each CSV `instid` must exist as institutes.id — one-time institutes sheet if missing:
#      python3 scripts/import_institutes_csv.py scripts/my_institutes.csv --with-admin-invites
#   2. After student import: run scripts/reconcile_institute_student_counts.sql in Supabase SQL Editor.
#
# Faster bulk INSERT (PostgreSQL COPY, not REST): pip install -r scripts/requirements-fast-pg-load.txt
# On Mac/local IPv4, set DATABASE_SESSION_POOL_URL (Dashboard → Connect → Session pooler) or DATABASE_URL,
# then scripts/fast_load_students_pg_copy.py with the same
# CSV flags — inserts new rows only; does not PATCH updates like import_students_csv.py.
#
# Imports from the full STUDENTS.csv. Silent `--ignore-zero-subject-rows` skips students who declare SUBJECT_*
# columns but have none enrolled (master CSV unchanged). Optional: `--ignore-institutes-file` / `--ignore-instid-form-tsv`
# if you pass them manually to import_students_csv.py.
#
# Usage:
#   cd repo && ./scripts/run_student_import.sh              # LIVE import (writes DB)
#   cd repo && ./scripts/run_student_import.sh --dry-run    # Plan only
#   cd repo && ./scripts/run_student_import.sh --csv scripts/STUDENTS_import_bulk.csv   # alternate CSV
#
# Single-institute file (no instid column) — pass institute id explicitly, e.g.:
#   python3 scripts/import_students_csv.py path/to/one_center.csv \\
#     --institute-id 11061 --match sr_no --max-subjects 5
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CSV="${ROOT}/scripts/STUDENTS.csv"
DRY=""
INST_ID=""
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    --dry-run) DRY="--dry-run"; shift ;;
    --institute-id=*)
      INST_ID="${1#*=}"
      shift ;;
    --institute-id)
      INST_ID="$2"
      shift 2 ;;
    --csv=*)
      CSV="${1#*=}"
      shift ;;
    --csv)
      CSV="$2"
      shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

ENVF="${ROOT}/.env"
if [[ ! -f "$CSV" ]]; then
  echo "CSV not found: $CSV" >&2
  exit 1
fi
if [[ ! -f "$ENVF" ]]; then
  echo "Missing .env at $ENVF" >&2
  exit 1
fi

LOG="${ROOT}/scripts/student_import_$(date +%Y%m%d_%H%M%S).log"

export PYTHONUNBUFFERED=1
echo "Log: $LOG" | tee "$LOG"
echo "CSV: $CSV" | tee -a "$LOG"
echo "Dry-run: ${DRY:-no}" | tee -a "$LOG"
if [[ -n "$INST_ID" ]]; then
  echo "Institute (--institute-id): $INST_ID" | tee -a "$LOG"
fi

IID_ARGS=( )
[[ -n "$INST_ID" ]] && IID_ARGS+=( "--institute-id" "$INST_ID" )

python3 "$ROOT/scripts/import_students_csv.py" "$CSV" \
  "${IID_ARGS[@]}" \
  --match sr_no \
  --max-subjects 5 \
  --ignore-zero-subject-rows \
  --env-file "$ENVF" \
  ${DRY:+"--dry-run"} \
  2>&1 | tee -a "$LOG"

echo "--- finished ---"
echo "Optional: refresh institute student_count → run scripts/reconcile_institute_student_counts.sql in Supabase." | tee -a "$LOG"
