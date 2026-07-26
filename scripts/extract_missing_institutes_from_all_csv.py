#!/usr/bin/env python3
"""
From scripts/ALL_INSTITUTE.csv (wide master list), output only institutes whose
GCC code appears in scripts/missing_institute_ids_static.txt — ready for
import_institutes_csv.py (same columns as institutes_import_template.csv).

Does not touch ALL_INSTITUTE.csv.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent


def load_missing_ids(path: Path) -> set[str]:
    out: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.split("#", 1)[0].strip()
        if s:
            out.add(s)
    return out


TEMPLATE_FIELDS = [
    "SR NO",
    "FIRST",
    "MIDDLE",
    "LAST NAME",
    "MOBILE NO",
    "emailid",
    "instname",
    "isntadd",
    "gccinstcode",
    "dist",
    "taluka",
    "pincode",
    "region",
]


def norm_key(s: str) -> str:
    return "".join((s or "").split()).strip().lstrip("\ufeff")


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Extract missing institutes from ALL_INSTITUTE.csv for import_institutes_csv.py."
    )
    ap.add_argument(
        "--all-csv",
        default=str(_SCRIPTS / "ALL_INSTITUTE.csv"),
        metavar="PATH",
        help="Master institute extract (default: scripts/ALL_INSTITUTE.csv)",
    )
    ap.add_argument(
        "--missing-ids",
        default=str(_SCRIPTS / "missing_institute_ids_static.txt"),
        metavar="PATH",
        help="One institute id per line (default: scripts/missing_institute_ids_static.txt)",
    )
    ap.add_argument(
        "-o",
        "--output",
        default=str(_SCRIPTS / "missing_institutes_from_ALL_INSTITUTE.csv"),
        metavar="PATH",
        help="Output CSV for import_institutes_csv.py",
    )
    args = ap.parse_args()

    miss_path = Path(args.missing_ids).expanduser()
    all_path = Path(args.all_csv).expanduser()
    out_path = Path(args.output).expanduser()

    if not miss_path.is_file():
        print(f"Not found: {miss_path}", file=sys.stderr)
        sys.exit(1)
    if not all_path.is_file():
        print(f"Not found: {all_path}", file=sys.stderr)
        sys.exit(1)

    want = load_missing_ids(miss_path)

    rows_out: list[dict[str, str]] = []
    found_ids: set[str] = set()

    with all_path.open(newline="", encoding="utf-8-sig") as fh:
        r = csv.DictReader(fh)
        if not r.fieldnames:
            print("ALL CSV has no header row.", file=sys.stderr)
            sys.exit(1)
        lower_map = {norm_key(f).lower(): f for f in r.fieldnames if f}

        def pick(*candidates: str) -> str | None:
            for n in candidates:
                k = n.lower()
                if k in lower_map:
                    return lower_map[k]
            return None

        col_inst = pick("INST_CODE")
        fc = pick("FIRST_NAME")
        fm = pick("MIDDLE_NAME")
        fl = pick("LAST_NAME")
        fcname = pick("INST_NAME")
        faddr = pick("INST_ADD")
        fem = pick("EMAIL")
        fpin = pick("PINCODE")
        fmob = pick("MOB_PRINC")
        fdist = pick("DISTRICT")
        ftal = pick("TALUKA")

        required = (
            ("INST_CODE", col_inst),
            ("FIRST_NAME", fc),
            ("MIDDLE_NAME", fm),
            ("LAST_NAME", fl),
            ("INST_NAME", fcname),
            ("INST_ADD", faddr),
            ("EMAIL", fem),
            ("PINCODE", fpin),
            ("MOB_PRINC", fmob),
            ("DISTRICT", fdist),
            ("TALUKA", ftal),
        )
        missing_hdr = [n for n, v in required if not v]
        if missing_hdr:
            print(f"HEADER mapping failed — missing mapping for: {missing_hdr}", file=sys.stderr)
            print(f"Saw columns: {r.fieldnames}", file=sys.stderr)
            sys.exit(1)

        assert col_inst is not None and fc and fm and fl and fcname and faddr
        assert fem and fpin and fmob and fdist and ftal

        idx = 0
        for row in r:
            code = norm_key(row.get(col_inst) or "")
            if not code or code not in want:
                continue
            found_ids.add(code)
            idx += 1

            mob_raw = row.get(fmob) or ""

            rows_out.append(
                {
                    "SR NO": str(idx),
                    "FIRST": (row.get(fc) or "").strip(),
                    "MIDDLE": (row.get(fm) or "").strip(),
                    "LAST NAME": (row.get(fl) or "").strip(),
                    "MOBILE NO": "".join(ch for ch in mob_raw if ch.isdigit() or ch in "+ ").strip(),
                    "emailid": (row.get(fem) or "").strip(),
                    "instname": (row.get(fcname) or "").strip(),
                    "isntadd": (row.get(faddr) or "").strip(),
                    "gccinstcode": code,
                    "dist": (row.get(fdist) or "").strip(),
                    "taluka": (row.get(ftal) or "").strip(),
                    "pincode": (row.get(fpin) or "").strip(),
                    "region": "",
                }
            )

    def _id_sort(x: str) -> tuple[int, str]:
        try:
            return int(x), x
        except ValueError:
            return 10**18, x

    not_found = sorted(want - found_ids, key=_id_sort)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as fo:
        w = csv.DictWriter(fo, fieldnames=TEMPLATE_FIELDS)
        w.writeheader()
        w.writerows(rows_out)

    print(f"Requested {len(want)} id(s); wrote {len(rows_out)} institute row(s) → {out_path}", file=sys.stderr)
    if not_found:
        print(
            f"WARN: {len(not_found)} id(s) from missing list NOT found in {all_path.name}:",
            file=sys.stderr,
        )
        for u in not_found[:30]:
            print(f"  {u}", file=sys.stderr)
        if len(not_found) > 30:
            print(f"  … +{len(not_found) - 30} more", file=sys.stderr)


if __name__ == "__main__":
    main()
