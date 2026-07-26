#!/usr/bin/env python3
"""
Fast bulk UPSERT for students via PostgreSQL COPY staging.

Uses the same CSV parsing rules as import_students_csv.py, then:
  1. deletes blank placeholder duplicates when a full row already exists for institute_id + sr_no,
  2. updates existing rows by institute_id + user_id,
  3. updates old blank placeholder rows by institute_id + sr_no,
  4. inserts remaining missing rows.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import filter_students_csv_for_import as filt  # noqa: E402
import import_institutes_csv as icu  # noqa: E402
import import_students_csv as stu  # noqa: E402
import fast_load_students_pg_copy as fast  # noqa: E402


def _clean_copy_text(value):
    if isinstance(value, str):
        return " ".join(value.split())
    if isinstance(value, list):
        return [_clean_copy_text(v) for v in value]
    return value


def _row_from_payload_for_copy(payload: dict) -> tuple:
    return tuple(_clean_copy_text(payload.get(col)) for col in fast.COPY_COLUMNS)


def main() -> None:
    try:
        import psycopg
    except ImportError:
        print("Install psycopg: pip install -r scripts/requirements-fast-pg-load.txt", file=sys.stderr)
        sys.exit(1)

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("csv_path")
    ap.add_argument("--match", choices=("user_id", "id", "sr_no"), default="user_id")
    ap.add_argument("--allow-zero-subjects", action="store_true")
    ap.add_argument("--max-subjects", type=int, default=8)
    ap.add_argument("--env-file", default=None)
    ap.add_argument("--no-dotenv", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--copy-chunk-rows", type=int, default=5000)
    ap.add_argument("--start-chunk", type=int, default=1)
    ap.add_argument("--chunk-retries", type=int, default=5)
    ap.add_argument("--skip-institutes-rest-check", action="store_true")
    ap.add_argument(
        "--source-of-truth",
        action="store_true",
        help="For institutes in the CSV, delete rows whose sr_no is not present in the CSV and reconcile by institute_id + sr_no.",
    )
    ap.add_argument("--ignore-institutes-file", default=None, metavar="PATH")
    ap.add_argument("--ignore-instid-form-tsv", default=None, metavar="PATH")
    ap.add_argument("--ignore-zero-subject-rows", action="store_true")
    ap.add_argument("--no-prefer-ipv4", action="store_false", dest="prefer_ipv4")
    ap.set_defaults(prefer_ipv4=True)
    args = ap.parse_args()

    icu.load_dotenv_merged(args.env_file, skip=args.no_dotenv)
    csv_path = Path(args.csv_path).expanduser()
    if not csv_path.is_file():
        print(f"Not found: {csv_path}", file=sys.stderr)
        sys.exit(1)

    ignore_inst: set[str] = set()
    if args.ignore_institutes_file:
        p = Path(args.ignore_institutes_file).expanduser()
        if p.is_file():
            ignore_inst = filt.load_inst_ids(p)

    ignore_pairs: set[tuple[str, str]] = set()
    if args.ignore_instid_form_tsv:
        p = Path(args.ignore_instid_form_tsv).expanduser()
        if p.is_file():
            ignore_pairs = filt.load_exclude_pairs(p)

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
            print(f"Unsafe institute id token(s): {unsafe[:20]}", file=sys.stderr)
            sys.exit(3)
        missing = [iid for iid in institute_ids if iid not in found]
        if missing:
            print(f"{len(missing)} institute id(s) missing in public.institutes.", file=sys.stderr)
            for iid in missing[:40]:
                print(f"  {iid}", file=sys.stderr)
            sys.exit(3)

    dsn = fast._database_url_from_env()
    dsn, pooler_note = fast._dsn_fix_supabase_session_pooler_user(psycopg, dsn)
    if pooler_note:
        print(pooler_note, file=sys.stderr)
    if args.prefer_ipv4:
        dsn, ipv4_note = fast._dsn_prefer_ipv4(psycopg, dsn)
        if ipv4_note:
            print(ipv4_note, file=sys.stderr)
    dsn = fast._dsn_merge_tcp_keepalives(psycopg, dsn)

    cols_sql = ",".join(fast.COPY_COLUMNS)
    set_sql = ",\n      ".join(
        f"{col} = s.{col}"
        for col in fast.COPY_COLUMNS
        if col != "institute_id"
    )
    create_sql = """
CREATE TEMP TABLE _stu_upsert_staging (
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
) ON COMMIT DROP;
"""
    copy_stmt = f"COPY _stu_upsert_staging ({cols_sql}) FROM STDIN"
    select_cols = ", ".join(f"s.{col}" for col in fast.COPY_COLUMNS)
    insert_sql = f"""
INSERT INTO public.students ({cols_sql})
SELECT {select_cols}
FROM _stu_upsert_staging s
WHERE NOT EXISTS (
  SELECT 1 FROM public.students e
  WHERE e.institute_id = s.institute_id
    AND e.user_id IS NOT DISTINCT FROM s.user_id
    AND s.user_id IS NOT NULL
)
AND NOT EXISTS (
  SELECT 1 FROM public.students e
  WHERE e.institute_id = s.institute_id
    AND e.sr_no IS NOT DISTINCT FROM s.sr_no
    AND s.sr_no IS NOT NULL
);
"""
    update_by_user_id_sql = f"""
UPDATE public.students e
SET {set_sql}
FROM _stu_upsert_staging s
WHERE e.institute_id = s.institute_id
  AND e.user_id = s.user_id
  AND s.user_id IS NOT NULL;
"""
    update_blank_by_sr_sql = f"""
UPDATE public.students e
SET {set_sql}
FROM _stu_upsert_staging s
WHERE e.institute_id = s.institute_id
  AND e.sr_no IS NOT DISTINCT FROM s.sr_no
  AND s.sr_no IS NOT NULL
  AND coalesce(nullif(btrim(e.name), ''), nullif(btrim(e.user_id), '')) IS NULL;
"""
    update_by_sr_sql = f"""
UPDATE public.students e
SET {set_sql}
FROM _stu_upsert_staging s
WHERE e.institute_id = s.institute_id
  AND e.sr_no IS NOT DISTINCT FROM s.sr_no
  AND s.sr_no IS NOT NULL;
"""
    delete_not_in_source_sql = """
DELETE FROM public.students e
WHERE EXISTS (
  SELECT 1 FROM _stu_upsert_staging s WHERE s.institute_id = e.institute_id
)
AND NOT EXISTS (
  SELECT 1 FROM _stu_upsert_staging s
  WHERE s.institute_id = e.institute_id
    AND s.sr_no IS NOT DISTINCT FROM e.sr_no
    AND s.sr_no IS NOT NULL
);
"""
    delete_blank_duplicates_sql = """
DELETE FROM public.students blank
USING public.students filled
WHERE blank.id <> filled.id
  AND blank.institute_id = filled.institute_id
  AND blank.sr_no IS NOT DISTINCT FROM filled.sr_no
  AND blank.sr_no IS NOT NULL
  AND coalesce(nullif(btrim(blank.name), ''), nullif(btrim(blank.user_id), '')) IS NULL
  AND coalesce(nullif(btrim(filled.name), ''), nullif(btrim(filled.user_id), '')) IS NOT NULL;
"""

    total_rows = sum(len(bucket) for bucket in agg.aggregated.values())
    merged = agg.rows_into_agg - total_rows
    print(
        f"Bulk upsert: {total_rows} unique CSV student rows across {len(institute_ids)} institutes "
        f"(merged duplicate CSV keys: {merged}).",
        flush=True,
    )
    if args.dry_run:
        print("Dry run parsed CSV and verified institutes only. No database writes.")
        return

    payload_rows = [
        payload
        for iid in sorted(agg.aggregated.keys(), key=lambda x: str(x))
        for _mk, payload in agg.aggregated[iid].items()
    ]
    chunk_size = max(1, args.copy_chunk_rows)
    chunks = [payload_rows[i : i + chunk_size] for i in range(0, len(payload_rows), chunk_size)]

    written = 0
    total_deleted_blank = 0
    total_deleted_not_in_source = 0
    total_updated_by_user = 0
    total_updated_by_sr = 0
    total_updated_blank = 0
    total_inserted = 0
    for chunk_index, chunk in enumerate(chunks, start=1):
        if chunk_index < args.start_chunk:
            continue
        attempt = 1
        while True:
            print(
                f"Chunk {chunk_index}/{len(chunks)}: processing {len(chunk)} row(s)"
                f"{'' if attempt == 1 else f' (retry {attempt}/{args.chunk_retries})'}...",
                flush=True,
            )
            try:
                try:
                    conn_cm = psycopg.connect(dsn)
                except Exception as e:
                    fast._pg_network_allow_list_hints(e)
                    fast._pg_password_auth_hints(e, dsn)
                    fast._pg_connect_timeout_hints(e)
                    raise

                with conn_cm as conn:
                    with conn.cursor() as cur:
                        cur.execute(create_sql)
                        with cur.copy(copy_stmt) as cp:
                            for payload in chunk:
                                cp.write_row(_row_from_payload_for_copy(payload))
                        cur.execute("CREATE INDEX ON _stu_upsert_staging (institute_id, user_id);")
                        cur.execute("CREATE INDEX ON _stu_upsert_staging (institute_id, sr_no);")
                        cur.execute(delete_blank_duplicates_sql)
                        total_deleted_blank += cur.rowcount
                        if args.source_of_truth:
                            cur.execute(delete_not_in_source_sql)
                            total_deleted_not_in_source += cur.rowcount
                            cur.execute(update_by_sr_sql)
                            total_updated_by_sr += cur.rowcount
                        else:
                            cur.execute(update_by_user_id_sql)
                            total_updated_by_user += cur.rowcount
                            cur.execute(update_blank_by_sr_sql)
                            total_updated_blank += cur.rowcount
                        cur.execute(insert_sql)
                        total_inserted += cur.rowcount
                written += len(chunk)
                break
            except Exception as e:
                if attempt >= args.chunk_retries:
                    raise
                wait = min(20.0, 0.75 * (2 ** (attempt - 1)))
                print(f"Chunk {chunk_index} failed: {e}. Retrying after {wait:.1f}s...", file=sys.stderr)
                time.sleep(wait)
                attempt += 1

    print(
        "Done. "
        f"staged={written}, deleted_blank_duplicates={total_deleted_blank}, "
        f"deleted_not_in_source={total_deleted_not_in_source}, "
        f"updated_by_user_id={total_updated_by_user}, updated_blank_by_sr_no={total_updated_blank}, "
        f"updated_by_sr_no={total_updated_by_sr}, "
        f"inserted={total_inserted}.",
        flush=True,
    )
    print("Run scripts/reconcile_institute_student_counts.sql if institute student_count must be refreshed.", file=sys.stderr)


if __name__ == "__main__":
    main()
