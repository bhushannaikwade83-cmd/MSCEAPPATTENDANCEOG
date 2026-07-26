#!/usr/bin/env python3
"""
Merge CSV rows where instid + full name (FNAME+MNAME+LNAME) match.

All subject codes across the duplicate rows are unioned (case-insensitive); order follows
 ascending formserialno, scanning SUBJECT_1.. in order inside each row.
Codes fill SUBJECT_1..SUBJECT_N (from file headers); extra slots stay 0.
If merged code count exceeds N or --cap, truncate from the tail and record in --log.

Survivor = row with smallest formserialno; other duplicates are dropped.

  python3 scripts/merge_students_duplicate_name_subjects.py scripts/STUDENTS.csv \\
    --out scripts/STUDENTS_MERGED_one_row_per_name.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Optional, Tuple


def _norm(s: str) -> str:
    return " ".join((s or "").strip().upper().split())


def _can_header(h: str) -> str:
    return " ".join(h.strip().upper().split()).replace(" ", "_")


def _can_row(raw: Mapping[str, Any]) -> Dict[str, str]:
    return {_can_header(str(k)): ("" if raw.get(k) is None else str(raw[k]).strip()) for k in raw if k}


def _full_name(cr: Mapping[str, str]) -> str:
    fn = _norm(cr.get("FNAME", ""))
    mn = _norm(cr.get("MNAME", ""))
    ln = _norm(cr.get("LNAME", ""))
    return " ".join(p for p in [fn, mn, ln] if p)


def _serial_key(can: Mapping[str, str]) -> Tuple[int, str]:
    fs = (can.get("FORMSERIALNO") or "").strip()
    return (int(fs), fs) if fs.isdigit() else (10**12, fs)


def _codes_from(can: Mapping[str, str]) -> List[str]:
    keys = sorted(
        [k for k in can if str(k).upper().startswith("SUBJECT_")],
        key=lambda x: int(_can_header(str(x)).split("_")[-1]),
    )
    seen: Dict[str, bool] = {}
    out: List[str] = []
    for k in keys:
        rv = (can.get(k) or "").strip()
        if not rv or rv == "0" or rv.upper() == "NULL":
            continue
        low = rv.lower()
        if low in seen:
            continue
        seen[low] = True
        out.append(rv)
    return out


def _subject_headers(fieldnames: List[str]) -> List[str]:
    """Actual CSV headers for SUBJECT_* columns sorted by trailing number."""

    numbered: List[Tuple[int, str]] = []
    for h in fieldnames:
        nk = _can_header(h)
        m = re.match(r"^SUBJECT_(\d+)$", nk)
        if m:
            numbered.append((int(m.group(1)), h))
    numbered.sort(key=lambda t: t[0])
    return [h for _, h in numbered]


def _cols(fieldnames: List[str]) -> Tuple[str, str]:
    inst_h = next(h for h in fieldnames if _can_header(h) == "INSTID")
    fs_h = next(h for h in fieldnames if _can_header(h).replace("__", "").upper() == "FORMSERIALNO")
    return inst_h, fs_h


def merge(filepath: Path, outpath: Path, cap_codes: Optional[int], log_json: Optional[Path]) -> Tuple[int, int]:
    logs: List[dict] = []
    rows: List[MutableMapping[str, str]] = []
    canons: List[Dict[str, str]] = []

    with filepath.open(encoding="utf-8-sig", newline="") as fh:
        rdr = csv.DictReader(fh)
        fieldnames = list(rdr.fieldnames or [])
        if not fieldnames:
            sys.exit("empty CSV")

        slot_headers = _subject_headers(fieldnames)
        n_slots = len(slot_headers)

        for raw in rdr:
            rr = {k: "" if raw.get(k) is None else str(raw[k]) for k in fieldnames}
            rows.append(rr)
            canons.append(_can_row(rr))

    grp: Dict[Tuple[str, str], List[int]] = defaultdict(list)
    for i, cn in enumerate(canons):
        inst = _norm(cn.get("INSTID", ""))
        fn = _full_name(cn)
        if inst and fn:
            grp[(inst, fn)].append(i)

    inst_col, fs_col = _cols(fieldnames)
    slot_headers = _subject_headers(fieldnames)
    limit = len(slot_headers)

    merged_out: List[MutableMapping[str, str]] = []

    for i, crc in enumerate(canons):
        inst = _norm(crc.get("INSTID", ""))
        fn = _full_name(crc)
        if not inst or not fn:
            merged_out.append(dict(rows[i]))
            continue

        g = grp[(inst, fn)]
        if len(g) == 1:
            merged_out.append(dict(rows[i]))
            continue

        anchor = min(g)
        if i != anchor:
            continue

        order_idx = sorted(g, key=lambda j: (_serial_key(canons[j]), j))

        seen_lc_in_merge: Dict[str, bool] = {}
        seq: List[str] = []
        for j in order_idx:
            for c in _codes_from(canons[j]):
                lw = c.lower()
                if lw in seen_lc_in_merge:
                    continue
                seen_lc_in_merge[lw] = True
                seq.append(c)

        ceil = cap_codes if cap_codes is not None else limit
        final_seq = seq[:ceil]
        drop_tail = seq[ceil:]
        truncate_warn = bool(drop_tail)

        survivor_j = min(order_idx, key=lambda jj: (_serial_key(canons[jj]), jj))
        survivor = dict(rows[survivor_j])
        survivor_fs = (canons[survivor_j].get("FORMSERIALNO") or "").strip()

        survivor[inst_col] = survivor[inst_col].strip()
        survivor[fs_col] = survivor_fs

        for sj, hh in enumerate(slot_headers):
            survivor[hh] = final_seq[sj] if sj < len(final_seq) else "0"

        csv_line_no = lambda j: j + 2
        logs.append(
            {
                "kept_anchor_csv_line": csv_line_no(anchor),
                "survivor_csv_line": csv_line_no(survivor_j),
                "instid": inst,
                "full_name_normalized": fn,
                "merged_from_csv_lines": sorted(csv_line_no(j) for j in g),
                "merged_form_serials_in_order": [canons[j].get("FORMSERIALNO", "") for j in order_idx],
                "kept_formserialno_lowest_serial": survivor_fs,
                "union_subject_codes_ordered": seq,
                "written_to_columns": final_seq,
                "dropped_after_cap": drop_tail if truncate_warn else [],
                "cap_applied": ceil,
            }
        )

        merged_out.append(survivor)

    with outpath.open("w", encoding="utf-8-sig", newline="") as fh:
        wtr = csv.DictWriter(fh, fieldnames=fieldnames, extrasaction="ignore")
        wtr.writeheader()
        for rr in merged_out:
            wtr.writerow(rr)

    if log_json and logs:
        log_json.parent.mkdir(parents=True, exist_ok=True)
        log_json.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in logs), encoding="utf-8")

    return len(rows), len(merged_out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("csv_file", nargs="?", default=None)
    ap.add_argument(
        "--out",
        metavar="PATH",
        default=None,
        help="Output CSV (default: <input>_MERGED_duplicate_names.csv next to source)",
    )
    ap.add_argument(
        "--cap",
        type=int,
        default=None,
        metavar="N",
        help="Maximum distinct merged subject codes to write (default: number of SUBJECT_* columns)",
    )
    ap.add_argument(
        "--log",
        metavar="PATH",
        default=None,
        help="JSONL merge log path (default next to CSV: *_duplicate_name_merge.jsonl)",
    )
    args = ap.parse_args()

    scripts_dir = Path(__file__).resolve().parent
    src = Path(args.csv_file) if args.csv_file else scripts_dir / "STUDENTS.csv"
    src = src.expanduser()
    if not src.is_file():
        sys.exit(f"missing CSV: {src}")

    out_path = Path(args.out).expanduser() if args.out else src.parent / (src.stem + "_MERGED_duplicate_names.csv")
    log_path = Path(args.log).expanduser() if args.log else src.parent / (src.stem + "_duplicate_name_merge.jsonl")

    n_in, n_out = merge(src, out_path, cap_codes=args.cap, log_json=log_path)
    merged_rows = n_in - n_out
    print(f"Rows in: {n_in} | rows out: {n_out} (removed duplicate rows: {merged_rows})", file=sys.stderr)
    print(f"Wrote: {out_path}", file=sys.stderr)
    if log_path and log_path.is_file():
        print(f"Log: {log_path}", file=sys.stderr)


if __name__ == "__main__":
    main()