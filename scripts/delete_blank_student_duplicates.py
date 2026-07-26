#!/usr/bin/env python3
"""
Delete blank placeholder student rows when a full row exists for the same institute + sr_no.

This is meant to clean old seed/import placeholder rows such as:
  institute_id=11061, sr_no=1, name=NULL, user_id=NULL
when the real CSV row has already been imported as:
  institute_id=11061, sr_no=1, name='...', user_id='1'

Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (.env okay).
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List
from urllib.parse import quote

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import import_institutes_csv as _icu  # noqa: E402


def _chunks(items: List[str], size: int) -> Iterable[List[str]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def _is_blank_placeholder(row: Dict[str, Any]) -> bool:
    name = str(row.get("name") or "").strip()
    user_id = str(row.get("user_id") or "").strip()
    return not name and not user_id


def _is_full_row(row: Dict[str, Any]) -> bool:
    name = str(row.get("name") or "").strip()
    user_id = str(row.get("user_id") or "").strip()
    return bool(name or user_id)


def fetch_all_students(base_url: str, key: str, page_size: int) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    page_size = min(page_size, 1000)
    offset = 0
    while True:
        endpoint = (
            base_url.rstrip("/")
            + "/rest/v1/students"
            + "?select=id,institute_id,sr_no,user_id,name"
            + "&order=id.asc"
            + f"&limit={page_size}&offset={offset}"
        )
        req = urllib.request.Request(
            endpoint,
            headers={"apikey": key, "Authorization": "Bearer " + key, "Accept": "application/json"},
            method="GET",
        )
        with _icu._url_open_supabase(req, timeout=180) as resp:
            chunk = json.loads(resp.read().decode())
        if not chunk:
            break
        if not isinstance(chunk, list):
            raise RuntimeError(f"Unexpected students response: {chunk!r}")
        rows.extend(chunk)
        if len(chunk) < page_size:
            break
        offset += len(chunk)
        print(f"Fetched {len(rows)} student rows...", file=sys.stderr, flush=True)
    return rows


def delete_rows(base_url: str, key: str, ids: List[str], batch_size: int, dry_run: bool) -> None:
    for batch in _chunks(ids, batch_size):
        if dry_run:
            continue
        in_param = "(" + ",".join(quote(x, safe="") for x in batch) + ")"
        endpoint = base_url.rstrip("/") + "/rest/v1/students?id=in." + in_param
        _icu.post_json(endpoint, key, None, method="DELETE", extra_headers={"Prefer": "return=minimal"})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--env-file", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--page-size", type=int, default=5000)
    ap.add_argument("--delete-batch-size", type=int, default=80)
    args = ap.parse_args()

    _icu.load_dotenv_merged(args.env_file, skip=False)
    base_url, key = _icu.supabase_rest_credentials()

    rows = fetch_all_students(base_url, key, args.page_size)
    groups: Dict[tuple[str, str], List[Dict[str, Any]]] = defaultdict(list)
    for row in rows:
        institute_id = str(row.get("institute_id") or "").strip()
        sr_no = str(row.get("sr_no") or "").strip()
        if institute_id and sr_no:
            groups[(institute_id, sr_no)].append(row)

    delete_ids: List[str] = []
    for grouped in groups.values():
        if len(grouped) < 2:
            continue
        if not any(_is_full_row(row) for row in grouped):
            continue
        delete_ids.extend(str(row["id"]) for row in grouped if row.get("id") and _is_blank_placeholder(row))

    delete_ids = sorted(set(delete_ids))
    print(
        f"Scanned {len(rows)} rows; blank duplicate placeholders to delete: {len(delete_ids)}.",
        flush=True,
    )
    delete_rows(base_url, key, delete_ids, args.delete_batch_size, args.dry_run)
    print("Dry run complete." if args.dry_run else "Cleanup complete.")


if __name__ == "__main__":
    main()
