#!/usr/bin/env python3
"""
Filter a wide STUDENTS CSV: drop rows by institute id set and optional (instid, formserialno) pairs.
Writes UTF-8 CSV with same columns as input.
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


def load_inst_ids(path: Path) -> set[str]:
    out: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.split("#", 1)[0].strip()
        if s:
            out.add(s)
    return out


def load_exclude_pairs(tsv_path: Path) -> set[tuple[str, str]]:
    """TSV: columns instid, formserialno (header row okay)."""
    pairs: set[tuple[str, str]] = set()
    with tsv_path.open(newline="", encoding="utf-8-sig") as fh:
        r = csv.DictReader(fh, delimiter="\t")
        if not r.fieldnames:
            return pairs

        def col(*names: str) -> str | None:
            lower_map = {f.strip().lower(): f for f in r.fieldnames if f}
            for n in names:
                if n.lower() in lower_map:
                    return lower_map[n.lower()]
            return None

        ck = col("instid", "gccinstcode", "INSTID")
        fk = col("formserialno", "FORM SERIAL NO", "form serial no")
        if not ck or not fk:
            print("TSV must have instid and formserialno columns.", file=sys.stderr)
            sys.exit(1)
        for row in r:
            iid = "".join((row.get(ck) or "").split()).strip().lstrip("\ufeff")
            fs = (row.get(fk) or "").strip()
            if iid and fs:
                pairs.add((iid, fs))
    return pairs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("input_csv")
    ap.add_argument("-o", "--output", required=True, metavar="PATH")
    ap.add_argument(
        "--exclude-instids",
        metavar="PATH",
        help="Text file: one institute id per line (# comments ok)",
    )
    ap.add_argument(
        "--exclude-pairs-tsv",
        metavar="PATH",
        help="TSV with instid + formserialno (e.g. STUDENTS_zero_subjects_names.tsv)",
    )
    args = ap.parse_args()

    inp = Path(args.input_csv).expanduser()
    out = Path(args.output).expanduser()
    if not inp.is_file():
        print(f"Not found: {inp}", file=sys.stderr)
        sys.exit(1)

    bad_inst = load_inst_ids(Path(args.exclude_instids).expanduser()) if args.exclude_instids else set()
    bad_pairs = load_exclude_pairs(Path(args.exclude_pairs_tsv).expanduser()) if args.exclude_pairs_tsv else set()

    skipped_inst = skipped_pair = wrote = 0
    fieldnames: list[str] | None = None

    with inp.open(newline="", encoding="utf-8-sig") as fh_in:
        reader = csv.DictReader(fh_in)
        fieldnames = list(reader.fieldnames or [])
        if not fieldnames:
            print("Input CSV has no header.", file=sys.stderr)
            sys.exit(1)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", newline="", encoding="utf-8") as fh_out:
            writer = csv.DictWriter(fh_out, fieldnames=fieldnames, extrasaction="ignore")
            writer.writeheader()
            for raw in reader:
                norm = _icu._norm_row(raw)
                iid_raw = _icu._pick(
                    norm,
                    "INSTID",
                    "INST ID",
                    "INSTITUTE_ID",
                    "INSTITUTE ID",
                    "GCCINSTCODE",
                )
                iid = "".join((iid_raw or "").split()).strip().lstrip("\ufeff")
                fs = (
                    _icu._pick(
                        norm,
                        "FORMSERIALNO",
                        "FORM SERIAL NO",
                        "FORM_SERIAL_NO",
                        "FORM SERIAL",
                    )
                    or ""
                ).strip()
                if iid in bad_inst:
                    skipped_inst += 1
                    continue
                if bad_pairs and (iid, fs) in bad_pairs:
                    skipped_pair += 1
                    continue
                writer.writerow({k: raw.get(k, "") for k in fieldnames})
                wrote += 1

    print(
        f"Wrote {wrote} row(s) to {out} "
        f"(skipped {skipped_inst} row(s) on excluded institute id(s), "
        f"{skipped_pair} row(s) on excluded instid+formserialno).",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
