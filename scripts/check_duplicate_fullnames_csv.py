#!/usr/bin/env python3
"""
Detect duplicate STUDENT FULL NAMES within the SAME institute only.

Full name = FNAME + MNAME + LNAME (trimmed; case-insensitive match).
Uses instid from CSV. Different institutes with the same spelling are NOT duplicates.

Example:
  python3 scripts/check_duplicate_fullnames_csv.py scripts/STUDENTS.csv
  python3 scripts/check_duplicate_fullnames_csv.py my.csv --out report.tsv
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple

DEFAULT_REL = Path("STUDENTS.csv")


def _norm(s: str) -> str:
    return " ".join((s or "").strip().upper().split())


def _norm_headers(raw: Dict[str, Any]) -> Dict[str, str]:
    return {
        " ".join(k.strip().upper().split()).replace(" ", "_"): (v.strip() if v else "")
        for k, v in raw.items()
        if k
    }


def _full_name(nrow: Dict[str, str]) -> str:
    fn = _norm(nrow.get("FNAME", ""))
    mn = _norm(nrow.get("MNAME", ""))
    ln = _norm(nrow.get("LNAME", ""))
    return " ".join(p for p in [fn, mn, ln] if p)


def _sort_key_serial(fs: str) -> Tuple[int, str]:
    s = fs.strip()
    return (int(s), s) if s.isdigit() else (10**18, s)


def find_duplicates(
    path: Path,
) -> Tuple[List[Tuple[str, str, List[Tuple[int, str]]]], int, int]:
    """
    Returns (list of (instid, full_name, [(csv_line, formserialno), ...]) for count>1,
             total_data_rows, total_rows_in_duplicate_groups).
    """
    by_key: Dict[Tuple[str, str], List[Tuple[int, str]]] = defaultdict(list)
    total = 0

    with path.open(encoding="utf-8-sig", newline="") as fh:
        rdr = csv.DictReader(fh)
        for line_no, raw in enumerate(rdr, start=2):
            nrow = _norm_headers(raw)
            inst = _norm(nrow.get("INSTID", ""))
            fnm = _full_name(nrow)
            fs = nrow.get("FORMSERIALNO", "").strip()
            if not inst or not fnm:
                continue
            total += 1
            by_key[(inst, fnm)].append((line_no, fs))

    dups_only: List[Tuple[str, str, List[Tuple[int, str]]]] = []
    in_dup_groups = 0
    for (inst, fnm), ents in sorted(by_key.items()):
        if len(ents) <= 1:
            continue
        sorted_ents = sorted(ents, key=lambda t: (_sort_key_serial(t[1]), t[0]))
        dups_only.append((inst, fnm, sorted_ents))
        in_dup_groups += len(sorted_ents)

    return dups_only, total, in_dup_groups


def main() -> None:
    ap = argparse.ArgumentParser(description="List duplicate full names per institute.")
    ap.add_argument("csv_path", nargs="?", default=None, help="Student CSV path")
    ap.add_argument(
        "--out",
        metavar="PATH",
        default=None,
        help="Write TSV (one row per duplicate group summary). Default: beside CSV as *_duplicate_fullnames.tsv",
    )
    args = ap.parse_args()

    scripts_dir = Path(__file__).resolve().parent
    cwd = Path.cwd()

    cand: Path
    if args.csv_path:
        cand = Path(args.csv_path).expanduser()
        if not cand.is_file():
            print(f"File not found: {cand}", file=sys.stderr)
            sys.exit(1)
    else:
        if (scripts_dir / DEFAULT_REL).is_file():
            cand = scripts_dir / DEFAULT_REL
        elif (cwd / DEFAULT_REL).is_file():
            cand = cwd / DEFAULT_REL
        else:
            print("Pass CSV path or place STUDENTS.csv in scripts/ or cwd.", file=sys.stderr)
            sys.exit(1)

    dups, total_rows, dup_row_count = find_duplicates(cand)

    if args.out:
        out_path = Path(args.out).expanduser()
    else:
        out_path = cand.parent / (cand.stem + "_duplicate_fullnames.tsv")

    group_idx = 0
    lines_out: List[str] = [
        "group_index\tinstid\tfull_name_fname_mname_lname\tduplicate_row_count\t"
        "csv_lines_comma\tformserialno_comma\n"
    ]
    for inst, fnm, ents in dups:
        group_idx += 1
        csv_lines = ",".join(str(x[0]) for x in ents)
        fss = ",".join(x[1] for x in ents)
        lines_out.append(
            f"{group_idx}\t{inst}\t{fnm}\t{len(ents)}\t{csv_lines}\t{fss}\n"
        )

    out_path.write_text("".join(lines_out), encoding="utf-8")

    n_groups = len(dups)
    extra_rows = dup_row_count - n_groups  # rows beyond one per group

    print(f"CSV: {cand}", file=sys.stderr)
    print(f"Total student rows (with instid+name): {total_rows}", file=sys.stderr)
    print(f"Duplicate-name groups (same inst, same full name, 2+ rows): {n_groups}", file=sys.stderr)
    print(f"Rows involved in those groups: {dup_row_count}", file=sys.stderr)
    print(f"Extra rows (would merge if keeping one per name): {extra_rows}", file=sys.stderr)
    print(f"Report written: {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
