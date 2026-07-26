#!/usr/bin/env python3
"""
Fast path: INSERT many students via PostgreSQL COPY (same CSV rules as import_students_csv.py).

Much faster than Supabase REST for large loads. Does **NOT** PATCH existing rows — by default skips
students that already exist for the same (institute_id, sr_no). Use `--allow-duplicates` to disable
skip (dangerous duplicates).

Requirements:
  pip install -r scripts/requirements-fast-pg-load.txt

Connection strings (pick one — **prefer Session pooler on Mac / IPv4-only networks**):

  **Session pooler (IPv4 + IPv6)** — Dashboard → **Connect** → **Session pooler** → copy URI:

    export DATABASE_SESSION_POOL_URL="postgres://postgres.YOUR_PROJECT_REF:PASSWORD@aws-0-YOUR_REGION.pooler.supabase.com:5432/postgres"

  User looks like ``postgres.<project_ref>``, host ends with ``.pooler.supabase.com``. Use **session** mode (**5432**) for this script (**COPY**).

  Alternatively set ``DATABASE_URL`` to that same string, or ``DATABASE_POOL_URL``.

  **Direct** (`db.PROJECT.supabase.co:5432`) is often **IPv6-only**; timeouts are common without IPv6 routing.

If you see **`address not in tenant allow_list`**, open Dashboard → Database → **Network Restrictions**:
add your public IP or temporarily allow all. See https://supabase.com/docs/guides/platform/network-restrictions

If **`password authentication failed for user "postgres"`** on `*.pooler.supabase.com`, the URI must use
user **`postgres.<project_ref>`**. This script can rewrite plain **`postgres`** automatically when
**`SUPABASE_URL`** or **`SUPABASE_PROJECT_REF`** is set in `.env`.

Defaults add **IPv4 `hostaddr`** when DNS has an A record. Disable with ``--no-prefer-ipv4``.

Large loads through poolers/Wi‑Fi sometimes fail mid‑COPY with **SSL bad record MAC** / **connection is lost**.
The script defaults to **chunked COPY** (see ``--copy-chunk-rows``) and enables TCP keepalives on the DSN.
Try ``--no-prefer-ipv4`` or ``--copy-new-connection-each-chunk`` if errors persist.

Also respects repo root `.env`:

  ``DATABASE_SESSION_POOL_URL``, ``DATABASE_POOL_URL``, ``DATABASE_URL``, ``SUPABASE_DB_URL``, ``DIRECT_DATABASE_URL``
  (first non-empty wins).

Example:

  python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \\
    --match sr_no --max-subjects 5 --ignore-zero-subject-rows
"""

from __future__ import annotations

import argparse
import os
import re
import socket
import sys
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

COPY_COLUMNS = (
    "institute_id",
    "name",
    "first_name",
    "middle_name",
    "last_name",
    "user_id",
    "sr_no",
    "year",
    "lecture_timing",
    "subject",
    "subjects",
    "semester",
    "semester_name",
    "status",
    "role",
    "uid",
    "has_device",
)


def _row_from_payload(pl: dict) -> tuple:
    return tuple(pl.get(col) for col in COPY_COLUMNS)


def _iter_agg_payloads_in_order(agg) -> object:
    for iid in sorted(agg.aggregated.keys(), key=lambda x: str(x)):
        for _mk, pl in agg.aggregated[iid].items():
            yield pl


def _dsn_merge_tcp_keepalives(psycopg_module, dsn: str) -> str:
    ci = psycopg_module.conninfo
    try:
        opts = dict(ci.conninfo_to_dict(dsn))
    except Exception:
        return dsn
    if not str(opts.get("keepalives") or "").strip():
        opts["keepalives"] = "1"
    if not str(opts.get("keepalives_idle") or "").strip():
        opts["keepalives_idle"] = (
            os.environ.get("SUPABASE_PG_KEEPALIVES_IDLE") or "30"
        ).strip() or "30"
    if not str(opts.get("keepalives_interval") or "").strip():
        opts["keepalives_interval"] = (
            os.environ.get("SUPABASE_PG_KEEPALIVES_INTERVAL") or "10"
        ).strip() or "10"
    if not str(opts.get("keepalives_count") or "").strip():
        opts["keepalives_count"] = (
            os.environ.get("SUPABASE_PG_KEEPALIVES_COUNT") or "6"
        ).strip() or "6"
    try:
        return ci.make_conninfo(**opts)
    except Exception:
        return dsn


def _dsn_prefer_ipv4(psycopg_module, dsn: str) -> tuple[str, str]:
    """
    Add hostaddr=<IPv4> so the TCP route uses IPv4; keep host= for certificate name (libpq).
    Returns (connection_string, stderr_note_or_empty).
    """
    ci = psycopg_module.conninfo
    try:
        opts = dict(ci.conninfo_to_dict(dsn))
    except Exception:
        return dsn, ""
    if opts.get("hostaddr"):
        return dsn, ""
    host = (opts.get("host") or "").strip()
    if not host or host.startswith("/"):
        return dsn, ""
    port_s = str(opts.get("port") or "5432")
    try:
        port = int(port_s)
    except ValueError:
        port = 5432

    try:
        infos = socket.getaddrinfo(
            host,
            port,
            socket.AF_INET,
            socket.SOCK_STREAM,
            socket.IPPROTO_TCP,
        )
    except OSError as e:
        return dsn, f"prefer-ipv4: no IPv4 A record for {host!r} ({e}); using default DNS only."
    ipv4 = infos[0][4][0]
    opts["hostaddr"] = ipv4
    try:
        return ci.make_conninfo(**opts), (
            f"prefer-ipv4: using hostaddr={ipv4} (TLS host {host!r}) to avoid broken IPv6 routes."
        )
    except Exception:
        return dsn, ""


def _pg_connect_timeout_hints(exc: BaseException) -> None:
    msg = str(exc).lower()
    if "timed out" not in msg and "timeout" not in msg:
        return
    print(
        "\n--- Postgres connection troubleshooting ---\n"
        "• Direct host db.*.supabase.co often resolves to IPv6 only; many LANs block or break IPv6 to port 5432.\n"
        "• Fix: Dashboard → Connect → **Session pooler** → copy URI (user postgres.<project_ref>, host *.pooler.supabase.com:5432).\n"
        "  Set DATABASE_SESSION_POOL_URL or DATABASE_URL to that URI (not transaction mode :6543).\n"
        "• Or enable project **IPv4** add-on for direct connections, or try another network / hotspot / VPN.\n"
        "• Confirm outbound TCP **5432** is allowed.\n",
        file=sys.stderr,
    )


def _pg_ssl_copy_stream_hints(exc: BaseException) -> None:
    msg = str(exc).lower()
    if (
        "bad record mac" not in msg
        and "ssl" not in msg
        and "connection is lost" not in msg
        and "copy data" not in msg
    ):
        return
    print(
        "\n--- COPY / TLS stream dropped ---\n"
        "Common with long COPY over VPN, Wi‑Fi, or poolers.\n"
        "• Script defaults to chunked COPY; try smaller chunks:  ``--copy-chunk-rows 5000``.\n"
        "• Try ``--copy-new-connection-each-chunk`` (fresh TLS per chunk).\n"
        "• Try ``--no-prefer-ipv4`` (avoid hostaddr + TLS edge cases).\n"
        "• Use wired Ethernet, disable VPN, or run from a cloud VM closer to the DB region.\n"
        "• For maximum stability on huge loads, use **direct** ``db.*.supabase.co`` (IPv6 or IPv4 add‑on).\n",
        file=sys.stderr,
    )


def _pg_network_allow_list_hints(exc: BaseException) -> None:
    msg = str(exc).lower()
    if "allow_list" not in msg and "eaddrnotallowed" not in msg:
        return
    print(
        "\n--- Supabase: Database network restrictions blocked this machine ---\n"
        "The pooler/database only accepts IPs on your project's allow list.\n"
        "Fix: Dashboard → **Project Settings** → **Database** → **Network Restrictions**\n"
        "  • Add your current public IPv4/IPv6 (e.g. from https://whatismyip.akamai.com )\n"
        "  • Or temporarily **Allow all** while running a bulk import (tighten again afterward).\n"
        "Docs: https://supabase.com/docs/guides/platform/network-restrictions\n",
        file=sys.stderr,
    )


def _pg_password_auth_hints(exc: BaseException, dsn: str) -> None:
    msg = str(exc).lower()
    if "password authentication failed" not in msg:
        return
    dl = dsn.lower()
    pooler = ".pooler.supabase.com" in dl
    print(
        "\n--- Postgres: password rejected ---\n"
        "• Use the **database password** from Dashboard → **Project Settings** → **Database** "
        "(not the anon/service_role API keys).\n",
        file=sys.stderr,
        end="",
    )
    if pooler:
        print(
            "• **Session pooler** URIs must use user **postgres.<your_project_ref>** "
            "(copy the full URI from Dashboard → **Connect** → **Session pooler**). "
            "Plain user **postgres** often fails on pooler hosts.\n"
            "• If your password has `@`, `#`, etc., URL-encode it in the connection string.\n",
            file=sys.stderr,
        )
    else:
        print(
            "• Direct connection uses user **postgres** and host **db.<project>.supabase.co**.\n",
            file=sys.stderr,
        )


_SUPABASE_PUBLIC_URL_REF = re.compile(
    r"https?://([a-z0-9][a-z0-9_-]*)\.supabase\.co/?",
    re.IGNORECASE,
)


def _supabase_project_ref_from_env() -> str | None:
    for key in ("SUPABASE_PROJECT_REF", "SUPABASE_REF"):
        v = (os.environ.get(key) or "").strip().lower()
        if v:
            return v
    for key in (
        "SUPABASE_URL",
        "NEXT_PUBLIC_SUPABASE_URL",
        "EXPO_PUBLIC_SUPABASE_URL",
    ):
        url = (os.environ.get(key) or "").strip()
        if not url:
            continue
        m = _SUPABASE_PUBLIC_URL_REF.match(url)
        if m:
            return m.group(1).lower()
    return None


def _dsn_fix_supabase_session_pooler_user(psycopg_module, dsn: str) -> tuple[str, str]:
    """
    Session pooler rejects libpq user 'postgres'; Dashboard URIs use 'postgres.<project_ref>'.
    If host is pooler and user is exactly postgres, rewrite using SUPABASE_URL / SUPABASE_PROJECT_REF.
    """
    ci = psycopg_module.conninfo
    try:
        opts = dict(ci.conninfo_to_dict(dsn))
    except Exception:
        return dsn, ""
    host = (opts.get("host") or "").lower()
    user = (opts.get("user") or "").strip()
    if ".pooler.supabase.com" not in host or user != "postgres":
        return dsn, ""
    ref = _supabase_project_ref_from_env()
    if not ref:
        return dsn, ""
    opts["user"] = f"postgres.{ref}"
    try:
        new_dsn = ci.make_conninfo(**opts)
        return new_dsn, (
            "session pooler: DB user was 'postgres'; using "
            f"'postgres.{ref}' (from SUPABASE_URL or SUPABASE_PROJECT_REF in env)."
        )
    except Exception:
        return dsn, ""


def _looks_like_supabase_direct_db_uri(dsn: str) -> bool:
    dl = dsn.lower()
    return (
        "db." in dl
        and ".supabase.co" in dl
        and ".pooler.supabase.com" not in dl
    )


def _database_url_from_env() -> str:
    for key in (
        "DATABASE_SESSION_POOL_URL",
        "DATABASE_POOL_URL",
        "DATABASE_URL",
        "SUPABASE_DB_URL",
        "DIRECT_DATABASE_URL",
    ):
        v = (os.environ.get(key) or "").strip()
        if v:
            return v
    print(
        "Missing Postgres URI. Prefer Session pooler (IPv4): Dashboard → Connect → Session pooler, then set "
        "DATABASE_SESSION_POOL_URL or DATABASE_URL in .env. Add ?sslmode=require if needed.",
        file=sys.stderr,
    )
    sys.exit(1)


def main() -> None:
    try:
        import psycopg
    except ImportError:
        print(
            "Install psycopg:  pip install -r scripts/requirements-fast-pg-load.txt",
            file=sys.stderr,
        )
        sys.exit(1)

    import import_institutes_csv as icu

    import import_students_csv as stu

    import filter_students_csv_for_import as filt

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("csv_path")
    ap.add_argument("--institute-id", default=None)
    ap.add_argument(
        "--match",
        choices=("user_id", "id", "sr_no"),
        default="user_id",
    )
    ap.add_argument("--allow-zero-subjects", action="store_true")
    ap.add_argument("--max-subjects", type=int, default=5)
    ap.add_argument("--ignore-institutes-file", default=None, metavar="PATH")
    ap.add_argument("--ignore-instid-form-tsv", default=None, metavar="PATH")
    ap.add_argument("--ignore-zero-subject-rows", action="store_true")
    ap.add_argument(
        "--allow-duplicates",
        action="store_true",
        help="COPY all rows without skipping (institute_id, sr_no) already present (NOT recommended)",
    )
    ap.add_argument(
        "--skip-institutes-rest-check",
        action="store_true",
        help="Do not verify institute ids via REST against public.institutes (risk FK failure on INSERT)",
    )
    ap.add_argument("--env-file", default=None)
    ap.add_argument("--no-dotenv", action="store_true")
    ap.add_argument(
        "--no-prefer-ipv4",
        action="store_false",
        dest="prefer_ipv4",
        help="Do not set libpq hostaddr to IPv4 (use if you need default DNS / IPv6-only)",
    )
    ap.set_defaults(prefer_ipv4=True)
    args = ap.parse_args()

    icu.load_dotenv_merged(args.env_file, skip=args.no_dotenv)
    csv_path = Path(args.csv_path).expanduser()
    if not csv_path.is_file():
        print(f"Not found: {csv_path}", file=sys.stderr)
        sys.exit(1)

    cli_inst = None
    if args.institute_id:
        cli_inst = str(args.institute_id).strip().lstrip("\ufeff")
        if not cli_inst:
            print("--institute-id empty", file=sys.stderr)
            sys.exit(1)

    ignore_inst: set[str] = set()
    if args.ignore_institutes_file:
        p = Path(args.ignore_institutes_file).expanduser()
        if p.is_file():
            ignore_inst = filt.load_inst_ids(p)

    pairs: set[tuple[str, str]] = set()
    if args.ignore_instid_form_tsv:
        p = Path(args.ignore_instid_form_tsv).expanduser()
        if p.is_file():
            pairs = filt.load_exclude_pairs(p)

    agg = stu.aggregate_student_rows_from_csv(
        csv_path,
        cli_institute_id=cli_inst,
        match=args.match,
        allow_zero_subjects=args.allow_zero_subjects,
        max_subjects=args.max_subjects,
        ignore_institutes=ignore_inst,
        ignore_pairs=pairs,
        ignore_zero_subject_rows=args.ignore_zero_subject_rows,
        verbose_row_skips=False,
    )
    if not agg.aggregated:
        print("No student rows.", file=sys.stderr)
        sys.exit(1)

    institute_ids = sorted(agg.aggregated.keys(), key=lambda x: str(x))
    if not args.skip_institutes_rest_check:
        base_url, key = icu.supabase_rest_credentials()
        found, unsafe = stu.fetch_institute_ids_that_exist(base_url, key, institute_ids)
        if unsafe:
            print("Unsafe institute id token(s)", file=sys.stderr)
            sys.exit(3)
        missing = [i for i in institute_ids if i not in found]
        if missing:
            print(
                f"{len(missing)} institute id(s) from CSV missing in public.institutes — import institutes first:",
                file=sys.stderr,
            )
            for x in missing[:40]:
                print(f"  {x}", file=sys.stderr)
            sys.exit(3)

    cols_sql = ",".join(COPY_COLUMNS)
    select_s = ", ".join(f"s.{c}" for c in COPY_COLUMNS)

    create_sql = """
CREATE TEMP TABLE _stu_copy_staging (
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

    if args.allow_duplicates:
        insert_sql = f"INSERT INTO public.students ({cols_sql}) SELECT {select_s} FROM _stu_copy_staging s"
    else:
        insert_sql = f"""
INSERT INTO public.students ({cols_sql})
SELECT {select_s}
FROM _stu_copy_staging s
WHERE NOT EXISTS (
  SELECT 1 FROM public.students e
  WHERE e.institute_id = s.institute_id
    AND e.sr_no IS NOT DISTINCT FROM s.sr_no
)
"""

    dsn = _database_url_from_env()
    dsn, pooler_user_note = _dsn_fix_supabase_session_pooler_user(psycopg, dsn)
    if pooler_user_note:
        print(pooler_user_note, file=sys.stderr)
    if _looks_like_supabase_direct_db_uri(dsn):
        print(
            "Note: DATABASE_URL uses direct Supabase db.* host (often IPv6-only). "
            "For IPv4/Mac networks, Dashboard → Connect → Session pooler and set DATABASE_SESSION_POOL_URL or replace DATABASE_URL.",
            file=sys.stderr,
        )

    env_pv = (os.environ.get("SUPABASE_PG_PREFER_IPV4") or "").strip().lower()
    prefer_ipv4 = args.prefer_ipv4
    if env_pv in {"0", "false", "no"}:
        prefer_ipv4 = False
    elif env_pv in {"1", "true", "yes"}:
        prefer_ipv4 = True
    if prefer_ipv4:
        dsn, ipv4_note = _dsn_prefer_ipv4(psycopg, dsn)
        if ipv4_note:
            print(ipv4_note, file=sys.stderr)
    n_written = 0
    merged = agg.rows_into_agg - sum(len(b) for b in agg.aggregated.values())

    total_rows = sum(len(b) for b in agg.aggregated.values())

    print(
        f"COPY pipeline: ~{total_rows} unique student rows (after merge dedupe {merged}); connecting…",
        file=sys.stderr,
    )

    copy_stmt = f"COPY _stu_copy_staging ({cols_sql}) FROM STDIN"

    try:
        conn_cm = psycopg.connect(dsn)
    except Exception as e:
        _pg_network_allow_list_hints(e)
        _pg_password_auth_hints(e, dsn)
        _pg_connect_timeout_hints(e)
        raise

    with conn_cm as conn:
        with conn.cursor() as cur:
            cur.execute(create_sql)
            with cur.copy(copy_stmt) as cp:
                for iid in sorted(agg.aggregated.keys()):
                    for _mk, pl in agg.aggregated[iid].items():
                        cp.write_row(_row_from_payload(pl))
                        n_written += 1
            cur.execute(insert_sql)
            inserted = cur.rowcount if cur.rowcount is not None else -1

    print(
        f"Loaded {n_written} row(s) via COPY staging; INSERT added {inserted} new row(s) "
        + ("(all rows forced)" if args.allow_duplicates else "(skipped existing institute_id + sr_no)"),
        flush=True,
    )
    print("Run scripts/reconcile_institute_student_counts.sql if you rely on institute student_count.", file=sys.stderr)


if __name__ == "__main__":
    main()
