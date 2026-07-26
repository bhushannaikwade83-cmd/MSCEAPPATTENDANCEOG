#!/usr/bin/env python3
"""
Bulk upsert **institute** rows (`public.institutes`) + optional admin invites.
Does **not** load students — bulk student roster per institute is
`scripts/import_students_csv.py` (CSV `instid` → students.institute_id).

Service role required (never put in the Flutter app).

  python3 scripts/import_institutes_csv.py your.csv --with-admin-invites

`--with-admin-invites`: also writes pending `admin_invites` (principal name, mobile, email from the sheet).
Those rows are required for **Institute search → Complete signup → email OTP** in the app.
Importing institutes **without** this flag leaves `admin_invites` empty ⇒ admin details do not appear (not a bug).

To see how many institutes lack pending invites on your project:
`python3 scripts/report_institutes_missing_pending_admin_invites.py -t scripts/missing_invites_report.tsv`.

If you see DNS errors only from Python, add `--direct-http` (forces no proxy handlers).
If HTTPS fails mid-import with TLS errors (e.g. `SSLV3_ALERT_BAD_RECORD_MAC`), retries are automatic; prefer stable Wi‑Fi, disable VPN/ad‑blocking HTTPS inspection, or use `--batch-size 40`.

HTTPS uses IPv4-first TCP to `*.supabase.co` (matches app behavior on networks with broken IPv6).

Credentials (first non-empty wins):

  Process environment: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (already exported in your shell).
  If the key is missing, the script loads from .env in this order: --env-file PATH, then repo root
  .env, then ./.env — only for variables not already set.

  In .env use the same names, or SERVICE_ROLE_KEY / SUPABASE_SECRET_KEY as alternate names for
  the service role secret. Do not use SUPABASE_ANON_KEY for bulk import.

Excel / CSV columns (exact names OK; spelling & case insensitive except below):

  SR NO,FIRST,MIDDLE,LAST NAME,MOBILE NO,emailid,instname,isntadd,gccinstcode,dist,taluka,pincode,region

  isntadd … typo for institute address → institutes.address

  Sr.No ... when SR NO is filled, stored in institutes.location prefix (omit with --no-sheet-sr-in-location).

All institutes are imported as active (`is_active` true). No inactive column. COM CODE is not imported from Excel.

Save as "CSV UTF-8". Case and extra spaces in headers are still tolerated.

Alternative without Python: Supabase SQL + psql COPY.
"""

from __future__ import annotations

import argparse
import csv
import http.client
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import quote, urlparse

_import_http_always_direct = False


def set_import_http_options(*, force_direct: bool) -> None:
    global _import_http_always_direct
    _import_http_always_direct = force_direct


class IPv4HTTPSConnection(http.client.HTTPSConnection):
    """Skip broken IPv6 paths: TCP to first IPv4 address, TLS SNI = real hostname."""

    def connect(self) -> None:
        if self._tunnel_host:
            return super().connect()
        try:
            addrs = socket.getaddrinfo(
                self.host, self.port, socket.AF_INET, socket.SOCK_STREAM
            )
        except socket.gaierror:
            return super().connect()
        if not addrs:
            return super().connect()
        last: Optional[OSError] = None
        sock: Optional[socket.socket] = None
        try:
            for _fa, socktype, proto, _cn, sockaddr in addrs:
                try:
                    s = socket.socket(socket.AF_INET, socktype, proto)
                    s.settimeout(self.timeout)
                    if self.source_address is not None:
                        s.bind(self.source_address)
                    s.connect(sockaddr)
                    sock = s
                    last = None
                    break
                except OSError as e:
                    last = e
            if sock is None:
                if last:
                    raise last
                return super().connect()
            self.sock = self._context.wrap_socket(sock, server_hostname=self.host)
        except Exception:
            if sock:
                sock.close()
            raise


class IPv4HTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req: urllib.request.Request) -> http.client.HTTPResponse:
        return self.do_open(
            IPv4HTTPSConnection,
            req,
            context=self._context,
        )


def _supabase_opener_director(*, no_proxy: bool) -> urllib.request.OpenerDirector:
    ph = urllib.request.ProxyHandler({} if no_proxy else urllib.request.getproxies())
    return urllib.request.build_opener(ph, IPv4HTTPSHandler(context=ssl.create_default_context()))


_TRANSIENT_NET = (
    http.client.RemoteDisconnected,
    ConnectionResetError,
    BrokenPipeError,
    http.client.IncompleteRead,
    ssl.SSLError,
)
"""TLS read failures (e.g. SSLV3_ALERT_BAD_RECORD_MAC) often indicate VPN/antivirus/MITM mangling HTTPS — we retry."""

_MAX_OPEN_ATTEMPTS = 5


def _url_open_supabase(req: urllib.request.Request, *, timeout: float):
    proxies = urllib.request.getproxies()
    px_snap = "; ".join(f"{k}={v}" for k, v in sorted(proxies.items())) if proxies else "(none)"
    configs: List[bool] = [True] if _import_http_always_direct else [False, True]

    last_err: Optional[Exception] = None
    for no_proxy in configs:
        opener = _supabase_opener_director(no_proxy=no_proxy)
        for attempt in range(_MAX_OPEN_ATTEMPTS):
            try:
                return opener.open(req, timeout=timeout)
            except urllib.error.URLError as e:
                last_err = e
                errno = getattr(e.reason, "errno", None) if getattr(e, "reason", None) else None
                if errno == 8 and not no_proxy and len(configs) > 1:
                    print(
                        f"Warning: DNS lookup failed ({e!r}); getproxies()={px_snap}. Retrying without proxy handlers.",
                        file=sys.stderr,
                    )
                    break
                if isinstance(getattr(e, "reason", None), _TRANSIENT_NET) and attempt + 1 < _MAX_OPEN_ATTEMPTS:
                    wait = min(16.0, 0.4 * (2**attempt))
                    print(
                        f"Transient HTTPS wrapped error ({type(e.reason).__name__}: {e.reason!r}); "
                        f"retry {attempt + 2}/{_MAX_OPEN_ATTEMPTS} after {wait:.1f}s…",
                        file=sys.stderr,
                    )
                    time.sleep(wait)
                    continue
                raise
            except _TRANSIENT_NET as e:
                last_err = e
                if attempt + 1 < _MAX_OPEN_ATTEMPTS:
                    wait = min(16.0, 0.4 * (2**attempt))
                    kind = (
                        "TLS/MAC or truncated response"
                        if isinstance(e, (ssl.SSLError, http.client.IncompleteRead))
                        else "disconnect"
                    )
                    print(
                        f"Transient HTTPS {kind} ({type(e).__name__}: {e!r}); "
                        f"retry {attempt + 2}/{_MAX_OPEN_ATTEMPTS} after {wait:.1f}s… "
                        f"(VPN off / smaller --batch-size if this repeats)",
                        file=sys.stderr,
                    )
                    time.sleep(wait)
                    continue
                raise
    if last_err is not None:
        raise last_err
    raise RuntimeError("unexpected opener loop exit")


def warn_dns_preflight(rest_base_url: str) -> None:
    parsed = urlparse(rest_base_url)
    host = parsed.hostname or ""
    if not host:
        return
    try:
        socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    except socket.gaierror as ge:
        scheme = parsed.scheme or "https"
        print(
            "DNS preflight: Python socket.getaddrinfo failed for "
            f"{host!r}: {ge}. If the import fails, try `--direct-http`, "
            "turn off VPN, check AdGuard/firewall DNS, or run:",
            file=sys.stderr,
        )
        print(f"  curl -sI '{scheme}://{host}/rest/v1/'", file=sys.stderr)


# ── Normalise Excel headers ("Institute ID", "INSTITUTE ID", etc.) ─────────────

_WS = re.compile(r"\s+")


def _norm_header(h: Optional[str]) -> str:
    if h is None:
        return ""
    return _WS.sub(" ", str(h).strip()).upper()


def _norm_row(raw: Dict[str, Any]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for k, v in raw.items():
        nk = _norm_header(k)
        if not nk:
            continue
        if v is None:
            out[nk] = ""
        elif isinstance(v, float) and v == int(v):
            out[nk] = str(int(v))
        else:
            out[nk] = str(v).strip()
    return out


def _pick(norm: Dict[str, str], *candidates: str) -> str:
    for cand in candidates:
        key = _norm_header(cand)
        if key in norm and norm[key]:
            return norm[key].strip()
    return ""


def _digits_only_phone(s: str) -> str:
    return re.sub(r"\D", "", s or "")


def _looks_like_email(s: str) -> bool:
    return bool(s) and ("@" in s) and ("." in s.split("@")[-1])


def _strip_kv_quotes(val: str) -> str:
    v = val.strip()
    if len(v) >= 2 and v[0] in '"\'' and v[0] == v[-1]:
        return v[1:-1]
    return v


# Replace empty shell placeholders with .env (setdefault alone cannot do that).
_DOTENV_FILL_IF_BLANK = frozenset(
    {"SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY"}
)


def _merge_env_kv(key: str, val: str) -> None:
    k = key.strip()
    if not k:
        return
    v = _strip_kv_quotes((val or "").strip())
    if not v:
        return
    if k in _DOTENV_FILL_IF_BLANK:
        cur = (os.environ.get(k) or "").strip()
        if not cur:
            os.environ[k] = v
        return
    os.environ.setdefault(k, v)


def _load_dotenv_file(path: Path) -> None:
    try:
        with open(path, encoding="utf-8-sig") as f:
            for raw in f:
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                if line.lower().startswith("export "):
                    line = line[7:].strip()
                if "=" not in line:
                    continue
                k, _, val = line.partition("=")
                k = k.strip()
                if not k:
                    continue
                _merge_env_kv(k, val)
    except OSError as e:
        print(f"Warning: could not read {path}: {e}", file=sys.stderr)


def normalize_supabase_project_url(raw: str) -> str:
    """Yield https://projectref.supabase.co for REST (fixes quotes, missing scheme, stray newlines)."""

    u = (raw or "").strip()
    while len(u) >= 2 and u[0] in '"\'' and u[0] == u[-1]:
        u = u[1:-1].strip()
    u = "".join(u.splitlines()).strip()
    if not u:
        print("SUPABASE_URL is empty after cleanup.", file=sys.stderr)
        sys.exit(1)
    if "://" not in u:
        u = "https://" + u.lstrip("/")
    parsed = urlparse(u)
    if parsed.scheme not in ("https", "http"):
        print(
            f"SUPABASE_URL must start with https:// — got scheme {parsed.scheme!r}. Check your .env (no stray spaces).",
            file=sys.stderr,
        )
        sys.exit(1)
    host = (parsed.netloc or "").strip()
    # If someone pasted host-only into a malformed URL parser edge case:
    if not host and parsed.path:
        maybe = parsed.path.split("/")[0].strip()
        if "." in maybe:
            host = maybe
            parsed = urlparse(f"{parsed.scheme}://{host}")
    host = host.split("@")[-1].strip().rstrip(":")
    if not host:
        preview = repr(u[:120])
        print(
            f"SUPABASE_URL has no hostname. Line should look exactly like:\n"
            f'  SUPABASE_URL=https://xxxx.supabase.co\n'
            f"Current value parses as: {preview}",
            file=sys.stderr,
        )
        sys.exit(1)
    return f"{parsed.scheme}://{host}".rstrip("/")


def load_dotenv_merged(cli_env_file: Optional[str], *, skip: bool = False) -> None:
    """Fill os.environ gaps from dotenv-style files (does not replace existing exports)."""

    if skip:
        return
    paths_ordered: List[Path] = []
    if cli_env_file:
        paths_ordered.append(Path(cli_env_file).expanduser().resolve())
    repo_env = Path(__file__).resolve().parent.parent / ".env"
    paths_ordered.append(repo_env.resolve())
    paths_ordered.append((Path.cwd() / ".env").resolve())

    seen: set[str] = set()
    for p in paths_ordered:
        key = str(p)
        if key in seen:
            continue
        seen.add(key)
        if p.is_file():
            _load_dotenv_file(p)
            print(f"Loaded missing env keys from {p}", file=sys.stderr)


def supabase_rest_credentials() -> tuple[str, str]:
    """(url, service_role_secret). Prefer process env over .env-injected."""

    url_raw = os.environ.get("SUPABASE_URL", "").strip()
    url = normalize_supabase_project_url(url_raw)

    candidates = (
        "SUPABASE_SERVICE_ROLE_KEY",
        "SERVICE_ROLE_KEY",
        "SUPABASE_SECRET_KEY",
    )
    for name in candidates:
        secret = os.environ.get(name, "").strip()
        if secret:
            return url, secret

    print(
        "Missing bulk-import secret: set SUPABASE_SERVICE_ROLE_KEY in your environment or .env\n"
        "  (Dashboard → Settings → API → service_role — not the anon key).",
        file=sys.stderr,
    )
    sys.exit(1)


def institute_from_row(
    norm: Dict[str, str],
    *,
    prepend_sheet_sr: bool,
) -> Tuple[Optional[Dict[str, Any]], Optional[str], Optional[str]]:
    """Returns (payload, skip_reason, soft_warning). DB id/code always from GCCINSTCODE."""

    gcc_raw = _pick(norm, "GCCINSTCODE", "GCC INST CODE", "GCCINSTITUTECODE", "GCC INST")
    if not (gcc_raw or "").strip():
        gcc_raw = _pick(norm, "INSTITUTE CODE")
    gcc = "".join((gcc_raw or "").split()).strip().lstrip("\ufeff")

    if not gcc:
        return None, "GCCINSTCODE is required — it becomes institutes.id / institute_code in the app.", None

    if not gcc.isdigit():
        return None, f"GCCINSTCODE must be digits only (official institute key): {gcc_raw!r}", None

    iid = gcc
    institute_code = gcc

    inst_name = _pick(
        norm,
        "INSTNAME",
        "INST NAME",
        "NAME",
        "INSTITUTE NAME",
        "INST_NAME",
    )
    if not inst_name:
        return None, f"missing INSTNAME / institute name (GCC={iid})", None

    sheet_sr = _pick(
        norm,
        "SR NO",
        "SRNO",
        "SR_NO",
        "S.NO",
        "S NO",
        "SERIAL NO",
        "SERIAL",
        "LIST NO",
        "LIST NO.",
    )

    soft: Optional[str] = None
    if gcc_raw.strip() != gcc:
        soft = f"GCCINSTCODE trimmed for id={iid}"

    addr = _pick(
        norm,
        "ISNTADD",
        "ISNT ADD",
        "INST ADD",
        "INSTADD",
        "INST_ADDR",
        "INST ADDRESS",
        "INSTITUTE ADDRESS",
        "ADDRESS",
    )

    district = _pick(norm, "DIST", "DISTRICT")

    taluka = _pick(norm, "TALUKA", "TALUK", "TALUKKA")

    pincode = _pick(norm, "PINCODE", "PIN CODE", "PIN")

    mobile = _pick(norm, "MOBILE NO", "MOBILE", "MOBILE_NO", "PHONE", "MOBILENO")

    region = _pick(norm, "REGION")

    loc_parts: List[str] = []
    if prepend_sheet_sr and sheet_sr.strip():
        loc_parts.append(f"Sr.No {sheet_sr.strip()}")
    if region:
        loc_parts.append(region.strip())
    location = "; ".join(loc_parts) if loc_parts else None

    payload: Dict[str, Any] = {
        "id": iid,
        "institute_code": "".join(institute_code.split()),
        "name": inst_name.strip(),
        "location": location,
        "address": addr or None,
        "city": None,
        "district": district or None,
        "taluka": taluka or None,
        "state": None,
        "country": "India",
        "mobile_no": mobile or None,
        "pincode": pincode or None,
        "is_active": True,
    }

    return payload, None, soft


def admin_full_name(norm: Dict[str, str]) -> str:
    first = _pick(norm, "FIRST NAME", "FIRST", "FIRSTNAME", "FNAME")
    middle = _pick(norm, "MIDDLE NAME", "MIDDLE", "MIDDLENAME", "MNAME")
    last = _pick(norm, "LAST NAME", "LAST", "LASTNAME", "LNAME", "SURNAME")
    parts = [p for p in [first, middle, last] if p and p.strip()]
    return " ".join(parts)


def invite_from_row(
    institute_id: str, norm: Dict[str, str]
) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    fn = admin_full_name(norm)
    raw_email = _pick(
        norm,
        "EMAILID",
        "EMAIL ID",
        "EMAIL",
        "EMAIL_ID",
        "E MAIL",
    )
    email = raw_email.strip().lower()
    mob_raw = _pick(norm, "MOBILE NO", "MOBILE", "PHONE", "MOBILENO")
    phone = _digits_only_phone(mob_raw)

    if not fn or len(fn) < 2:
        return None, "admin full name empty (FIRST/MIDDLE/LAST)"
    if not phone or len(phone) < 8:
        return None, "admin phone missing or too short"
    if not _looks_like_email(email):
        return None, f"admin email invalid: {email!r}"

    return {
        "institute_id": institute_id,
        "full_name": fn,
        "phone": phone,
        "email": email,
        "claimed": False,
    }, None


def post_json(
    endpoint: str,
    key: str,
    body: Any,
    method: str = "POST",
    extra_headers: Optional[Dict[str, str]] = None,
) -> None:
    h: Dict[str, str] = {
        "apikey": key,
        "Authorization": "Bearer " + key,
    }
    if extra_headers:
        h.update(extra_headers)
    data: Optional[bytes]
    if body is None:
        data = None
    else:
        h["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(endpoint, data=data, headers=h, method=method)
    try:
        with _url_open_supabase(req, timeout=180) as resp:
            if resp.status not in (200, 201, 204):
                raise RuntimeError(f"HTTP {resp.status}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {err_body}") from e
    except http.client.RemoteDisconnected as e:
        raise RuntimeError(
            "Supabase closed the connection without an HTTP status (often a bad TLS or IPv6 path). "
            "This script retries over IPv4; if it persists, disable VPN briefly or set DNS to 1.1.1.1 / 8.8.8.8."
        ) from e
    except urllib.error.URLError as e:
        parsed = urlparse(endpoint)
        host = parsed.netloc or "(unknown)"
        hint = ""
        errno = getattr(e.reason, "errno", None) if e.reason else None
        if errno == 8 or (e.reason is not None and "nodename" in str(e.reason).lower()):
            hint = (
                f"\n  DNS/host lookup failed for {host!r} from Python (urllib already retried direct/no-proxy)."
                f"\n  On Mac: unplug VPN briefly, check AdGuard/firewall blocking *.supabase.co, or run:"
                f"\n    curl -sI '{parsed.scheme or 'https'}://{host}/'"
                f"\n  If shells work but Python fails, run with:  python3 scripts/import_institutes_csv.py ... --direct-http"
                f"\n  Confirm SUPABASE_URL matches Dashboard → Settings → API → Project URL."
                f"\n  If router DNS returns NXDOMAIN but `dig @1.1.1.1 …` resolves, switch Mac/System DNS to 1.1.1.1 or 8.8.8.8."
            )
        raise RuntimeError(f"Network error contacting {endpoint[:96]}...: {e!r}.{hint}") from e


def post_institutes_batch(base: str, key: str, rows: List[Dict[str, Any]]) -> None:
    endpoint = base.rstrip("/") + "/rest/v1/institutes?on_conflict=id"
    clean = []
    for r in rows:
        clean.append({k: v for k, v in r.items() if v is not None})
    post_json(
        endpoint,
        key,
        clean,
        extra_headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
    )


def delete_pending_invites(base: str, key: str, institute_ids: List[str]) -> None:
    """Remove pending invites before import (`claimed=false` OR `claimed IS NULL`)."""

    if not institute_ids:
        return
    root = base.rstrip("/") + "/rest/v1/admin_invites"

    def _in_clause_text_ids(ids: List[str]) -> str:
        """PostgREST `in.(...)` for TEXT institute ids (digits must be quoted strings, not BIGINT)."""

        inner = "(" + ",".join(json.dumps(str(uid).strip().lstrip("\ufeff")) for uid in ids) + ")"
        return quote(inner, safe="(),")

    for chunk in chunked(institute_ids, 80):
        enc_body = _in_clause_text_ids(chunk)
        for claimed_q in ("claimed=eq.false", "claimed=is.null"):
            endpoint = root + "?institute_id=in." + enc_body + "&" + claimed_q
            post_json(endpoint, key, None, method="DELETE", extra_headers={"Prefer": "return=minimal"})


def chunked(xs: List[Any], n: int) -> List[List[Any]]:
    return [xs[i : i + n] for i in range(0, len(xs), n)]


def dedupe_dict_rows_by_column(
    rows: List[Dict[str, Any]],
    *,
    column: str,
) -> Tuple[List[Dict[str, Any]], int]:
    """
    Collapse duplicates on `column`; later rows overwrite earlier ones.
    Postgres `ON CONFLICT DO UPDATE` forbids proposing the same unique key twice in one INSERT.
    """
    merged: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        merged[str(row[column])] = row
    uniq = list(merged.values())
    return uniq, len(rows) - len(uniq)


def post_invites_batch(base: str, key: str, rows: List[Dict[str, Any]]) -> None:
    merged: Dict[str, Dict[str, Any]] = {}
    for r in rows:
        merged[str(r["institute_id"]).strip().lstrip("\ufeff")] = r
    clean = list(merged.values())
    if len(clean) < len(rows):
        print(
            f"Warning: trimmed {len(rows) - len(clean)} duplicate institute_id row(s) inside one POST batch.",
            file=sys.stderr,
        )
    endpoint = base.rstrip("/") + "/rest/v1/admin_invites"
    post_json(
        endpoint,
        key,
        clean,
        extra_headers={"Prefer": "return=minimal"},
    )


def main() -> None:
    ap = argparse.ArgumentParser(description="Upsert institutes (and optionally admin invites) from CSV.")
    ap.add_argument("csv_path")
    ap.add_argument(
        "--msce-excel",
        action="store_true",
        help="Optional; MSCE-style columns are auto-detected from headers (no change if omitted).",
    )
    ap.add_argument(
        "--with-admin-invites",
        action="store_true",
        help="Also write admin_invites (delete pending invite per institute, then insert)",
    )
    ap.add_argument("--batch-size", type=int, default=100)
    ap.add_argument(
        "--env-file",
        metavar="PATH",
        default=None,
        help="Optional extra .env to merge (only fills unset vars; after shell env, before repo/.env then ./.env).",
    )
    ap.add_argument(
        "--no-dotenv",
        action="store_true",
        help="Do not read .env files; use only variables already exported in your shell.",
    )
    ap.add_argument(
        "--direct-http",
        action="store_true",
        help="Ignore HTTP_PROXY/HTTPS_PROXY for all Supabase REST calls (if Python fails DNS but browsers work).",
    )
    ap.add_argument(
        "--no-sheet-sr-in-location",
        dest="prepend_sheet_sr",
        action="store_false",
        help="Do not add Sr.No from SR NO column into institutes.location (default adds it when SR NO present).",
    )
    ap.set_defaults(prepend_sheet_sr=True)
    args = ap.parse_args()

    set_import_http_options(force_direct=args.direct_http)

    load_dotenv_merged(args.env_file, skip=args.no_dotenv)
    base, key = supabase_rest_credentials()
    print(f"Using SUPABASE REST base: {base}", file=sys.stderr)
    warn_dns_preflight(base)

    institutes: List[Dict[str, Any]] = []
    invites: List[Dict[str, Any]] = []
    invited_ids: List[str] = []

    skipped = 0
    seen = 0
    warns: List[str] = []

    with open(args.csv_path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            print("CSV has no header row.", file=sys.stderr)
            sys.exit(1)

        for raw in reader:
            seen += 1
            norm = _norm_row(raw)
            payload, skip_reason, soft = institute_from_row(
                norm,
                prepend_sheet_sr=args.prepend_sheet_sr,
            )
            if skip_reason:
                skipped += 1
                print(f"row {seen}: {skip_reason}", file=sys.stderr)
                continue
            if soft:
                warns.append(soft)
            assert payload is not None
            institute_id = str(payload["id"])
            institutes.append(payload)

            if args.with_admin_invites:
                inv, inv_err = invite_from_row(institute_id, norm)
                if inv is None:
                    print(f"row {seen} id={institute_id}: invite skipped — {inv_err}", file=sys.stderr)
                else:
                    invites.append(inv)
                    invited_ids.append(institute_id)

    for w in warns[:50]:
        print(w, file=sys.stderr)
    if len(warns) > 50:
        print(f"... and {len(warns)-50} more warnings", file=sys.stderr)

    if not institutes:
        print("No valid institute rows.")
        sys.exit(1)

    inst_read = len(institutes)
    institutes, dup_inst = dedupe_dict_rows_by_column(institutes, column="id")
    if dup_inst:
        print(
            f"Merged {dup_inst} duplicate spreadsheet row(s) with the same GCCINSTCODE "
            "(institutes.id): later rows win (Postgres cannot upsert duplicate keys in one request).",
            file=sys.stderr,
        )

    if args.with_admin_invites and invites:
        invites, dup_inv = dedupe_dict_rows_by_column(invites, column="institute_id")
        invited_ids = [str(r["institute_id"]) for r in invites]
        if dup_inv:
            print(
                f"Merged {dup_inv} duplicate admin invite row(s) for the same institute_id "
                "(later rows win).",
                file=sys.stderr,
            )

    batches = chunked(institutes, args.batch_size)
    print(
        f"Institutes: {len(institutes)} distinct rows ({inst_read} from sheet) in "
        f"{len(batches)} batches (read {seen}, skipped {skipped}).",
    )

    for i, batch in enumerate(batches, start=1):
        print(f"Institutes batch {i}/{len(batches)}...", flush=True)
        post_institutes_batch(base, key, batch)
        time.sleep(0.12)

    if args.with_admin_invites and invites:
        # One delete per institute that gets a new invite, then inserts in batches.
        uniq_ids = list(dict.fromkeys(invited_ids))
        print(f"Deleting pending admin_invites for {len(uniq_ids)} institutes...")
        delete_pending_invites(base, key, uniq_ids)
        for i, ib in enumerate(chunked(invites, args.batch_size), start=1):
            print(f"Admin invites batch {i}...", flush=True)
            post_invites_batch(base, key, ib)
            time.sleep(0.12)
        print(f"Posted {len(invites)} admin_invites.")
    elif args.with_admin_invites:
        print("No admin invites to post (check FIRST/MIDDLE/LAST, EMAILID, MOBILE NO).")

    print("Done.")


if __name__ == "__main__":
    main()
