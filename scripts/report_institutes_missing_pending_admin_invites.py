#!/usr/bin/env python3
"""
List institutes that have NO pending admin_invites row (claimed = false).

The mobile app institute search → OTP signup reads admin_invites for that institute;
without a pending invite, admin name/email do not appear.

Uses SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (.env).

After review, create invites by re-importing matching rows with --with-admin-invites:

  python3 scripts/report_institutes_missing_pending_admin_invites.py -o scripts/need_invites_instids.txt
  python3 scripts/extract_missing_institutes_from_all_csv.py \\
    --missing-ids scripts/need_invites_instids.txt \\
    -o scripts/institutes_need_invites_only.csv
  python3 scripts/import_institutes_csv.py scripts/institutes_need_invites_only.csv --with-admin-invites

If principal email/phone/name in the CSV is invalid, invite_from_row skips that row — fix CSV then re-run.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

import import_institutes_csv as _icu  # noqa: E402


def _fetch_json_url(url: str, key: str) -> list:
    import urllib.request

    hdr = {"apikey": key, "Authorization": "Bearer " + key, "Accept": "application/json"}
    req = urllib.request.Request(url, headers=hdr, method="GET")
    with _icu._url_open_supabase(req, timeout=120) as resp:
        raw = resp.read().decode()
    data = json.loads(raw)
    if not isinstance(data, list):
        raise RuntimeError(f"unexpected GET response (expected list): {data!r}")
    return data


def fetch_all_institutes(base: str, key: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    page = 1000
    offset = 0
    root = base.rstrip("/") + "/rest/v1/institutes?select=id,name"
    while True:
        url = root + f"&limit={page}&offset={offset}&order=id.asc"
        rows = _fetch_json_url(url, key)
        for r in rows:
            if isinstance(r, dict):
                iid = str(r.get("id") or "").strip()
                nm = str(r.get("name") or "").strip()
                if iid:
                    out.append((iid, nm))
        if len(rows) < page:
            break
        offset += page
    return out


def fetch_pending_invite_institute_ids(base: str, key: str) -> set[str]:
    ids: set[str] = set()
    page = 1000
    offset = 0
    root = base.rstrip("/") + "/rest/v1/admin_invites?select=institute_id&claimed=eq.false"
    while True:
        url = root + f"&limit={page}&offset={offset}"
        rows = _fetch_json_url(url, key)
        for r in rows:
            if isinstance(r, dict):
                iid = str(r.get("institute_id") or "").strip().lstrip("\ufeff")
                if iid:
                    ids.add(iid)
        if len(rows) < page:
            break
        offset += page
    return ids


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--env-file", metavar="PATH", default=None)
    ap.add_argument("--no-dotenv", action="store_true")
    ap.add_argument("--direct-http", action="store_true")
    ap.add_argument(
        "-o",
        "--write-id-list",
        metavar="PATH",
        help="One institute id per line (for extract_missing_institutes_from_all_csv.py --missing-ids)",
    )
    ap.add_argument(
        "-t",
        "--write-tsv",
        metavar="PATH",
        help="Write id\\tname TSV",
    )
    args = ap.parse_args()

    _icu.set_import_http_options(force_direct=args.direct_http)
    _icu.load_dotenv_merged(args.env_file, skip=args.no_dotenv)
    base_url, key = _icu.supabase_rest_credentials()

    institutes = fetch_all_institutes(base_url, key)
    pending_inst = fetch_pending_invite_institute_ids(base_url, key)

    missing = [(iid, name) for iid, name in institutes if iid not in pending_inst]

    print(f"Institutes in DB: {len(institutes)}", file=sys.stderr)
    print(f"With pending invite (claimed=false): {len(pending_inst)}", file=sys.stderr)
    print(f"Missing pending invite (no admin OTP signup row): {len(missing)}", file=sys.stderr)
    print(file=sys.stderr)

    def sort_key(pair: tuple[str, str]):
        iid = pair[0]
        try:
            return int(iid), pair
        except ValueError:
            return 10**18, pair

    missing.sort(key=sort_key)

    if args.write_id_list:
        p = Path(args.write_id_list).expanduser()
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("\n".join(x[0] for x in missing) + ("\n" if missing else ""), encoding="utf-8")
        print(f"Wrote institute id list ({len(missing)}) → {p}", file=sys.stderr)

    if args.write_tsv:
        p = Path(args.write_tsv).expanduser()
        p.parent.mkdir(parents=True, exist_ok=True)
        with p.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f, delimiter="\t", lineterminator="\n")
            w.writerow(["institute_id", "institute_name"])
            w.writerows(missing)
        print(f"Wrote TSV ({len(missing)}) → {p}", file=sys.stderr)

    for iid, name in missing:
        disp = name if name else "(no name)"
        print(f"{iid}\t{disp}")


if __name__ == "__main__":
    main()
