#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NDC GEO MATRIX v1
# ============================================================
# State-level analysis companion to ndc_source_matrix.sh.
# One state table per unique normalized NDC11.
#
# Usage:
#   INPUT="0006"          bash ndc_geo_matrix.sh
#   INPUT="0006-0277"     bash ndc_geo_matrix.sh
#   INPUT="0006-0277-02"  bash ndc_geo_matrix.sh
# ============================================================

INPUT="${INPUT:-0006}"
OPENFDA_API_KEY="${OPENFDA_API_KEY:-}"
MAX_WORKERS="${MAX_WORKERS:-8}"
CACHE_TTL_HOURS="${CACHE_TTL_HOURS:-24}"

export INPUT OPENFDA_API_KEY MAX_WORKERS CACHE_TTL_HOURS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
export PROJECT_ROOT
export BASH_SOURCE_DIR="$SCRIPT_DIR"

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
# SAFE STRING / STATUS / STATE CONSTANTS
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

US_STATES = [
    ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"),
    ("CA", "California"), ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"),
    ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"),
    ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"),
    ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"),
    ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
    ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"),
    ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"),
    ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"),
    ("OK", "Oklahoma"), ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"),
    ("SC", "South Carolina"), ("SD", "South Dakota"), ("TN", "Tennessee"), ("TX", "Texas"),
    ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"), ("WA", "Washington"),
    ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
]
STATE_CODES = [s[0] for s in US_STATES]
STATE_NAMES = {s[0]: s[1] for s in US_STATES}

# ============================================================
# UTILITIES
# ============================================================

def digits_only(x):
    return re.sub(r"\D", "", _s(x))

def upper_clean(x):
    return re.sub(r"\s+", " ", _ss(x)).upper()

def safe_filename(x):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", _s(x))

INPUT_SAFE = safe_filename(INPUT) if INPUT else "EMPTY"
_root_env = os.environ.get("PROJECT_ROOT", "").strip()
if _root_env:
    PROJECT_ROOT = Path(_root_env)
else:
    _script_dir = Path(os.environ.get("BASH_SOURCE_DIR", "")).resolve() if os.environ.get("BASH_SOURCE_DIR") else Path.cwd()
    if _script_dir.name == "commands":
        PROJECT_ROOT = _script_dir.parent
    else:
        PROJECT_ROOT = _script_dir
TABLES_DIR = PROJECT_ROOT / "exports" / "tables" / ("geo_matrix_" + INPUT_SAFE)
CSV_DIR = TABLES_DIR / "state_tables"
LOGS_DIR = PROJECT_ROOT / "exports" / "logs"
DEBUG_DIR = PROJECT_ROOT / "exports" / "debug"
CACHE_DIR = PROJECT_ROOT / "local-data" / ("cache_geo_matrix_" + INPUT_SAFE)
for d in [TABLES_DIR, CSV_DIR, LOGS_DIR, DEBUG_DIR, CACHE_DIR]:
    d.mkdir(parents=True, exist_ok=True)
OUTDIR = TABLES_DIR

def log(msg):
    print("[ndc-geo] " + _s(msg), file=sys.stderr, flush=True)

# ============================================================
# HTTP WITH CACHE (identical pattern to ndc_source_matrix.sh)
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
                "User-Agent": "NDCGeoMatrix/1.0",
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

def fetch_many(urls, timeout=60, retries=2):
    result = {}
    if not urls:
        return result
    unique = list(dict.fromkeys(urls))
    workers = min(MAX_WORKERS, len(unique))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futs = {pool.submit(http_get_json, u, timeout, retries): u for u in unique}
        for fut in as_completed(futs):
            u = futs[fut]
            try:
                result[u] = fut.result()
            except Exception as exc:
                result[u] = {"_error": repr(exc), "_url": u}
    return result

# ============================================================
# NDC NORMALIZATION (same as ndc_source_matrix.sh)
# ============================================================

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

def normalize_ndc11(package_ndc):
    s = _ss(package_ndc)
    d = digits_only(s)
    if len(d) == 11:
        return d
    parts = s.split("-")
    if len(parts) != 3:
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
# PHASE 1: RESOLVE NDC FAMILY (same logic as ndc_source_matrix.sh)
# ============================================================

log("Input: " + INPUT + " (" + INPUT_KIND + ")")

resolution = {"input": INPUT, "input_digits": INPUT_DIGITS, "input_kind": INPUT_KIND}

def resolve_family():
    if INPUT_KIND == "package":
        ndc11 = INPUT_DIGITS if len(INPUT_DIGITS) == 11 else normalize_ndc11(INPUT)
        if not ndc11:
            sys.exit("Cannot normalize package input.")
        ndc9 = ndc11[0:9]
        variants = product_ndc_variants(ndc9)
        q = " OR ".join(['product_ndc:"' + v + '"' for v in variants])
        rows = openfda_paginate("drug/ndc", q, max_pages=10)
        resolution["derived_ndc11"] = ndc11
        resolution["scope"] = "exact_package"
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
        resolution["derived_ndc9"] = ndc9
        resolution["scope"] = "product_all_packages"
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
        resolution["scope"] = "company_all_packages"
        return out

family_rows = resolve_family()
if not family_rows:
    resolution["error"] = "No openFDA NDC rows found."
    (OUTDIR / "run_log.json").write_text(json.dumps(resolution, indent=2, ensure_ascii=False), encoding="utf-8")
    sys.exit("No rows resolved for INPUT='" + INPUT + "'.")

log("openFDA: " + str(len(family_rows)) + " product rows")

# ============================================================
# PHASE 2: BUILD NDC11 IDENTITY MAP
# ============================================================

ndc11_info = {}
all_brands = set()
target_ndc11 = None
if INPUT_KIND == "package":
    target_ndc11 = INPUT_DIGITS if len(INPUT_DIGITS) == 11 else normalize_ndc11(INPUT)

for r in family_rows:
    brand = _ss(r.get("brand_name"))
    generic = _ss(r.get("generic_name"))
    labeler = _ss(r.get("labeler_name"))
    dosage_form = _ss(r.get("dosage_form"))
    product_ndc = _ss(r.get("product_ndc"))
    ndc9 = normalize_ndc9(product_ndc) or ""
    if brand:
        all_brands.add(brand)
    for pkg in (r.get("packaging") or []):
        pkg_ndc_raw = _s((pkg or {}).get("package_ndc", ""))
        ndc11 = normalize_ndc11(pkg_ndc_raw)
        if not ndc11:
            continue
        if target_ndc11 and ndc11 != target_ndc11:
            continue
        if ndc11 not in ndc11_info:
            pkg_desc = _ss(pkg.get("description"))
            # Build display names
            brand_display = brand if brand else generic
            product_display = brand_display
            if dosage_form:
                # Find strength from active_ingredients
                strength = ""
                ai = r.get("active_ingredients", [])
                if isinstance(ai, list) and ai:
                    strength = _ss(ai[0].get("strength")) if isinstance(ai[0], dict) else ""
                if strength:
                    product_display = brand_display + " " + strength + " " + dosage_form
                else:
                    product_display = brand_display + " " + dosage_form
            package_display = product_display
            if pkg_desc:
                package_display = product_display + " [" + pkg_desc + "]"

            ndc11_info[ndc11] = {
                "ndc11": ndc11,
                "ndc11_display": display_ndc11(ndc11),
                "product_ndc": product_ndc,
                "ndc9": ndc9,
                "brand_name": brand,
                "generic_name": generic,
                "labeler_name": labeler,
                "dosage_form": dosage_form,
                "brand_display": brand_display,
                "product_display": product_display,
                "package_display": package_display,
                "package_description": pkg_desc,
            }
        else:
            info = ndc11_info[ndc11]
            if not info["brand_name"] and brand:
                info["brand_name"] = brand

all_ndc11 = sorted(ndc11_info.keys())
brands = sorted(all_brands)
log("Scope: " + str(len(all_ndc11)) + " NDC11s, " + str(len(brands)) + " brand(s)")

# ============================================================
# PHASE 3: FETCH SDUD DATA (ONLY STATE-NATIVE SOURCE)
# ============================================================
# Source classification:
#   SDUD          = state-native, package-native  --> USE for state rows
#   NADAC         = package-native, national       --> reference only
#   Part D/B      = program-summary / HCPCS-native --> EXCLUDED from state rows
#   Medicaid Sp.  = program-summary (drug-level)   --> EXCLUDED from state rows
#   Drugs@FDA     = regulatory                     --> EXCLUDED
#   RxNav         = terminology                    --> EXCLUDED
#   DailyMed      = label-document                 --> EXCLUDED
#   WAC (CHHS)    = CA-only event log              --> EXCLUDED (not per-state)
# ============================================================

log("Fetching SDUD (state-native) + NADAC (national reference)...")

sdud_urls = {}
nadac_urls = {}
for n in all_ndc11:
    sdud_urls[n] = (
        "https://data.medicaid.gov/api/1/datastore/query/"
        "61729e5a-7aa8-448c-8903-ba3e0cd0ea3c/0?"
        + urllib.parse.urlencode({
            "conditions[0][property]": "ndc",
            "conditions[0][value]": n,
            "conditions[0][operator]": "=",
            "limit": "5000",
            "offset": "0",
        })
    )
    nadac_urls[n] = (
        "https://data.medicaid.gov/api/1/datastore/query/"
        "fbb83258-11c7-47f5-8b18-5f8e79f7e704/0?"
        + urllib.parse.urlencode({
            "conditions[0][property]": "ndc",
            "conditions[0][value]": n,
            "conditions[0][operator]": "=",
            "limit": "50",
            "offset": "0",
        })
    )

all_urls = list(sdud_urls.values()) + list(nadac_urls.values())
all_data = fetch_many(all_urls, timeout=120, retries=2)

def G(url):
    return all_data.get(url, {"_error": "not_fetched", "_url": url})

# ============================================================
# PHASE 4: HELPERS
# ============================================================

def to_float(x):
    try:
        v = _s(x).strip().replace(",", "")
        if not v:
            return None
        return float(v)
    except Exception:
        return None

def to_int(x):
    try:
        v = _s(x).strip().replace(",", "")
        if not v:
            return None
        return int(float(v))
    except Exception:
        return None

def ff(x):
    v = to_float(x)
    return "{:.4f}".format(v) if v is not None else ""

def fi(x):
    v = to_int(x)
    return str(v) if v is not None else ""

def recs_med(data):
    if is_err(data):
        return []
    if isinstance(data, dict):
        if "results" in data and isinstance(data["results"], list):
            return data["results"]
        return []
    if isinstance(data, list):
        return data
    return []

def ndc_from_rec(rec):
    for k in ("ndc", "NDC", "ndc_11", "ndc11"):
        v = rec.get(k)
        if v:
            return digits_only(v)
    lc = _s(rec.get("labeler_code", ""))
    pc = _s(rec.get("product_code", ""))
    ps = _s(rec.get("package_size", ""))
    if lc and pc and ps:
        return digits_only(lc).zfill(5) + digits_only(pc).zfill(4) + digits_only(ps).zfill(2)
    return ""

# ============================================================
# PHASE 5: BUILD STATE TABLES
# ============================================================

log("Building state tables...")

STATE_COLS = [
    "state_code", "state_name",
    "ndc11", "ndc11_display", "brand_name", "product_ndc",
    "product_display", "package_display",
    "sdud_status", "sdud_record_count",
    "latest_period", "period_count",
    "total_units_reimbursed", "total_prescriptions",
    "total_amount_reimbursed", "medicaid_amount_reimbursed",
    "non_medicaid_amount_reimbursed",
    "ffsu_units", "ffsu_prescriptions", "ffsu_total_amount",
    "mcou_units", "mcou_prescriptions", "mcou_total_amount",
    "suppression_flag_present",
    "nadac_latest_per_unit", "nadac_effective_date", "nadac_pricing_unit",
    "notes",
]

warnings = []
tables_generated = 0
manifest_rows = []

for ndc11 in all_ndc11:
    info = ndc11_info[ndc11]

    # --- Get NADAC reference (national, not state) ---
    nad_raw = G(nadac_urls[ndc11])
    nadac_ref = {"price": "", "date": "", "unit": ""}
    if not is_err(nad_raw):
        nad_recs = recs_med(nad_raw)
        exact = [r for r in nad_recs if digits_only(r.get("ndc", "")) == ndc11]
        if exact:
            exact.sort(key=lambda x: _s(x.get("effective_date", "")), reverse=True)
            la = exact[0]
            nadac_ref["price"] = ff(la.get("nadac_per_unit", ""))
            nadac_ref["date"] = _s(la.get("effective_date", ""))
            nadac_ref["unit"] = _s(la.get("pricing_unit", ""))

    # --- Get SDUD records and validate exact match ---
    sdud_raw = G(sdud_urls[ndc11])
    sdud_status_global = S_NOT_QUERIED
    sdud_exact = []

    if is_err(sdud_raw):
        sdud_status_global = S_QUERY_ERROR
        warnings.append("SDUD query_error for " + ndc11)
    else:
        sdud_recs = recs_med(sdud_raw)
        if not sdud_recs:
            sdud_status_global = S_NO_DATA
        else:
            sdud_exact = [r for r in sdud_recs if ndc_from_rec(r) == ndc11]
            if sdud_exact:
                sdud_status_global = S_HIT
            else:
                sdud_status_global = S_BAD_FILTER
                warnings.append("SDUD bad_filter for " + ndc11 + ": 0 exact / " + str(len(sdud_recs)) + " returned")

    # --- Group SDUD records by state ---
    state_recs = {}
    for rec in sdud_exact:
        st = _s(rec.get("state", "")).strip().upper()
        if st and len(st) == 2:
            state_recs.setdefault(st, []).append(rec)

    # --- Build one row per state ---
    table_rows = []
    states_with_data = 0

    for sc in STATE_CODES:
        sname = STATE_NAMES[sc]
        recs = state_recs.get(sc, [])

        row = {
            "state_code": sc,
            "state_name": sname,
            "ndc11": ndc11,
            "ndc11_display": info["ndc11_display"],
            "brand_name": info["brand_name"],
            "product_ndc": info["product_ndc"],
            "product_display": info["product_display"],
            "package_display": info["package_display"],
            "sdud_status": "",
            "sdud_record_count": "",
            "latest_period": "",
            "period_count": "",
            "total_units_reimbursed": "",
            "total_prescriptions": "",
            "total_amount_reimbursed": "",
            "medicaid_amount_reimbursed": "",
            "non_medicaid_amount_reimbursed": "",
            "ffsu_units": "",
            "ffsu_prescriptions": "",
            "ffsu_total_amount": "",
            "mcou_units": "",
            "mcou_prescriptions": "",
            "mcou_total_amount": "",
            "suppression_flag_present": "",
            "nadac_latest_per_unit": nadac_ref["price"],
            "nadac_effective_date": nadac_ref["date"],
            "nadac_pricing_unit": nadac_ref["unit"],
            "notes": "",
        }

        if sdud_status_global in (S_QUERY_ERROR, S_BAD_FILTER):
            row["sdud_status"] = sdud_status_global
        elif sdud_status_global == S_NO_DATA:
            row["sdud_status"] = S_NO_DATA
        elif not recs:
            row["sdud_status"] = S_NO_DATA
        else:
            row["sdud_status"] = S_HIT
            row["sdud_record_count"] = str(len(recs))
            states_with_data += 1

            # Determine periods
            periods = set()
            for rec in recs:
                yr = to_int(rec.get("year"))
                qtr = to_int(rec.get("quarter"))
                if yr is not None and qtr is not None:
                    periods.add((yr, qtr))
            if periods:
                latest = max(periods)
                row["latest_period"] = str(latest[0]) + "Q" + str(latest[1])
                row["period_count"] = str(len(periods))

            # Split by utilization type
            ffsu = [r for r in recs if _s(r.get("utilization_type", "")).strip().upper() == "FFSU"]
            mcou = [r for r in recs if _s(r.get("utilization_type", "")).strip().upper() == "MCOU"]

            def _sum(recs_list, keys):
                t = 0.0
                found = False
                for rc in recs_list:
                    for k in keys:
                        v = to_float(rc.get(k))
                        if v is not None:
                            t += v
                            found = True
                            break
                return t if found else None

            # FFSU totals
            fu = _sum(ffsu, ("units_reimbursed",))
            fp = _sum(ffsu, ("number_of_prescriptions",))
            ft = _sum(ffsu, ("total_amount_reimbursed",))
            row["ffsu_units"] = fi(fu)
            row["ffsu_prescriptions"] = fi(fp)
            row["ffsu_total_amount"] = ff(ft)

            # MCOU totals
            mu = _sum(mcou, ("units_reimbursed",))
            mp = _sum(mcou, ("number_of_prescriptions",))
            mt = _sum(mcou, ("total_amount_reimbursed",))
            row["mcou_units"] = fi(mu)
            row["mcou_prescriptions"] = fi(mp)
            row["mcou_total_amount"] = ff(mt)

            # Combined totals
            all_u = _sum(recs, ("units_reimbursed",))
            all_p = _sum(recs, ("number_of_prescriptions",))
            all_t = _sum(recs, ("total_amount_reimbursed",))
            all_m = _sum(recs, ("medicaid_amount_reimbursed",))
            all_n = _sum(recs, ("non_medicaid_amount_reimbursed",))
            row["total_units_reimbursed"] = fi(all_u)
            row["total_prescriptions"] = fi(all_p)
            row["total_amount_reimbursed"] = ff(all_t)
            row["medicaid_amount_reimbursed"] = ff(all_m)
            row["non_medicaid_amount_reimbursed"] = ff(all_n)

            # Suppression
            has_supp = any(
                _s(r.get("suppression_used", "")).strip().upper() in ("TRUE", "Y", "1", "YES")
                for r in recs
            )
            row["suppression_flag_present"] = "Y" if has_supp else "N"

        table_rows.append(row)

    # --- Write CSV for this NDC11 ---
    csv_name = "state_" + ndc11 + ".csv"
    csv_path = CSV_DIR / csv_name
    with open(str(csv_path), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=STATE_COLS, extrasaction="ignore")
        w.writeheader()
        for row in table_rows:
            w.writerow({c: row.get(c, "") for c in STATE_COLS})

    tables_generated += 1
    manifest_rows.append({
        "ndc11": ndc11,
        "ndc11_display": info["ndc11_display"],
        "brand_name": info["brand_name"],
        "product_display": info["product_display"],
        "package_display": info["package_display"],
        "sdud_status": sdud_status_global,
        "states_with_data": states_with_data,
        "csv_file": csv_name,
    })

# ============================================================
# PHASE 6: WRITE WORKBOOK (openpyxl if available)
# ============================================================

xlsx_path = None
try:
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment

    log("Generating Excel workbook...")
    wb = Workbook()
    wb.remove(wb.active)

    header_font = Font(bold=True, size=10)
    header_fill = PatternFill("solid", fgColor="D9E1F2")
    header_align = Alignment(horizontal="center", wrap_text=True)

    for idx, ndc11 in enumerate(all_ndc11):
        info = ndc11_info[ndc11]
        sheet_name = info["brand_name"][0:15] + "_" + ndc11[-4:] if info["brand_name"] else ndc11
        sheet_name = re.sub(r"[^\w-]", "_", sheet_name)[0:31]
        ws = wb.create_sheet(title=sheet_name)

        # Headers
        for ci, col in enumerate(STATE_COLS, 1):
            cell = ws.cell(row=1, column=ci, value=col)
            cell.font = header_font
            cell.fill = header_fill
            cell.alignment = header_align

        # Read back CSV
        csv_path = CSV_DIR / ("state_" + ndc11 + ".csv")
        with open(str(csv_path), "r", encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            for ri, rec in enumerate(reader, 2):
                for ci, col in enumerate(STATE_COLS, 1):
                    val = rec.get(col, "")
                    # Try numeric
                    if val and re.match(r"^-?\d+$", val):
                        val = int(val)
                    elif val and re.match(r"^-?\d+\.\d+$", val):
                        val = float(val)
                    ws.cell(row=ri, column=ci, value=val)

        # Column widths
        for ci, col in enumerate(STATE_COLS, 1):
            ws.column_dimensions[ws.cell(row=1, column=ci).column_letter].width = max(12, len(col) + 2)

    xlsx_path = DEBUG_DIR / ("ndc_geo_matrix_" + INPUT_SAFE + ".xlsx")
    wb.save(str(xlsx_path))
    log("Workbook saved: " + str(xlsx_path))
except ImportError:
    log("openpyxl not available; skipping workbook generation")
    warnings.append("openpyxl not installed; xlsx not generated")
except Exception as exc:
    log("Workbook generation failed: " + repr(exc))
    warnings.append("xlsx generation error: " + repr(exc))

# ============================================================
# PHASE 7: WRITE MANIFEST AND RUN LOG
# ============================================================

manifest_path = DEBUG_DIR / ("manifest_geo_" + INPUT_SAFE + ".csv")
with open(str(manifest_path), "w", newline="", encoding="utf-8") as fh:
    mcols = ["ndc11", "ndc11_display", "brand_name", "product_display",
             "package_display", "sdud_status", "states_with_data", "csv_file"]
    w = csv.DictWriter(fh, fieldnames=mcols, extrasaction="ignore")
    w.writeheader()
    for mr in manifest_rows:
        w.writerow(mr)

elapsed = time.time() - T0

run_log = {
    "input": INPUT,
    "input_kind": INPUT_KIND,
    "scope": resolution.get("scope", ""),
    "brand_count": len(brands),
    "brands": brands[0:20],
    "product_count": len(set(ndc11_info[n]["ndc9"] for n in all_ndc11 if ndc11_info[n]["ndc9"])),
    "ndc11_count": len(all_ndc11),
    "tables_generated": tables_generated,
    "sources_used": [
        {"name": "SDUD", "classification": "state-native, package-native", "role": "primary state rows"},
        {"name": "NADAC", "classification": "package-native, national", "role": "reference columns only (not state-varied)"},
        {"name": "openFDA NDC", "classification": "regulatory, package-native", "role": "identity resolution only"},
    ],
    "sources_excluded": [
        {"name": "Medicare Part D (Annual/Quarterly)", "reason": "program-summary, drug-level grain, not state-native"},
        {"name": "Medicare Part B (Annual/Quarterly)", "reason": "HCPCS-native, not state-native, not NDC-native"},
        {"name": "Medicaid Spending by Drug", "reason": "program-summary, drug-level grain, not state-native"},
        {"name": "WAC (CHHS)", "reason": "CA-only event log, not national-by-state"},
        {"name": "Drugs@FDA", "reason": "regulatory, no state dimension"},
        {"name": "RxNav", "reason": "terminology, no state dimension"},
        {"name": "DailyMed", "reason": "label-document, no state dimension"},
        {"name": "Orange Book", "reason": "regulatory, no state dimension"},
        {"name": "Purple Book", "reason": "regulatory, no state dimension"},
        {"name": "MDRP Product File", "reason": "program reference, no state dimension"},
        {"name": "ACA FUL", "reason": "national benchmark, no state dimension"},
    ],
    "runtime_seconds": round(elapsed, 1),
    "warnings": warnings,
    "output_dir": str(OUTDIR),
    "files": {
        "manifest": str(manifest_path),
        "state_csvs_dir": str(CSV_DIR),
        "xlsx": str(xlsx_path) if xlsx_path else None,
    },
}

run_log_path = LOGS_DIR / ("run_log_geo_" + INPUT_SAFE + ".json")
run_log_path.write_text(json.dumps(run_log, indent=2, ensure_ascii=False), encoding="utf-8")

# ============================================================
# CONSOLE SUMMARY
# ============================================================

print("")
print("=" * 78)
print("NDC GEO MATRIX v1 -- COMPLETE")
print("=" * 78)
print("  INPUT            : " + INPUT)
print("  KIND             : " + INPUT_KIND)
print("  SCOPE            : " + resolution.get("scope", ""))
print("  BRANDS           : " + ", ".join(brands[0:10]) + (" ..." if len(brands) > 10 else ""))
print("  PRODUCTS (NDC9)  : " + str(run_log["product_count"]))
print("  NDC11s           : " + str(len(all_ndc11)))
print("  STATE TABLES     : " + str(tables_generated))
print("  RUNTIME          : " + str(run_log["runtime_seconds"]) + "s")
print("")
print("SOURCES USED FOR STATE ROWS:")
print("  SDUD (Medicaid State Drug Utilization) -- state-native, package-native")
print("")
print("REFERENCE COLUMNS (national, not state-varied):")
print("  NADAC latest price, effective date, pricing unit")
print("")
print("SOURCES EXCLUDED (not state-native):")
for ex in run_log["sources_excluded"]:
    print("  " + ex["name"] + " -- " + ex["reason"])
print("")
print("FILES:")
print("  " + str(manifest_path))
print("  " + str(CSV_DIR) + "/state_<ndc11>.csv  (x" + str(tables_generated) + ")")
if xlsx_path:
    print("  " + str(xlsx_path))
print("  " + str(run_log_path))
print("")

if warnings:
    print("WARNINGS (" + str(len(warnings)) + "):")
    for w in warnings[0:20]:
        print("  " + w)
    if len(warnings) > 20:
        print("  ... and " + str(len(warnings) - 20) + " more")
    print("")

# Manifest preview
print("MANIFEST PREVIEW:")
print("  {:<14} {:<20} {:<10} {:>6}".format("NDC11", "Brand", "SDUD", "States"))
print("  " + "-" * 55)
for mr in manifest_rows[0:15]:
    print("  {:<14} {:<20} {:<10} {:>6}".format(
        mr["ndc11"], mr["brand_name"][0:18], mr["sdud_status"], mr["states_with_data"]))
if len(manifest_rows) > 15:
    print("  ... (" + str(len(manifest_rows) - 15) + " more)")
print("")
ENDOFPYTHON
