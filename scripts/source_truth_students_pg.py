#!/usr/bin/env python3
"""Reconcile public.students exactly to a student CSV for institutes present in that CSV."""

from __future__ import annotations

import argparse
import sys
import time
import uuid
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import filter_students_csv_for_import as filt  # noqa: E402
import import_institutes_csv as icu  # noqa: E402
import import_students_csv as stu  # noqa: E402
import fast_load_students_pg_copy as fast  # noqa: E402
from bulk_upsert_students_pg import _row_from_payload_for_copy  # noqa: E402


STAGE_TABLE = "public._student_import_staging"


def main() -> None:
    try:
        import psycopg
    except ImportError:
        print("Install psycopg: pip install -r scripts/requirements-fast-pg-load.txt", file=sys.stderr)
        sys.exit(1)

    ap = argparse.ArgumentParser()
    ap.add_argument("csv_path")
    ap.add_argument("--match", choices=("user_id", "id", "sr_no"), default="sr_no")
    ap.add_argument("--allow-zero-subjects", action="store_true")
    ap.add_argument("--max-subjects", type=int, default=8)
    ap.add_argument("--copy-chunk-rows", type=int, default=250)
    ap.add_argument("--chunk-retries", type=int, default=8)
    ap.add_argument("--env-file", default=None)
    ap.add_argument("--no-dotenv", action="store_true")
    ap.add_argument("--skip-institutes-rest-check", action="store_true")
    ap.add_argument("--ignore-institutes-file", default=None)
    ap.add_argument("--ignore-instid-form-tsv", default=None)
    ap.add_argument("--ignore-zero-subject-rows", action="store_true")
    args = ap.parse_args()

    icu.load_dotenv_merged(args.env_file, skip=args.no_dotenv)
    csv_path = Path(args.csv_path).expanduser()
    if not csv_path.is_file():
        print(f"Not found: {csv_path}", file=sys.stderr)
        sys.exit(1)

    ignore_inst: set[str] = set()
    if args.ignore_institutes_file and Path(args.ignore_institutes_file).is_file():
        ignore_inst = filt.load_inst_ids(Path(args.ignore_institutes_file))
    ignore_pairs: set[tuple[str, str]] = set()
    if args.ignore_instid_form_tsv and Path(args.ignore_instid_form_tsv).is_file():
        ignore_pairs = filt.load_exclude_pairs(Path(args.ignore_instid_form_tsv))

    agg = stu.aggregate_student_rows_from_csv(
        csv_path,
        cli_institute_id=None,
        match=args.match,
        allow_zero_subjects=args.allow_zero_subjects,
        max_subjects=args.max_subjects,
        ignore_institutes=ignore_inst,
        ignore_pairs=ignore_pairs,
        ignore_zero_subject_rows=args.ignore_zero_subject_rows,
        verbose_row_skips=False,
    )
    if not agg.aggregated:
        print("No valid student rows.", file=sys.stderr)
        sys.exit(1)

    institute_ids = sorted(agg.aggregated.keys(), key=lambda x: str(x))
    if not args.skip_institutes_rest_check:
        base_url, key = icu.supabase_rest_credentials()
        found, unsafe = stu.fetch_institute_ids_that_exist(base_url, key, institute_ids)
        if unsafe:
            print(f"Unsafe institute IDs: {unsafe[:20]}", file=sys.stderr)
            sys.exit(3)
        missing = [iid for iid in institute_ids if iid not in found]
        if missing:
            print(f"{len(missing)} institute id(s) missing in public.institutes.", file=sys.stderr)
            sys.exit(3)

    dsn = fast._database_url_from_env()
    dsn, _ = fast._dsn_fix_supabase_session_pooler_user(psycopg, dsn)
    dsn, ipv4_note = fast._dsn_prefer_ipv4(psycopg, dsn)
    if ipv4_note:
        print(ipv4_note, file=sys.stderr)
    dsn = fast._dsn_merge_tcp_keepalives(psycopg, dsn)

    run_id = str(uuid.uuid4())
    cols = ("run_id",) + fast.COPY_COLUMNS
    cols_sql = ",".join(cols)
    copy_stmt = f"COPY {STAGE_TABLE} ({cols_sql}) FROM STDIN"
    payload_rows = [
        payload
        for iid in sorted(agg.aggregated.keys(), key=lambda x: str(x))
        for _mk, payload in agg.aggregated[iid].items()
    ]
    chunks = [payload_rows[i : i + args.copy_chunk_rows] for i in range(0, len(payload_rows), args.copy_chunk_rows)]

    create_stage = f"""
CREATE TABLE IF NOT EXISTS {STAGE_TABLE} (
  run_id text NOT NULL,
  institute_id text NOT NULL,
  name text,
  first_name text,
  middle_name text,
  last_name text,
  user_id text,
  sr_no text,
  year text,
  lecture_timing text,
  subject text,
  subjects text[],
  semester text,
  semester_name text,
  status text,
  role text,
  uid text,
  has_device boolean
);
"""
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute(create_stage)
            cur.execute(f"DELETE FROM {STAGE_TABLE} WHERE run_id = %s", (run_id,))

    print(f"Staging {len(payload_rows)} CSV rows in {len(chunks)} chunk(s); run_id={run_id}", flush=True)
    staged = 0
    for chunk_i, chunk in enumerate(chunks, start=1):
        attempt = 1
        while True:
            try:
                print(f"Stage chunk {chunk_i}/{len(chunks)} ({len(chunk)} rows)...", flush=True)
                with psycopg.connect(dsn) as conn:
                    with conn.cursor() as cur:
                        with cur.copy(copy_stmt) as cp:
                            for payload in chunk:
                                cp.write_row((run_id,) + _row_from_payload_for_copy(payload))
                staged += len(chunk)
                break
            except Exception as e:
                if attempt >= args.chunk_retries:
                    raise
                wait = min(20.0, 0.75 * (2 ** (attempt - 1)))
                print(f"Stage chunk {chunk_i} failed: {e}. Retrying after {wait:.1f}s...", file=sys.stderr)
                time.sleep(wait)
                attempt += 1

    set_sql = ",\n      ".join(f"{col} = s.{col}" for col in fast.COPY_COLUMNS if col != "institute_id")
    select_cols = ", ".join(f"s.{col}" for col in fast.COPY_COLUMNS)
    reconcile_sql = f"""
CREATE INDEX IF NOT EXISTS _student_import_staging_run_inst_sr_idx
  ON {STAGE_TABLE} (run_id, institute_id, sr_no);

DELETE FROM public.students e
WHERE EXISTS (SELECT 1 FROM {STAGE_TABLE} s WHERE s.run_id = %(run_id)s AND s.institute_id = e.institute_id)
AND NOT EXISTS (
  SELECT 1 FROM {STAGE_TABLE} s
  WHERE s.run_id = %(run_id)s
    AND s.institute_id = e.institute_id
    AND s.sr_no IS NOT DISTINCT FROM e.sr_no
);

DELETE FROM public.students e
USING (
  SELECT id,
         row_number() OVER (
           PARTITION BY institute_id, sr_no
           ORDER BY CASE WHEN coalesce(nullif(btrim(name), ''), nullif(btrim(user_id), '')) IS NULL THEN 1 ELSE 0 END, id
         ) AS rn
  FROM public.students
  WHERE EXISTS (
    SELECT 1 FROM {STAGE_TABLE} s
    WHERE s.run_id = %(run_id)s
      AND s.institute_id = students.institute_id
      AND s.sr_no IS NOT DISTINCT FROM students.sr_no
  )
) d
WHERE e.id = d.id AND d.rn > 1;

UPDATE public.students e
SET {set_sql}
FROM {STAGE_TABLE} s
WHERE s.run_id = %(run_id)s
  AND e.institute_id = s.institute_id
  AND e.sr_no IS NOT DISTINCT FROM s.sr_no;

INSERT INTO public.students ({",".join(fast.COPY_COLUMNS)})
SELECT {select_cols}
FROM {STAGE_TABLE} s
WHERE s.run_id = %(run_id)s
AND NOT EXISTS (
  SELECT 1 FROM public.students e
  WHERE e.institute_id = s.institute_id
    AND e.sr_no IS NOT DISTINCT FROM s.sr_no
);

DELETE FROM {STAGE_TABLE} WHERE run_id = %(run_id)s;
"""
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute(reconcile_sql, {"run_id": run_id})
    print(f"Source-of-truth reconciliation complete; staged={staged}.")


if __name__ == "__main__":
    main()
