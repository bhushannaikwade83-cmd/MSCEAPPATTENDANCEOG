#!/usr/bin/env python3
"""
Print institute id(s) from a student CSV (`instid`) that are NOT in `public.institutes`.
Uses SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (same .env as import scripts).
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

import import_institutes_csv as _icu  # noqa: E402
import import_students_csv as _stu  # noqa: E402


def _unique_instids(path: Path) -> list[str]:
    uniq: set[str] = set()
    with path.open(newline="", encoding="utf-8-sig") as fh:
        for raw in csv.DictReader(fh):
            norm = _icu._norm_row(raw)
            csv_raw = _icu._pick(
                norm,
                "INSTID",
                "INST ID",
                "INSTITUTE_ID",
                "INSTITUTE ID",
                "GCCINSTCODE",
            )
            s = "".join((csv_raw or "").split()).strip().lstrip("\ufeff")
            if s:
                uniq.add(s)

    def sort_key(x: str) -> tuple[int, str]:
        try:
            return int(x), x
        except ValueError:
            return 10**18, x

    return sorted(uniq, key=sort_key)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_path", nargs="?", default=str(_SCRIPTS / "STUDENTS.csv"))
    ap.add_argument("--env-file", metavar="PATH", default=None)
    ap.add_argument("--no-dotenv", action="store_true")
    ap.add_argument("--direct-http", action="store_true")
    args = ap.parse_args()

    _icu.set_import_http_options(force_direct=args.direct_http)
    _icu.load_dotenv_merged(args.env_file, skip=args.no_dotenv)
    base, key = _icu.supabase_rest_credentials()

    path = Path(args.csv_path).expanduser()
    if not path.is_file():
        print(f"Not found: {path}", file=sys.stderr)
        sys.exit(1)

    ids = _unique_instids(path)
    print(f"CSV: {len(ids)} distinct instid value(s). Checking public.institutes …", file=sys.stderr)

    found, unsafe = _stu.fetch_institute_ids_that_exist(base, key, ids)
    if unsafe:
        print("Unsafe institute id token(s) for REST filter:", file=sys.stderr)
        for u in unsafe:
            print(u, file=sys.stderr)
        sys.exit(2)

    missing = [i for i in ids if i not in found]
    print(f"Missing in database: {len(missing)} (exist: {len(found)}).", file=sys.stderr)
    print()
    for m in missing:
        print(m)


if __name__ == "__main__":
    main()
