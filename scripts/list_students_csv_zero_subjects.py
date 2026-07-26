#!/usr/bin/env python3
"""List STUDENTS.csv rows that declare subjects but have zero enrolled codes (same rules as import_students_csv.py without --allow-zero-subjects)."""

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


def _subject_count(norm: dict[str, str]) -> tuple[bool, int]:
    """Returns (declares_subjects?, enrolled_count)."""
    subjects_raw = _icu._pick(norm, "SUBJECTS", "SUBJECT LIST")
    subject_legacy_col = (_icu._pick(norm, "SUBJECT") or "").strip()
    declares = _stu.row_declares_subject_fields(norm)
    subjects_val = None
    if subjects_raw.strip():
        parsed = _stu._parse_text_array(subjects_raw) or []
        subjects_val = _stu._dedupe_subject_codes(parsed)
    elif _stu._sorted_subject_slot_keys(norm):
        subjects_val = _stu.subjects_from_wide_slots(norm)
    elif subject_legacy_col:
        subjects_val = _stu._dedupe_subject_codes([subject_legacy_col])
    return declares, len(subjects_val or [])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_path", nargs="?", default=str(_SCRIPTS / "STUDENTS.csv"))
    ap.add_argument("-o", "--output", metavar="PATH", help="Write TSV here (default: stdout)")
    args = ap.parse_args()
    path = Path(args.csv_path).expanduser()
    if not path.is_file():
        print(f"Not found: {path}", file=sys.stderr)
        sys.exit(1)

    out_fp = open(args.output, "w", encoding="utf-8", newline="") if args.output else sys.stdout
    try:
        w = csv.writer(out_fp, delimiter="\t", lineterminator="\n")
        w.writerow(
            ["csv_row", "instid", "formserialno", "fname", "mname", "lname", "name_display"]
        )
        n = 0
        with path.open(newline="", encoding="utf-8-sig") as fh:
            for lineno, raw in enumerate(csv.DictReader(fh), start=2):
                norm = _icu._norm_row(raw)
                declares, cnt = _subject_count(norm)
                if not declares or cnt > 0:
                    continue
                instid = "".join((_icu._pick(norm, "INSTID", "INST ID", "INSTITUTE_ID") or "").split()).strip()
                fs = (_icu._pick(norm, "FORMSERIALNO", "FORM SERIAL NO") or "").strip()
                fn = (_icu._pick(norm, "FNAME", "FIRST", "FIRST NAME") or "").strip()
                mn = (_icu._pick(norm, "MNAME", "MIDDLE", "MIDDLE NAME") or "").strip()
                ln = (_icu._pick(norm, "LNAME", "LAST", "LAST NAME") or "").strip()
                name_explicit = (_icu._pick(norm, "NAME", "FULL NAME", "STUDENT NAME") or "").strip()
                display = name_explicit or _icu.admin_full_name(norm).strip()
                w.writerow([lineno, instid, fs, fn, mn, ln, display])
                n += 1
        if args.output:
            print(f"Wrote {n} row(s) to {args.output}", file=sys.stderr)
        else:
            print(f"# {n} row(s)", file=sys.stderr)
    finally:
        if args.output:
            out_fp.close()


if __name__ == "__main__":
    main()
