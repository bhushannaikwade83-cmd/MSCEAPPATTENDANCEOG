#!/usr/bin/env python3
"""
Bulk INSERT / PATCH **student** rows in `public.students` — this is where the **student
roster per institute** is loaded. Each CSV row carries `institute_id` from the **`instid`**
column (or `--institute-id`); rows never cross institutes.

(This is **not** the institutes directory import — that script only ensures parent rows
exist in `public.institutes`; use `scripts/import_institutes_csv.py` for name/address +
matching `id` = `gccinstcode` / CSV `instid`.)

Uses Supabase REST + service_role (same as scripts/import_institutes_csv.py).

  python3 scripts/import_students_csv.py scripts/STUDENTS.csv --match sr_no \\
    --allow-zero-subjects --max-subjects 5

Match existing rows (--match):
  user_id … ROLL / PRN / USER_ID (default)
  id      … STUDENT exports
  sr_no   … SR_NO or FORMSERIALNO / form serial sheets

Wide MSCE-style columns (Excel → Save as CSV):
  instid, formserialno, lname, fname, mname, SUBJECT_1 … SUBJECT_N
  (spreadsheet-friendly **names-first** layout instead: see students_minimal_names_first_example.csv)
  • Omit --institute-id to upload every institute found in instid column (rows never
    mix into another institute).
  • With --institute-id, CSV instid rows must agree (missing instid inherits CLI).
  • SUBJECT_*: "0" or empty = not enrolled; default **1–5** codes (override with --max-subjects / --allow-zero-subjects).

When FORMSERIALNO is present and roll/USER_ID is empty, `user_id` is set from the
form serial so new rows can INSERT (unique per institute).

Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (.env okay).

**Order:** `public.institutes` rows must exist with `id` = each CSV **`instid`**
(so the foreign key is valid). Bulk **institute** metadata → `import_institutes_csv.py`.
Bulk **student** data attached to those institutes → **this script** (`import_students_csv.py`).
Use `--write-missing-institutes-stub-csv PATH` to emit a starter institutes CSV when the DB lacks those ids.

Keep the master spreadsheet intact and **skip** rows at import time:
  • `--ignore-institutes-file PATH` — one institute id per line (`#` comments ok); drops all rows for those institutes.
  • `--ignore-instid-form-tsv PATH` — TSV with `instid` + `formserialno`; drops only those pairs (no CSV edits).
  • `--ignore-zero-subject-rows` — drops rows that declare `SUBJECT_*` / `SUBJECTS` but have zero enrolled codes (used by run_student_import.sh).

**One-institute CSV (no `instid` column — every row is the same institute):**
  • Leave out `instid` / blank it; pass `--institute-id <GCC code>` once (must match `institutes.id` in DB).
  • Rows must still use the same institute (if the sheet repeats `instid`, it must match `--institute-id`).
  • Example sheet: scripts/students_single_institute_example.csv

**Minimal row (fill the rest later in Supabase or by re-running this script):**
`instid` + name (`NAME` or `FIRST`/`MNAME`/`LNAME`), plus **one stable key per student** —
`FORMSERIALNO` or SR_NO if `--match sr_no`, or roll/PRN/`USER_ID` if `--match user_id`.
You can omit all `SUBJECT_*` columns when subjects are unknown (no `--allow-zero-subjects` needed);
if the sheet includes `SUBJECT_*` columns but they are empty, pass `--allow-zero-subjects`.

After a large import, refresh counters: run `scripts/reconcile_institute_student_counts.sql` in Supabase SQL.

Dry-run (no writes):

  python3 scripts/import_students_csv.py scripts/STUDENTS.csv --match sr_no \\
    --allow-zero-subjects --max-subjects 5 --dry-run

See scripts/students_minimal_names_first_example.csv (names-first, no subjects yet),
scripts/msce_student_wide_example.csv, and scripts/students_import_template.csv.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Mapping, MutableMapping, Optional, Tuple
from urllib.parse import quote

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import import_institutes_csv as _icu  # noqa: E402

import filter_students_csv_for_import as _csv_row_ignore  # noqa: E402

# Default subject bounds (overridden by student_row_payload(..., max_subjects=, allow_zero_subjects=)).


def _dedupe_subject_codes(raw_tokens: Optional[List[str]]) -> List[str]:
    """Trim, drop empty / "0" / NULL, case-insensitive de-dupe, preserve order."""
    if not raw_tokens:
        return []
    seen: Dict[str, bool] = {}
    out: List[str] = []
    for raw in raw_tokens:
        s = (raw or "").strip()
        if not s:
            continue
        if s == "0" or s.upper() == "NULL":
            continue
        low = s.lower()
        if low in seen:
            continue
        seen[low] = True
        out.append(s)
    return out


def _sorted_subject_slot_keys(norm: Dict[str, str]) -> List[str]:
    keys: List[Tuple[int, str]] = []
    for k in norm:
        up = str(k).strip().upper()
        m = re.match(r"^SUBJECT_(\d+)$", up)
        if m:
            keys.append((int(m.group(1)), up))
    keys.sort(key=lambda t: t[0])
    return [t[1] for t in keys]


def subjects_from_wide_slots(norm: Dict[str, str]) -> List[str]:
    vals: List[str] = []
    for slot in _sorted_subject_slot_keys(norm):
        vals.append(norm.get(slot) or "")
    return _dedupe_subject_codes(vals)


def row_declares_subject_fields(norm: Dict[str, str]) -> bool:
    """True when this row participates in subject count checks (unless --allow-zero-subjects for empty)."""
    if _icu._pick(norm, "SUBJECTS", "SUBJECT LIST").strip():
        return True
    if _sorted_subject_slot_keys(norm):
        return True
    if (_icu._pick(norm, "SUBJECT") or "").strip():
        return True
    return False


def resolve_institute_for_row(norm: Dict[str, str], cli_institute_id: Optional[str]) -> Tuple[Optional[str], Optional[str]]:
    """Returns (effective institute_id) or (None, skip_reason)."""
    csv_raw = _icu._pick(norm, "INSTID", "INST ID", "INSTITUTE_ID", "INSTITUTE ID", "GCCINSTCODE")
    csv_inst = "".join((csv_raw or "").split()).strip().lstrip("\ufeff")

    cli = (cli_institute_id or "").strip().lstrip("\ufeff")

    if cli:
        if not csv_inst:
            return cli, None
        if csv_inst != "".join(cli.split()).strip():
            return None, f"instid mismatch (CSV {csv_inst!r} ≠ --institute-id {cli!r})"
        return cli, None

    if csv_inst:
        return csv_inst, None
    return None, "missing instid / institute id column (set instid per row or pass --institute-id)"


def _parse_text_array(raw: str) -> Optional[List[str]]:
    """Postgres text[] CSV style {a,b,c} or plain comma list."""
    s = (raw or "").strip()
    if not s:
        return None
    if s.startswith("{") and s.endswith("}"):
        inner = s[1:-1].strip()
        if not inner:
            return []
        return [x.strip().strip('"').strip("'") for x in inner.split(",") if x.strip()]
    return [x.strip() for x in re.split(r"[,;]", s) if x.strip()]


def _subjects_values_from_norm(norm: Dict[str, str]) -> Optional[List[str]]:
    """Parsed enrolled subject codes (same rules as student_row_payload SUBJECT_* / SUBJECTS columns)."""
    subjects_raw = _icu._pick(norm, "SUBJECTS", "SUBJECT LIST")
    subject_legacy_col = (_icu._pick(norm, "SUBJECT") or "").strip()
    if subjects_raw.strip():
        parsed = _parse_text_array(subjects_raw) or []
        return _dedupe_subject_codes(parsed)
    if _sorted_subject_slot_keys(norm):
        return subjects_from_wide_slots(norm)
    if subject_legacy_col:
        return _dedupe_subject_codes([subject_legacy_col])
    return None


def student_row_payload(
    norm: Dict[str, str],
    *,
    institute_id: str,
    allow_zero_subjects: bool = False,
    max_subjects: int = 5,
) -> Tuple[Optional[MutableMapping[str, Any]], Optional[str]]:
    """Build payload for `public.students`. Returns (`payload`,`skip_reason`)."""
    raw_iid = _icu._pick(norm, "INSTID", "INST ID", "INSTITUTE_ID", "INSTITUTE ID", "GCCINSTCODE")
    if raw_iid.strip() and "".join(raw_iid.split()) != institute_id.strip().lstrip("\ufeff"):
        return None, f"row institute_id mismatch (expected {institute_id!r}, got {raw_iid!r})"

    uid_roll = (
        _icu._pick(norm, "USER_ID", "USER ID", "ROLL", "ROLL NO", "ROLL_NUMBER", "PRN", "ENROLLMENT", "ENROLMENT NO")
        or ""
    ).strip()

    form_serial = (
        _icu._pick(norm, "FORMSERIALNO", "FORM SERIAL NO", "FORM_SERIAL_NO", "FORM SERIAL", "FORM_NO", "FORM NO")
        or ""
    ).strip()

    sr_no_val = (
        _icu._pick(norm, "SR_NO", "SR NO", "SERIAL", "SERIAL NO", "S_NO", "S NO") or ""
    ).strip()
    if not sr_no_val and form_serial:
        sr_no_val = form_serial

    if not uid_roll and form_serial:
        uid_roll = form_serial

    name_explicit = (_icu._pick(norm, "NAME", "FULL NAME", "STUDENT NAME") or "").strip()
    fn = _icu._pick(norm, "FIRST_NAME", "FIRST NAME", "FIRST", "FNAME")
    mn = _icu._pick(norm, "MIDDLE_NAME", "MIDDLE NAME", "MIDDLE", "MNAME")
    ln = _icu._pick(norm, "LAST_NAME", "LAST NAME", "LAST", "LNAME", "SURNAME")
    assembled = _icu.admin_full_name(norm).strip()

    display_name = name_explicit or assembled
    if not display_name:
        return None, "missing name (NAME or FIRST/MIDDLE/LAST)"

    year = (_icu._pick(norm, "YEAR", "ACADEMIC YEAR", "ACADEMIC_YEAR") or "").strip() or None

    subjects_raw = _icu._pick(norm, "SUBJECTS", "SUBJECT LIST")
    subject_legacy_col = (_icu._pick(norm, "SUBJECT") or "").strip()
    declares_subjects = row_declares_subject_fields(norm)

    subjects_val = _subjects_values_from_norm(norm)

    if declares_subjects:
        cnt = len(subjects_val or [])
        if cnt < 1 and not allow_zero_subjects:
            return None, (
                f"need 1–{max_subjects} enrolled subjects "
                f"(got {cnt}); 0 / empty SUBJECT_* = not enrolled (or pass --allow-zero-subjects)"
            )
        if cnt > max_subjects:
            return None, (
                f"at most {max_subjects} enrolled subjects (got {cnt}): "
                f"{subjects_val!r}"
            )

    subject_single = subject_legacy_col or None
    if subjects_val and not subject_single:
        subject_single = subjects_val[0]

    lecture_timing_raw = (
        _icu._pick(norm, "LECTURE_TIMING", "LECTURE TIMING")
        or _icu._pick(norm, "BATCH_TIMING", "BATCH TIMING")
        or _icu._pick(norm, "TIMING")
        or ""
    ).strip()
    lecture_timing = lecture_timing_raw or None

    semester = (_icu._pick(norm, "SEMESTER") or "").strip() or None
    semester_name = (_icu._pick(norm, "SEMESTER_NAME", "SEM NAME") or "").strip() or None
    status = (_icu._pick(norm, "STATUS") or "").strip() or None
    role = (_icu._pick(norm, "ROLE") or "").strip() or None

    legacy_uid = (_icu._pick(norm, "UID") or "").strip() or None

    has_device_raw = (_icu._pick(norm, "HAS_DEVICE", "HAS DEVICE") or "").strip().lower()
    has_device = None
    if has_device_raw in ("true", "1", "yes", "y"):
        has_device = True
    elif has_device_raw in ("false", "0", "no", "n"):
        has_device = False

    payload: MutableMapping[str, Any] = {
        "institute_id": institute_id.strip().lstrip("\ufeff"),
        "name": display_name,
        "first_name": fn or None,
        "middle_name": mn or None,
        "last_name": ln or None,
        "user_id": uid_roll or None,
        "sr_no": sr_no_val or None,
        "year": year,
        "lecture_timing": lecture_timing,
        "subject": subject_single,
        "subjects": subjects_val,
        "semester": semester,
        "semester_name": semester_name,
        "status": status,
        "role": role,
        "uid": legacy_uid,
    }
    if has_device is not None:
        payload["has_device"] = has_device

    keys_protected_face = frozenset(
        {
            "face_embedding",
            "photo_url",
            "face_photo_url",
            "registration_photo_path",
        }
    )

    stripped = {k: v for k, v in payload.items() if k not in keys_protected_face and v is not None}

    if not status:
        stripped.pop("status", None)
    if not role:
        stripped.pop("role", None)

    pk_csv = (_icu._pick(norm, "ID", "STUDENT_ID", "STUDENT ID") or "").strip()
    if pk_csv:
        stripped["id"] = pk_csv

    return stripped, None


def _match_field_for_mode(mode: str) -> Tuple[str, str]:
    if mode == "user_id":
        return "user_id", "roll/user_id"
    if mode == "id":
        return "id", "id"
    if mode == "sr_no":
        return "sr_no", "sr_no"
    raise ValueError(mode)


def _extract_match(norm: Dict[str, str], mode: str, payload: Mapping[str, Any]) -> Tuple[Optional[str], Optional[str]]:
    if mode == "user_id":
        v = payload.get("user_id")
        if v and str(v).strip():
            return str(v).strip(), None
        v2 = (
            _icu._pick(norm, "USER_ID", "USER ID", "ROLL", "ROLL NO", "ROLL_NUMBER", "PRN", "ENROLLMENT", "ENROLMENT NO")
            or ""
        ).strip()
        if v2:
            return v2, None
        return None, "missing roll / user_id (required for match user_id)"

    if mode == "id":
        sid = (_icu._pick(norm, "ID", "STUDENT_ID", "STUDENT ID") or "").strip()
        if sid:
            return sid, None
        return None, "missing ID column"

    sr = payload.get("sr_no")
    if sr and str(sr).strip():
        return str(sr).strip(), None
    fs = (_icu._pick(norm, "FORMSERIALNO", "FORM SERIAL NO", "FORM_SERIAL_NO", "FORM SERIAL") or "").strip()
    if fs:
        return fs, None
    return None, "missing sr_no / formserialno"


@dataclass
class StudentCsvAgg:
    """Result of scanning a student CSV into per-institute match-key buckets."""

    aggregated: Dict[str, Dict[str, MutableMapping[str, Any]]]
    field_label: str
    rows_into_agg: int
    seen: int
    skipped_csv: int
    skipped_ignore_inst: int
    skipped_ignore_pair: int
    skipped_ignore_zero_subjects: int


def aggregate_student_rows_from_csv(
    path: Path,
    *,
    cli_institute_id: Optional[str],
    match: str,
    allow_zero_subjects: bool,
    max_subjects: int,
    ignore_institutes: set[str],
    ignore_pairs: set[tuple[str, str]],
    ignore_zero_subject_rows: bool,
    verbose_row_skips: bool = True,
) -> StudentCsvAgg:
    """
    Scan CSV → same payloads as REST import (`student_row_payload`). Used by REST `main()`
    and by `fast_load_students_pg_copy.py`.
    """

    aggregated: Dict[str, Dict[str, MutableMapping[str, Any]]] = {}
    seen = 0
    skipped_csv = 0
    skipped_ignore_inst = 0
    skipped_ignore_pair = 0
    skipped_ignore_zero_subjects = 0
    rows_into_agg = 0
    _, field_label = _match_field_for_mode(match)

    with path.open(newline="", encoding="utf-8-sig") as fh:
        for raw in csv.DictReader(fh):
            seen += 1
            norm = _icu._norm_row(raw)
            eff_iid, i_skip = resolve_institute_for_row(norm, cli_institute_id)
            if i_skip:
                skipped_csv += 1
                if verbose_row_skips:
                    print(f"row {seen}: skipped — {i_skip}", file=sys.stderr)
                continue
            assert eff_iid is not None

            if ignore_institutes and eff_iid in ignore_institutes:
                skipped_ignore_inst += 1
                continue
            if ignore_pairs:
                fs = (
                    _icu._pick(
                        norm,
                        "FORMSERIALNO",
                        "FORM SERIAL NO",
                        "FORM_SERIAL_NO",
                        "FORM SERIAL",
                        "FORM_NO",
                        "FORM NO",
                    )
                    or ""
                ).strip()
                if (eff_iid, fs) in ignore_pairs:
                    skipped_ignore_pair += 1
                    continue

            if ignore_zero_subject_rows and row_declares_subject_fields(norm):
                sv = _subjects_values_from_norm(norm)
                if len(sv or []) < 1:
                    skipped_ignore_zero_subjects += 1
                    continue

            pl, skip = student_row_payload(
                norm,
                institute_id=eff_iid,
                allow_zero_subjects=allow_zero_subjects,
                max_subjects=max(1, max_subjects),
            )
            if skip:
                skipped_csv += 1
                if verbose_row_skips:
                    print(f"row {seen}: skipped — {skip}", file=sys.stderr)
                continue
            assert pl is not None

            mv, mr = _extract_match(norm, match, pl)
            if mr:
                skipped_csv += 1
                if verbose_row_skips:
                    print(f"row {seen}: skipped — {mr}", file=sys.stderr)
                continue
            assert mv is not None

            bucket = aggregated.setdefault(eff_iid, {})
            bucket[mv] = pl
            rows_into_agg += 1

    return StudentCsvAgg(
        aggregated=aggregated,
        field_label=field_label,
        rows_into_agg=rows_into_agg,
        seen=seen,
        skipped_csv=skipped_csv,
        skipped_ignore_inst=skipped_ignore_inst,
        skipped_ignore_pair=skipped_ignore_pair,
        skipped_ignore_zero_subjects=skipped_ignore_zero_subjects,
    )


_SAFE_INSTITUTE_ID = re.compile(r"^[A-Za-z0-9._~-]+$")


def fetch_institute_ids_that_exist(base: str, key: str, institute_ids: List[str]) -> Tuple[set[str], List[str]]:
    """
    Returns (ids found in public.institutes, list of ids that fail token safety — never queried).
    """
    unique = sorted({str(i).strip().lstrip("\ufeff") for i in institute_ids if str(i).strip()})
    unsafe = [x for x in unique if not _SAFE_INSTITUTE_ID.fullmatch(x)]
    if unsafe:
        return set(), unsafe

    found: set[str] = set()
    for chunk in _icu.chunked(unique, 80):
        in_param = "(" + ",".join(chunk) + ")"
        url = (
            base.rstrip("/")
            + "/rest/v1/institutes?select=id&id=in."
            + quote(in_param, safe="(),-._~A-Za-z0-9")
        )
        hdr = {"apikey": key, "Authorization": "Bearer " + key, "Accept": "application/json"}
        req = urllib.request.Request(url, headers=hdr, method="GET")
        with _icu._url_open_supabase(req, timeout=120) as resp:
            chunk_rows = json.loads(resp.read().decode())
        if not isinstance(chunk_rows, list):
            raise RuntimeError(f"unexpected institutes GET response: {chunk_rows!r}")
        for row in chunk_rows:
            if isinstance(row, dict) and row.get("id") is not None:
                found.add(str(row["id"]).strip())
    return found, []


STUB_INST_TEMPLATE_HEADER = (
    "SR NO,FIRST,MIDDLE,LAST NAME,MOBILE NO,emailid,instname,isntadd,"
    "gccinstcode,dist,taluka,pincode,region"
).split(",")


def write_missing_institutes_stub_csv(dest: Path, gcc_ids: List[str]) -> None:
    """Minimal institutes CSV compatible with import_institutes_csv.py (GCCINSTCODE + INSTNAME)."""

    def _sort_key(g: str) -> tuple[int, str]:
        g = str(g).strip()
        try:
            return int(g), g
        except ValueError:
            return 10**18, g

    uniq = sorted(set(str(x).strip().lstrip("\ufeff") for x in gcc_ids if str(x).strip()), key=_sort_key)
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=STUB_INST_TEMPLATE_HEADER)
        w.writeheader()
        for i, gid in enumerate(uniq, start=1):
            w.writerow(
                {
                    "SR NO": str(i),
                    "FIRST": "",
                    "MIDDLE": "",
                    "LAST NAME": "",
                    "MOBILE NO": "",
                    "emailid": "",
                    "instname": f"GCC institute {gid} (replace with official name)",
                    "isntadd": "",
                    "gccinstcode": gid,
                    "dist": "",
                    "taluka": "",
                    "pincode": "",
                    "region": "",
                }
            )


def fetch_match_index(base: str, key: str, institute_id: str, field: str) -> Dict[str, str]:
    rows: List[Dict[str, Any]] = []
    page = 1000
    offset = 0
    while True:
        sel = "id" if field == "id" else f"id,{field}"
        url = (
            base.rstrip("/")
            + f"/rest/v1/students?institute_id=eq.{quote(institute_id)}"
            + f"&select={quote(sel)}"
            + f"&limit={page}&offset={offset}"
        )
        hdr = {"apikey": key, "Authorization": "Bearer " + key, "Accept": "application/json"}
        req = urllib.request.Request(url, headers=hdr, method="GET")
        with _icu._url_open_supabase(req, timeout=120) as resp:
            chunk = json.loads(resp.read().decode())
        if not chunk:
            break
        if not isinstance(chunk, list):
            raise RuntimeError(f"unexpected students GET response: {chunk!r}")
        rows.extend(chunk)
        if len(chunk) < page:
            break
        offset += page

    idx: Dict[str, str] = {}
    seen_dup: Dict[str, int] = {}
    for row in rows:
        sid_db = row.get("id")
        raw = row.get(field)
        if sid_db is None or raw is None:
            continue
        k = str(raw).strip()
        if not k:
            continue
        seen_dup[k] = seen_dup.get(k, 0) + 1
        idx[k] = str(sid_db)
    dups = [k for k, n in seen_dup.items() if n > 1]
    if dups:
        preview = ", ".join(dups[:15])
        more = len(dups) - 15 if len(dups) > 15 else 0
        print(
            f"Warning: duplicate {field} values in institute {institute_id} (last row wins locally): "
            f"{preview}{' … +' + str(more) + ' more' if more > 0 else ''}",
            file=sys.stderr,
        )
    return idx


def _post_students_batch(base: str, key: str, rows: List[Dict[str, Any]]) -> None:
    endpoint = base.rstrip("/") + "/rest/v1/students"
    batch_keys = sorted({k for r in rows for k, v in r.items() if v is not None})
    clean = [{k: r.get(k) for k in batch_keys} for r in rows]
    _icu.post_json(
        endpoint,
        key,
        clean,
        extra_headers={"Prefer": "return=minimal"},
    )


def _patch_student(base: str, key: str, student_pk: str, body: Dict[str, Any]) -> None:
    qpk = quote(str(student_pk).strip(), safe="")
    endpoint = base.rstrip("/") + "/rest/v1/students?id=eq." + qpk
    patch_body = dict(body)
    patch_body.pop("institute_id", None)
    patch_body.pop("id", None)
    out = {k: v for k, v in patch_body.items() if v is not None}
    _icu.post_json(endpoint, key, out, method="PATCH", extra_headers={"Prefer": "return=minimal"})


def _plan_one_institute(
    base_url: str,
    key: str,
    institute_id: str,
    rows_by_key: Dict[str, MutableMapping[str, Any]],
    *,
    db_field: str,
    field_label: str,
    match_mode: str,
    batch_size: int,
    dry_run: bool,
) -> Tuple[int, int, int]:
    idx = fetch_match_index(base_url, key, institute_id, db_field)
    to_patch: List[Tuple[str, MutableMapping[str, Any]]] = []
    to_insert: List[MutableMapping[str, Any]] = []
    skipped_guard = 0

    for mk, pl in rows_by_key.items():
        if mk in idx:
            to_patch.append((idx[mk], pl))
            continue

        if not str(pl.get("user_id") or "").strip():
            skipped_guard += 1
            print(
                f"[{institute_id}] skip INSERT (match key={mk!r}): need USER_ID/ROLL or FORMSERIALNO for new rows",
                file=sys.stderr,
            )
            continue

        if match_mode == "id":
            pid = str(pl.get("id") or "").strip()
            if not pid or pid != mk:
                skipped_guard += 1
                print(
                    f"[{institute_id}] skip INSERT: --match id requires ID/STUDENT_ID equal to key {mk!r}",
                    file=sys.stderr,
                )
                continue

        csv_pk = str(pl.get("id") or "").strip()
        if csv_pk and csv_pk in idx.values():
            skipped_guard += 1
            print(
                f"[{institute_id}] skip INSERT: id={csv_pk} already exists — use PATCH via --match",
                file=sys.stderr,
            )
            continue

        to_insert.append(pl)

    print(
        f"[{institute_id}] PATCH {len(to_patch)}, INSERT {len(to_insert)}, insert guard skips {skipped_guard}",
        flush=True,
    )

    if dry_run:
        return len(to_patch), len(to_insert), skipped_guard

    for bi, batch in enumerate(_icu.chunked(to_insert, batch_size), start=1):
        if not batch:
            continue
        print(f"[{institute_id}] INSERT batch {bi} ({len(batch)})…", flush=True)
        _post_students_batch(base_url, key, batch)
        time.sleep(0.08)

    for i, (row_pk, pl) in enumerate(to_patch, start=1):
        if i % 50 == 0 or i == 1:
            print(f"[{institute_id}] PATCH {i}/{len(to_patch)} …", flush=True)
        _patch_student(base_url, key, row_pk, pl)
        time.sleep(0.02)

    return len(to_patch), len(to_insert), skipped_guard


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Insert or PATCH students via Supabase REST (service role). Multi-institute when CSV has instid."
    )
    ap.add_argument("csv_path")
    ap.add_argument(
        "--institute-id",
        default=None,
        help="If set, force this institute_id; CSV instid (if present) must match.",
    )
    ap.add_argument(
        "--match",
        choices=("user_id", "id", "sr_no"),
        default="user_id",
        help="Find existing rows: user_id (roll), id, or sr_no / formserialno.",
    )
    ap.add_argument("--batch-size", type=int, default=80)
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Load CSV + DB index only; report counts (no POST/PATCH).",
    )
    ap.add_argument(
        "--allow-zero-subjects",
        action="store_true",
        help="Allow rows whose SUBJECT_* are all blank/0 (insert with empty subjects; re-run same import later with subjects filled to PATCH).",
    )
    ap.add_argument(
        "--max-subjects",
        type=int,
        default=5,
        metavar="N",
        help="Max distinct subject codes per row (default 5).",
    )
    ap.add_argument("--env-file", metavar="PATH", default=None)
    ap.add_argument("--no-dotenv", action="store_true")
    ap.add_argument("--direct-http", action="store_true")
    ap.add_argument(
        "--skip-institute-check",
        action="store_true",
        help="Do not verify CSV institute id(s) exist in public.institutes before POST/PATCH (not recommended).",
    )
    ap.add_argument(
        "--write-missing-institutes-stub-csv",
        metavar="PATH",
        default=None,
        help="If the DB is missing institute id(s) from the CSV, write this stub institutes CSV then exit.",
    )
    ap.add_argument(
        "--ignore-institutes-file",
        metavar="PATH",
        default=None,
        help="Skip every row whose institute id is listed in this text file (# lines ignored). CSV stays unchanged.",
    )
    ap.add_argument(
        "--ignore-instid-form-tsv",
        metavar="PATH",
        default=None,
        help="Skip rows matching (instid, formserialno) pairs from this tab-separated file.",
    )
    ap.add_argument(
        "--ignore-zero-subject-rows",
        action="store_true",
        help="Silently skip rows that declare SUBJECT_* / SUBJECTS but have no enrolled codes (0/empty).",
    )
    args = ap.parse_args()

    _icu.set_import_http_options(force_direct=args.direct_http)
    _icu.load_dotenv_merged(args.env_file, skip=args.no_dotenv)
    base_url, key = _icu.supabase_rest_credentials()

    cli_inst = None
    if args.institute_id is not None:
        cli_inst = str(args.institute_id).strip().lstrip("\ufeff")
        if not cli_inst:
            print("--institute-id is empty.", file=sys.stderr)
            sys.exit(1)

    db_field, _ = _match_field_for_mode(args.match)

    path = Path(args.csv_path).expanduser()
    if not path.is_file():
        print(f"File not found: {path}", file=sys.stderr)
        sys.exit(1)

    ignore_institutes: set[str] = set()
    if args.ignore_institutes_file:
        ipath = Path(args.ignore_institutes_file).expanduser()
        if ipath.is_file():
            ignore_institutes = _csv_row_ignore.load_inst_ids(ipath)
        else:
            print(f"WARN: ignore institutes file missing: {ipath}", file=sys.stderr)

    ignore_pairs: set[tuple[str, str]] = set()
    if args.ignore_instid_form_tsv:
        tpath = Path(args.ignore_instid_form_tsv).expanduser()
        if tpath.is_file():
            ignore_pairs = _csv_row_ignore.load_exclude_pairs(tpath)
        else:
            print(f"WARN: ignore pairs TSV missing: {tpath}", file=sys.stderr)

    agg = aggregate_student_rows_from_csv(
        path,
        cli_institute_id=cli_inst,
        match=args.match,
        allow_zero_subjects=args.allow_zero_subjects,
        max_subjects=args.max_subjects,
        ignore_institutes=ignore_institutes,
        ignore_pairs=ignore_pairs,
        ignore_zero_subject_rows=args.ignore_zero_subject_rows,
        verbose_row_skips=True,
    )
    aggregated = agg.aggregated

    if not aggregated:
        print("No valid student rows.")
        sys.exit(1)

    merged_total = agg.rows_into_agg - sum(len(v) for v in aggregated.values())
    if merged_total > 0:
        print(
            f"Merged {merged_total} duplicate CSV row(s) on same {agg.field_label} "
            "(within each institute); last wins."
        )

    if agg.skipped_ignore_inst or agg.skipped_ignore_pair or agg.skipped_ignore_zero_subjects:
        parts = []
        if agg.skipped_ignore_inst:
            parts.append(f"{agg.skipped_ignore_inst} row(s) via --ignore-institutes-file")
        if agg.skipped_ignore_pair:
            parts.append(f"{agg.skipped_ignore_pair} row(s) via --ignore-instid-form-tsv")
        if agg.skipped_ignore_zero_subjects:
            parts.append(f"{agg.skipped_ignore_zero_subjects} row(s) via --ignore-zero-subject-rows")
        print("Ignored (master CSV unchanged): " + "; ".join(parts) + ".", file=sys.stderr)

    print(f"Using SUPABASE REST base: {base_url}", file=sys.stderr)
    _icu.warn_dns_preflight(base_url)

    institute_ids = sorted(aggregated.keys(), key=lambda x: str(x))
    n_inst = len(institute_ids)

    if not args.skip_institute_check:
        found, unsafe = fetch_institute_ids_that_exist(base_url, key, institute_ids)
        if unsafe:
            print(
                "Institute id(s) from CSV use characters not allowed in PostgREST `in` filter. "
                "Fix instid values or use only [A-Za-z0-9._~-]:",
                file=sys.stderr,
            )
            for u in unsafe[:40]:
                print(f"  {u!r}", file=sys.stderr)
            sys.exit(3)
        missing = [iid for iid in institute_ids if iid not in found]
        if missing:
            print(
                "No rows in public.institutes for these id(s) (import institutes first so id matches CSV instid):",
                file=sys.stderr,
            )
            for m in missing[:80]:
                print(f"  {m}", file=sys.stderr)
            if len(missing) > 80:
                print(f"  … and {len(missing) - 80} more", file=sys.stderr)
            stub_arg = (args.write_missing_institutes_stub_csv or "").strip()
            if stub_arg:
                sp = Path(stub_arg).expanduser()
                write_missing_institutes_stub_csv(sp, missing)
                print(
                    f"Wrote {len(missing)} stub institute row(s) to {sp} "
                    "(edit instname/address, then: python3 scripts/import_institutes_csv.py <that file>).",
                    file=sys.stderr,
                )
            print("Run: python3 scripts/import_institutes_csv.py your_institutes.csv", file=sys.stderr)
            print("Or use --skip-institute-check to force (may cause FK errors on insert).", file=sys.stderr)
            sys.exit(3)
        print(f"Verified {n_inst} institute id(s) exist in public.institutes.", flush=True, file=sys.stderr)
    tot_patch = tot_insert = tot_guard = 0
    for ni, iid in enumerate(institute_ids, start=1):
        print(
            f"[{ni}/{n_inst}] institute {iid}: fetching existing students ({agg.field_label}) …",
            flush=True,
            file=sys.stderr,
        )
        p, ins, g = _plan_one_institute(
            base_url,
            key,
            iid,
            aggregated[iid],
            db_field=db_field,
            field_label=agg.field_label,
            match_mode=args.match,
            batch_size=args.batch_size,
            dry_run=args.dry_run,
        )
        tot_patch += p
        tot_insert += ins
        tot_guard += g

    print(
        f"Total across institutes: PATCH {tot_patch}, INSERT {tot_insert}, "
        f"CSV skips {agg.skipped_csv}, insert guard skips {tot_guard}.",
        flush=True,
    )
    if args.dry_run:
        print("Dry run — done (no writes).")
    else:
        print("Done.")


if __name__ == "__main__":
    main()
