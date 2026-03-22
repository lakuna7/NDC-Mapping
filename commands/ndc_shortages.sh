#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NDC SHORTAGE MATRIX v1
# ============================================================
# Companion to ndc_source_matrix.sh.
# Adds shortage status flag to NDC11 rows.
#
# Usage:
#   INPUT="0006"          bash ndc_shortages.sh
#   INPUT="0006-0277"     bash ndc_shortages.sh
#   INPUT="0006-0277-02"  bash ndc_shortages.sh
# ============================================================

INPUT="${INPUT:-0006}"
OPENFDA_API_KEY="${OPENFDA_API_KEY:-}"
MAX_WORKERS="${MAX_WORKERS:-8}"
CACHE_TTL_HOURS="${CACHE_TTL_HOURS:-24}"

export INPUT OPENFDA_API_KEY MAX_WORKERS CACHE_TTL_HOURS

exec python3 - <<'ENDOFPYTHON'
import csv
import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

T0 = time.time()

INPUT = os.environ.get("INPUT", "0006").strip()
OPENFDA_API_KEY = os.environ.get("OPENFDA_API_KEY", "").strip()
MAX_WORKERS = max(1, int(os.environ.get("MAX_WORKERS", "8")))
CACHE_TTL_HOURS = max(0, int(os.environ.get("CACHE_TTL_HOURS", "24")))

# ============================================================
# SAFE STRING / STATUS CONSTANTS
# ============================================================

def _s(x):
    if x is None:
        return ""
    return str(x)

def _ss(x):
    return _s(x).strip()

S_HIT = "hit"
S_NO_DATA = "no_data"
S_BAD_FILTER = "bad_filter"
S_QUERY_ERROR = "query_error"
S_NOT_QUERIED = "not_queried"

def digits_only(x):
    return re.sub(r"\D", "", _s(x))

def safe_filename(x):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", _s(x))

def upper_clean(x):
    return re.sub(r"\s+", " ", _ss(x)).upper()

INPUT_SAFE = safe_filename(INPUT) if INPUT else "EMPTY"
_outdir_env = os.environ.get("OUTDIR", "").strip()
if _outdir_env:
    OUTDIR = Path(_outdir_env)
else:
    OUTDIR = Path.home() / ("ndc_shortages_" + INPUT_SAFE)
CACHE_DIR = OUTDIR / "cache"
OUTDIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

def log(msg):
    print("[ndc-short] " + _s(msg), file=sys.stderr, flush=True)

# ============================================================
# HTTP WITH CACHE (same pattern as other scripts)
# ============================================================

def _cache_path(url):
    h = hashlib.sha256(url.encode("utf-8")).hexdigest()
    return CACHE_DIR / (h + ".json")

def http_get_json(url, timeout=60, retries=2, backoff=1.2):
    cp = _cache_path(url)
    if CACHE_TTL_HOURS > 0 and cp.exists():
        age_h = (time.time() - cp.stat().st_mtime) / 3600.0
        if age_h <= CACHE_TTL_HOURS:
            try:
                return json.loads(cp.read_text(encoding="utf-8"))
            except Exception:
                pass
    last_err = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": "NDCShortages/1.0",
                "Accept": "application/json, text/plain, */*",
            })
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
                try:
                    data = json.loads(raw)
                except Exception:
                    data = {"_raw_text": raw}
                try:
                    cp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                except Exception:
                    pass
                return data
        except Exception as exc:
            last_err = exc
            if attempt < retries:
                time.sleep(backoff * (attempt + 1))
    return {"_error": repr(last_err), "_url": url}

def is_err(data):
    return isinstance(data, dict) and "_error" in data

# ============================================================
# NDC NORMALIZATION (same as ndc_source_matrix.sh)
# ============================================================

def normalize_ndc11(package_ndc):
    s = _ss(package_ndc)
    d = digits_only(s)
    if len(d) == 11:
        return d
    parts = s.split("-")
    if len(parts) != 3:
        # Try FDA 10-digit formats: 4-4-2, 5-3-2, 5-4-1
        # Zero-pad to 5-4-2
        if len(d) == 10:
            # Ambiguous without dashes; try 5-4-1 -> 5-4-01
            return d[0:5] + d[5:9] + "0" + d[9:10]
        return None
    a = digits_only(parts[0])
    b = digits_only(parts[1])
    c = digits_only(parts[2])
    if len(a) == 4 and len(b) == 4 and len(c) == 2:
        return "0" + a + b + c
    if len(a) == 5 and len(b) == 3 and len(c) == 2:
        return a + "0" + b + c
    if len(a) == 5 and len(b) == 4 and len(c) == 1:
        return a + b + "0" + c
    if len(a) == 5 and len(b) == 4 and len(c) == 2:
        return a + b + c
    return None

def normalize_ndc9(product_ndc):
    s = _ss(product_ndc)
    parts = s.split("-")
    if len(parts) == 2:
        a = digits_only(parts[0])
        b = digits_only(parts[1])
        if len(a) in (4, 5) and len(b) in (3, 4):
            return a.zfill(5) + b.zfill(4)
    d = digits_only(s)
    if len(d) == 9:
        return d
    if len(d) == 8:
        return d[:5].zfill(5) + d[5:].zfill(4)
    return None

def display_ndc11(ndc11):
    d = digits_only(ndc11)
    if len(d) != 11:
        return _s(ndc11)
    return d[0:5] + "-" + d[5:9] + "-" + d[9:11]

def product_ndc_variants(ndc9):
    d = digits_only(ndc9)
    if len(d) != 9:
        return []
    a = d[0:5]
    b = d[5:9]
    vs = set()
    vs.add(a + "-" + b)
    if a.startswith("0"):
        vs.add(a[1:] + "-" + b)
    if b.startswith("0"):
        vs.add(a + "-" + b[1:])
        if a.startswith("0"):
            vs.add(a[1:] + "-" + b[1:])
    try:
        b_int = str(int(b))
        vs.add(a + "-" + b_int)
        if a.startswith("0"):
            vs.add(a[1:] + "-" + b_int)
    except ValueError:
        pass
    return sorted(v for v in vs if "-" in v and len(v.replace("-", "")) >= 7)

def labeler_terms(input_d):
    d = digits_only(input_d)
    out = []
    if len(d) == 4:
        out = [d]
    elif len(d) == 5:
        out = [d]
        if d.startswith("0"):
            out.append(d[1:])
    elif len(d) == 6:
        l5 = d[0:5]
        out = [l5]
        if l5.startswith("0"):
            out.append(l5[1:])
        out.append(d[0:4])
    else:
        out = [d]
    return [x for x in dict.fromkeys(out) if x and len(x) >= 4]

def detect_kind(raw):
    s = _ss(raw)
    d = digits_only(s)
    if s.count("-") == 2 or len(d) == 11:
        return "package"
    if s.count("-") == 1 or len(d) in (8, 9):
        return "product"
    if len(d) in (4, 5, 6):
        return "company"
    sys.exit("Cannot parse INPUT='" + raw + "'.")

INPUT_KIND = detect_kind(INPUT)
INPUT_DIGITS = digits_only(INPUT)

# ============================================================
# openFDA HELPERS (same as ndc_source_matrix.sh)
# ============================================================

def openfda_url(endpoint, search=None, limit=100, skip=0):
    qs = {}
    if OPENFDA_API_KEY:
        qs["api_key"] = OPENFDA_API_KEY
    if search:
        qs["search"] = search
    qs["limit"] = str(limit)
    qs["skip"] = str(skip)
    return "https://api.fda.gov/" + endpoint + ".json?" + urllib.parse.urlencode(qs)

def openfda_paginate(endpoint, search, page_limit=100, max_pages=20):
    rows = []
    skip = 0
    for _ in range(max_pages):
        url = openfda_url(endpoint, search=search, limit=page_limit, skip=skip)
        data = http_get_json(url, timeout=90)
        if is_err(data):
            break
        batch = data.get("results", []) if isinstance(data, dict) else []
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < page_limit:
            break
        skip += page_limit
        time.sleep(0.15)
    return rows

# ============================================================
# PHASE 1: RESOLVE NDC FAMILY (identical to ndc_source_matrix.sh)
# ============================================================

log("Input: " + INPUT + " (" + INPUT_KIND + ")")

def resolve_family():
    if INPUT_KIND == "package":
        ndc11 = INPUT_DIGITS if len(INPUT_DIGITS) == 11 else normalize_ndc11(INPUT)
        if not ndc11:
            sys.exit("Cannot normalize package input.")
        ndc9 = ndc11[0:9]
        variants = product_ndc_variants(ndc9)
        q = " OR ".join(['product_ndc:"' + v + '"' for v in variants])
        rows = openfda_paginate("drug/ndc", q, max_pages=10)
        out = []
        for r in rows:
            for pkg in (r.get("packaging") or []):
                if normalize_ndc11(_s(pkg.get("package_ndc", ""))) == ndc11:
                    out.append(r)
                    break
        return out
    elif INPUT_KIND == "product":
        ndc9 = normalize_ndc9(INPUT)
        if not ndc9:
            sys.exit("Cannot normalize product input.")
        variants = product_ndc_variants(ndc9)
        q = " OR ".join(['product_ndc:"' + v + '"' for v in variants])
        rows = openfda_paginate("drug/ndc", q, max_pages=15)
        return [r for r in rows if normalize_ndc9(_s(r.get("product_ndc", ""))) == ndc9]
    else:
        terms = labeler_terms(INPUT_DIGITS)
        all_rows = []
        for t in terms:
            all_rows.extend(openfda_paginate("drug/ndc", "product_ndc:" + t + "*", max_pages=30))
        seen = set()
        deduped = []
        for r in all_rows:
            key = _s(r.get("product_ndc", "")) + "|" + json.dumps(r.get("packaging", []), sort_keys=True, default=str)
            if key not in seen:
                seen.add(key)
                deduped.append(r)
        prefix5 = INPUT_DIGITS.zfill(5) if len(INPUT_DIGITS) <= 5 else INPUT_DIGITS[0:5]
        prefix6 = INPUT_DIGITS if len(INPUT_DIGITS) == 6 else None
        out = []
        for r in deduped:
            for pkg in (r.get("packaging") or []):
                n11 = normalize_ndc11(_s(pkg.get("package_ndc", "")))
                if not n11:
                    continue
                ok = False
                if prefix6 and n11.startswith(prefix6):
                    ok = True
                elif n11[0:5] == prefix5:
                    ok = True
                if ok and r not in out:
                    out.append(r)
                    break
        return out

family_rows = resolve_family()
if not family_rows:
    sys.exit("No rows resolved for INPUT='" + INPUT + "'.")

# Build NDC11 set
target_ndc11 = None
if INPUT_KIND == "package":
    target_ndc11 = INPUT_DIGITS if len(INPUT_DIGITS) == 11 else normalize_ndc11(INPUT)

ndc11_set = set()
ndc11_identity = {}
for r in family_rows:
    brand = _ss(r.get("brand_name"))
    generic = _ss(r.get("generic_name"))
    product_ndc = _ss(r.get("product_ndc"))
    for pkg in (r.get("packaging") or []):
        pkg_ndc_raw = _s((pkg or {}).get("package_ndc", ""))
        ndc11 = normalize_ndc11(pkg_ndc_raw)
        if not ndc11:
            continue
        if target_ndc11 and ndc11 != target_ndc11:
            continue
        ndc11_set.add(ndc11)
        if ndc11 not in ndc11_identity:
            ndc11_identity[ndc11] = {
                "ndc11": ndc11,
                "ndc11_display": display_ndc11(ndc11),
                "brand_name": brand,
                "generic_name": generic,
                "product_ndc": product_ndc,
            }

all_ndc11 = sorted(ndc11_set)
log("Scope: " + str(len(all_ndc11)) + " NDC11s")

# ============================================================
# PHASE 2: FETCH FDA DRUG SHORTAGES (full extraction)
# ============================================================
# Source: openFDA Drug Shortages API
# Endpoint: https://api.fda.gov/drug/shortages.json
# Grain: one record per drug shortage presentation
# Native identifiers: package_ndc (top-level, FDA 10-digit format)
#                     openfda.package_ndc (array, FDA 10-digit)
#                     openfda.product_ndc (array)
# NDC-11 join: normalize FDA 10-digit -> 11-digit via zero-padding
# ============================================================

log("Fetching FDA Drug Shortages (full dataset)...")

shortage_records = []
shortage_fetch_status = S_NOT_QUERIED

# Paginate through all shortage records (dataset is small: ~1500-2000 total)
skip = 0
page_limit = 100
max_pages = 30
for page in range(max_pages):
    url = openfda_url("drug/shortages", limit=page_limit, skip=skip)
    data = http_get_json(url, timeout=90)
    if is_err(data):
        if page == 0:
            shortage_fetch_status = S_QUERY_ERROR
            log("Shortage API error: " + _s(data.get("_error", "")))
        break
    batch = data.get("results", []) if isinstance(data, dict) else []
    if not batch:
        break
    shortage_records.extend(batch)
    if len(batch) < page_limit:
        break
    skip += page_limit
    time.sleep(0.15)

if shortage_records:
    shortage_fetch_status = S_HIT

log("Shortages fetched: " + str(len(shortage_records)) + " records")

# ============================================================
# PHASE 3: BUILD SHORTAGE NDC11 INDEX
# ============================================================
# For each shortage record, extract all NDC-11 codes it maps to.
# Build: shortage_by_ndc11[ndc11] = list of shortage dicts
# ============================================================

def normalize_fda_ndc_to_11(ndc_str):
    """Normalize FDA variable-format NDC to 11-digit.
    FDA uses 4-4-2, 5-3-2, 5-4-1 formats (10 digits with dashes).
    Target: 5-4-2 (11 digits, no dashes)."""
    s = _ss(ndc_str)
    if not s:
        return None
    # Try standard 3-segment normalization first
    n11 = normalize_ndc11(s)
    if n11:
        return n11
    # If no dashes, try known 10-digit patterns
    d = digits_only(s)
    if len(d) == 10:
        # Ambiguous without dashes; try all 3 interpretations
        # 4-4-2: 0+4+4+2 = 11
        candidates = [
            "0" + d[0:4] + d[4:8] + d[8:10],  # 4-4-2
            d[0:5] + "0" + d[5:8] + d[8:10],   # 5-3-2
            d[0:5] + d[5:9] + "0" + d[9:10],   # 5-4-1
        ]
        return candidates  # Return all; caller must match
    return None

shortage_by_ndc11 = {}

for rec in shortage_records:
    rec_ndcs = set()

    # 1. Top-level package_ndc (single string)
    top_ndc = rec.get("package_ndc")
    if top_ndc:
        n = normalize_fda_ndc_to_11(_s(top_ndc))
        if isinstance(n, str):
            rec_ndcs.add(n)
        elif isinstance(n, list):
            rec_ndcs.update(n)

    # 2. openfda.package_ndc (array)
    ofd = rec.get("openfda", {})
    if isinstance(ofd, dict):
        for pndc in (ofd.get("package_ndc") or []):
            n = normalize_fda_ndc_to_11(_s(pndc))
            if isinstance(n, str):
                rec_ndcs.add(n)
            elif isinstance(n, list):
                rec_ndcs.update(n)
        # 3. openfda.product_ndc (for ndc9-level matching)
        for pndc in (ofd.get("product_ndc") or []):
            ndc9 = normalize_ndc9(_s(pndc))
            if ndc9:
                # Match any ndc11 in our set that starts with this ndc9
                for n in all_ndc11:
                    if n[0:9] == ndc9:
                        rec_ndcs.add(n)

    # Index by ndc11
    for n in rec_ndcs:
        shortage_by_ndc11.setdefault(n, []).append(rec)

log("Shortages indexed: " + str(len(shortage_by_ndc11)) + " unique NDC11s with shortages")

# ============================================================
# PHASE 4: BUILD OUTPUT
# ============================================================

OUT_COLS = [
    "ndc11", "ndc11_display", "brand_name", "generic_name", "product_ndc",
    "shortage_flag", "shortage_status", "shortage_count",
    "shortage_availability", "shortage_reason",
    "shortage_initial_date", "shortage_update_date",
    "shortage_generic_name", "shortage_company",
    "shortage_source_status",
]

output_rows = []

for ndc11 in all_ndc11:
    info = ndc11_identity.get(ndc11, {})
    recs = shortage_by_ndc11.get(ndc11, [])

    row = {
        "ndc11": ndc11,
        "ndc11_display": info.get("ndc11_display", display_ndc11(ndc11)),
        "brand_name": info.get("brand_name", ""),
        "generic_name": info.get("generic_name", ""),
        "product_ndc": info.get("product_ndc", ""),
        "shortage_flag": "",
        "shortage_status": "",
        "shortage_count": "",
        "shortage_availability": "",
        "shortage_reason": "",
        "shortage_initial_date": "",
        "shortage_update_date": "",
        "shortage_generic_name": "",
        "shortage_company": "",
        "shortage_source_status": shortage_fetch_status,
    }

    if shortage_fetch_status == S_QUERY_ERROR:
        row["shortage_flag"] = "unknown"
        row["shortage_source_status"] = S_QUERY_ERROR
    elif not recs:
        row["shortage_flag"] = "N"
        row["shortage_source_status"] = S_NO_DATA
    else:
        # Filter for current shortages (status != "Resolved")
        current = [r for r in recs if _ss(r.get("status", "")).upper() != "RESOLVED"]
        if not current:
            current = recs  # Show resolved if no current

        row["shortage_flag"] = "Y" if any(
            _ss(r.get("status", "")).upper() != "RESOLVED" for r in recs
        ) else "N_RESOLVED"
        row["shortage_count"] = str(len(recs))

        # Use most recent record
        recs_sorted = sorted(recs, key=lambda r: _s(r.get("update_date", r.get("initial_posting_date", ""))), reverse=True)
        latest = recs_sorted[0]

        row["shortage_status"] = _ss(latest.get("status"))
        row["shortage_availability"] = _ss(latest.get("availability"))
        row["shortage_reason"] = _ss(latest.get("shortage_reason"))
        row["shortage_initial_date"] = _ss(latest.get("initial_posting_date"))
        row["shortage_update_date"] = _ss(latest.get("update_date"))
        row["shortage_generic_name"] = _ss(latest.get("generic_name"))
        row["shortage_company"] = _ss(latest.get("company_name"))
        row["shortage_source_status"] = S_HIT

    output_rows.append(row)

# ============================================================
# PHASE 5: WRITE OUTPUT
# ============================================================

csv_path = OUTDIR / "ndc11_shortages.csv"
with open(str(csv_path), "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=OUT_COLS, extrasaction="ignore")
    w.writeheader()
    for row in output_rows:
        w.writerow({c: row.get(c, "") for c in OUT_COLS})

elapsed = time.time() - T0

run_log = {
    "input": INPUT,
    "input_kind": INPUT_KIND,
    "ndc11_count": len(all_ndc11),
    "shortage_records_fetched": len(shortage_records),
    "ndc11s_with_shortages": len(shortage_by_ndc11),
    "ndc11s_matched": sum(1 for r in output_rows if r["shortage_flag"] == "Y"),
    "source": {
        "name": "FDA Drug Shortages",
        "endpoint": "https://api.fda.gov/drug/shortages.json",
        "classification": "package-native",
        "grain": "one record per drug shortage presentation",
        "identifier_basis": "package_ndc (FDA 10-digit, normalized to 11)",
        "allowed_joins": ["NDC-11 to openFDA NDC", "NDC-11 to NADAC", "NDC-11 to SDUD"],
        "forbidden_joins": ["Do not project shortage status to brand-level or state-level without explicit aggregation label"],
    },
    "runtime_seconds": round(elapsed, 1),
    "output_file": str(csv_path),
}

(OUTDIR / "run_log.json").write_text(json.dumps(run_log, indent=2, ensure_ascii=False), encoding="utf-8")

# Console summary
print("")
print("=" * 70)
print("NDC SHORTAGE MATRIX v1 -- COMPLETE")
print("=" * 70)
print("  INPUT              : " + INPUT)
print("  NDC11s             : " + str(len(all_ndc11)))
print("  SHORTAGES FETCHED  : " + str(len(shortage_records)))
print("  NDC11s IN SHORTAGE : " + str(sum(1 for r in output_rows if r["shortage_flag"] == "Y")))
print("  NDC11s RESOLVED    : " + str(sum(1 for r in output_rows if r["shortage_flag"] == "N_RESOLVED")))
print("  NDC11s CLEAR       : " + str(sum(1 for r in output_rows if r["shortage_flag"] == "N")))
print("  RUNTIME            : " + str(run_log["runtime_seconds"]) + "s")
print("")
print("FILES:")
print("  " + str(csv_path))
print("  " + str(OUTDIR / "run_log.json"))
print("")

# Preview
print("PREVIEW:")
print("  {:<14} {:<20} {:<10} {:<12} {}".format("NDC11", "Brand", "Flag", "Status", "Availability"))
print("  " + "-" * 72)
for r in output_rows[0:15]:
    print("  {:<14} {:<20} {:<10} {:<12} {}".format(
        r["ndc11"], r["brand_name"][0:18], r["shortage_flag"],
        r["shortage_status"][0:10], r["shortage_availability"][0:20]))
print("")
ENDOFPYTHON
