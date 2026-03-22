#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NDC SOURCE MATRIX v2
# ============================================================
# One row per unique normalized NDC11.
#
# Usage:
#   INPUT="0006"          bash ndc_source_matrix.sh
#   INPUT="0006-0277"     bash ndc_source_matrix.sh
#   INPUT="0006-0277-02"  bash ndc_source_matrix.sh
#
# Or edit INPUT below and run directly.
# ============================================================

INPUT="${INPUT:-0006}"
OPENFDA_API_KEY="${OPENFDA_API_KEY:-}"
MAX_WORKERS="${MAX_WORKERS:-8}"
CACHE_TTL_HOURS="${CACHE_TTL_HOURS:-24}"
INCLUDE_WAC="${INCLUDE_WAC:-1}"

export INPUT OPENFDA_API_KEY MAX_WORKERS CACHE_TTL_HOURS INCLUDE_WAC

exec python3 - <<'ENDOFPYTHON'
# -*- coding: utf-8 -*-
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

INPUT = os.environ.get("INPUT", "0006").strip()
OPENFDA_API_KEY = os.environ.get("OPENFDA_API_KEY", "").strip()
MAX_WORKERS = max(1, int(os.environ.get("MAX_WORKERS", "8")))
CACHE_TTL_HOURS = max(0, int(os.environ.get("CACHE_TTL_HOURS", "24")))
INCLUDE_WAC = os.environ.get("INCLUDE_WAC", "1").strip() == "1"

def _s(x):
    if x is None:
        return ""
    return str(x)

def _ss(x):
    return _s(x).strip()

S_HIT = "hit"
S_NO_DATA = "no_data"
S_NO_MATCH = "no_match"
S_BAD_FILTER = "bad_filter"
S_QUERY_ERROR = "query_error"
S_NOT_QUERIED = "not_queried"
S_NOT_APPLICABLE = "not_applicable"

def digits_only(x):
    return re.sub(r"\D", "", _s(x))

def upper_clean(x):
    return re.sub(r"\s+", " ", _ss(x)).upper()

def safe_filename(x):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", _s(x))

INPUT_SAFE = safe_filename(INPUT) if INPUT else "EMPTY"
_outdir_env = os.environ.get("OUTDIR", "").strip()
if _outdir_env:
    OUTDIR = Path(_outdir_env)
else:
    OUTDIR = Path.home() / ("ndc_source_matrix_" + INPUT_SAFE)
CACHE_DIR = OUTDIR / "cache"
OUTDIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

def log(msg):
    print("[ndc-matrix] " + str(msg), file=sys.stderr, flush=True)

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
                "User-Agent": "NDCSourceMatrix/2.0",
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
    (OUTDIR / "resolution.json").write_text(json.dumps(resolution, indent=2, ensure_ascii=False), encoding="utf-8")
    sys.exit("No rows resolved for INPUT='" + INPUT + "'.")

log("openFDA: " + str(len(family_rows)) + " product rows")

rows_by_ndc11 = {}
all_brands = set()
target_ndc11 = None
if INPUT_KIND == "package":
    target_ndc11 = INPUT_DIGITS if len(INPUT_DIGITS) == 11 else normalize_ndc11(INPUT)

for r in family_rows:
    brand = _ss(r.get("brand_name"))
    generic = _ss(r.get("generic_name"))
    labeler = _ss(r.get("labeler_name"))
    dosage_form = _ss(r.get("dosage_form"))
    route_raw = r.get("route", [])
    route_str = " | ".join([_s(x) for x in route_raw]) if isinstance(route_raw, list) else _s(route_raw)
    product_ndc = _ss(r.get("product_ndc"))
    ndc9 = normalize_ndc9(product_ndc) or ""
    app_num = _ss(r.get("application_number"))
    listing_exp = _ss(r.get("listing_expiration_date"))
    ofd = r.get("openfda") if isinstance(r.get("openfda"), dict) else {}
    rxcui_raw = ofd.get("rxcui", []) or []
    if not isinstance(rxcui_raw, list):
        rxcui_raw = [rxcui_raw]
    spl_ids = ofd.get("spl_set_id", []) or []
    if not isinstance(spl_ids, list):
        spl_ids = [spl_ids]
    spl_setid = _s(spl_ids[0]) if spl_ids else ""
    if brand:
        all_brands.add(brand)
    for pkg in (r.get("packaging") or []):
        pkg_ndc_raw = _s((pkg or {}).get("package_ndc", ""))
        ndc11 = normalize_ndc11(pkg_ndc_raw)
        if not ndc11:
            continue
        if target_ndc11 and ndc11 != target_ndc11:
            continue
        if ndc11 not in rows_by_ndc11:
            rows_by_ndc11[ndc11] = {
                "ndc11": ndc11, "ndc11_display": display_ndc11(ndc11),
                "package_ndc_source": pkg_ndc_raw, "product_ndc": product_ndc,
                "ndc9": ndc9, "ndc6": ndc11[0:6],
                "brand_name": brand, "generic_name": generic,
                "labeler_name": labeler, "dosage_form": dosage_form,
                "route": route_str,
                "package_description": _ss(pkg.get("description")),
                "application_number": app_num, "spl_setid": spl_setid,
                "rxcui": " | ".join(sorted(set(_s(x) for x in rxcui_raw if x))),
                "listing_expiration_date": listing_exp,
                "marketing_start_date": _ss(pkg.get("marketing_start_date")),
                "sample": _ss(pkg.get("sample")),
            }
        else:
            row = rows_by_ndc11[ndc11]
            existing_rx = set(filter(None, row["rxcui"].split(" | ")))
            for rx in rxcui_raw:
                if rx:
                    existing_rx.add(_s(rx))
            row["rxcui"] = " | ".join(sorted(existing_rx))
            if not row["brand_name"] and brand:
                row["brand_name"] = brand
            if not row["generic_name"] and generic:
                row["generic_name"] = generic
            if not row["labeler_name"] and labeler:
                row["labeler_name"] = labeler
            if not row["spl_setid"] and spl_setid:
                row["spl_setid"] = spl_setid
            if not row["application_number"] and app_num:
                row["application_number"] = app_num

all_ndc11 = sorted(rows_by_ndc11.keys())
brands = sorted(all_brands)
log("Matrix: " + str(len(all_ndc11)) + " NDC11s, " + str(len(brands)) + " brand(s)")

def cms_url(did, filters, size=5000, offset=0):
    qs = {}
    for k, v in filters.items():
        qs["filter[" + k + "]"] = v
    qs["size"] = str(size)
    qs["offset"] = str(offset)
    return "https://data.cms.gov/data-api/v1/dataset/" + did + "/data?" + urllib.parse.urlencode(qs)

nadac_urls = {}
sdud_urls = {}
for n in all_ndc11:
    nadac_urls[n] = ("https://data.medicaid.gov/api/1/datastore/query/fbb83258-11c7-47f5-8b18-5f8e79f7e704/0?" + urllib.parse.urlencode({"conditions[0][property]": "ndc", "conditions[0][value]": n, "conditions[0][operator]": "=", "limit": "50", "offset": "0"}))
    sdud_urls[n] = ("https://data.medicaid.gov/api/1/datastore/query/61729e5a-7aa8-448c-8903-ba3e0cd0ea3c/0?" + urllib.parse.urlencode({"conditions[0][property]": "ndc", "conditions[0][value]": n, "conditions[0][operator]": "=", "limit": "200", "offset": "0"}))

wac_cur_urls = {}
wac_hist_urls = {}
if INCLUDE_WAC:
    for n in all_ndc11:
        wac_cur_urls[n] = ("https://data.chhs.ca.gov/api/action/datastore_search?" + urllib.parse.urlencode({"resource_id": "3a133d3f-da34-43ae-8171-14cdab782b1d", "q": n, "limit": "50"}))
        wac_hist_urls[n] = ("https://data.chhs.ca.gov/api/action/datastore_search?" + urllib.parse.urlencode({"resource_id": "2fe618fd-b03d-4453-aa32-de5b4a470e00", "q": n, "limit": "50"}))

drugsfda_urls = {}
rxnav_urls = {}
dailymed_urls = {}
for b in brands:
    drugsfda_urls[b] = openfda_url("drug/drugsfda", search='products.brand_name:"' + upper_clean(b) + '"', limit=100)
    rxnav_urls[b] = "https://rxnav.nlm.nih.gov/REST/drugs.json?" + urllib.parse.urlencode({"name": b})
    dailymed_urls[b] = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json?" + urllib.parse.urlencode({"drug_name": b, "pagesize": "100"})

PD_ANN = "7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b"
PD_Q = "4ff7c618-4e40-483a-b390-c8a58c94fa15"
MC_SP = "be64fce3-e835-4589-b46b-024198e524a6"
PB_ANN = "76a714ad-3a2c-43ac-b76d-9dadf8f7d890"
PB_Q = "bf6a5b3b-31ee-4abb-b1ad-2607a1e7510a"

pd_ann_urls = {b: cms_url(PD_ANN, {"Brnd_Name": b}) for b in brands}
pd_q_urls = {b: cms_url(PD_Q, {"Brnd_Name": b}) for b in brands}
mc_sp_urls = {b: cms_url(MC_SP, {"Brnd_Name": b}) for b in brands}
pb_ann_urls = {b: cms_url(PB_ANN, {"Brnd_Name": b}) for b in brands}
pb_q_urls = {b: cms_url(PB_Q, {"Brnd_Name": b}) for b in brands}

log("Fetching package-native sources...")
all_pkg = list(nadac_urls.values()) + list(sdud_urls.values())
if INCLUDE_WAC:
    all_pkg += list(wac_cur_urls.values()) + list(wac_hist_urls.values())
pkg_data = fetch_many(all_pkg, timeout=90, retries=2)

log("Fetching brand-level sources...")
all_brd = (list(drugsfda_urls.values()) + list(rxnav_urls.values()) + list(dailymed_urls.values()) + list(pd_ann_urls.values()) + list(pd_q_urls.values()) + list(mc_sp_urls.values()) + list(pb_ann_urls.values()) + list(pb_q_urls.values()))
brd_data = fetch_many(all_brd, timeout=90, retries=2)

all_data = {}
all_data.update(pkg_data)
all_data.update(brd_data)

def G(url):
    return all_data.get(url, {"_error": "not_fetched", "_url": url})

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

def recs_cms(data):
    if is_err(data):
        return []
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and "results" in data:
        r = data["results"]
        return r if isinstance(r, list) else []
    return []

def recs_fda(data):
    if is_err(data):
        return []
    if isinstance(data, dict) and "results" in data:
        r = data["results"]
        return r if isinstance(r, list) else []
    return []

def recs_chhs(data):
    try:
        return data["result"]["records"]
    except Exception:
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

log("Enriching package-native...")

INIT = {
    "src_nadac": 0, "src_nadac_status": S_NOT_QUERIED,
    "nadac_eff_date": "", "nadac_per_unit": "", "nadac_unit": "",
    "nadac_otc": "", "nadac_class": "", "nadac_count": "",
    "src_sdud": 0, "src_sdud_status": S_NOT_QUERIED,
    "sdud_count": "", "sdud_year": "", "sdud_quarter": "",
    "sdud_states": "", "sdud_units": "", "sdud_rx": "", "sdud_reimb": "",
    "src_wac_cur": 0, "src_wac_cur_status": S_NOT_QUERIED,
    "wac_cur_date": "", "wac_cur_price": "",
    "src_wac_hist": 0, "src_wac_hist_status": S_NOT_QUERIED,
    "wac_hist_date": "", "wac_hist_price": "",
    "src_drugsfda": 0, "src_drugsfda_status": S_NOT_QUERIED,
    "drugsfda_apps": "", "drugsfda_sponsors": "", "drugsfda_approval": "",
    "src_rxnav": 0, "src_rxnav_status": S_NOT_QUERIED,
    "rxnav_rxcuis": "", "rxnav_names": "",
    "src_dailymed": 0, "src_dailymed_status": S_NOT_QUERIED,
    "dm_spl_count": "", "dm_spl_ids": "",
    "src_pd_ann": 0, "src_pd_ann_status": S_NOT_QUERIED,
    "pd_ann_yr": "", "pd_ann_spend": "", "pd_ann_clm": "",
    "pd_ann_ben": "", "pd_ann_units": "", "pd_ann_avg_u": "", "pd_ann_avg_c": "",
    "src_pd_q": 0, "src_pd_q_status": S_NOT_QUERIED,
    "pd_q_per": "", "pd_q_spend": "", "pd_q_clm": "", "pd_q_ben": "", "pd_q_avg_c": "",
    "src_mc_sp": 0, "src_mc_sp_status": S_NOT_QUERIED,
    "mc_sp_yr": "", "mc_sp_spend": "", "mc_sp_clm": "", "mc_sp_units": "", "mc_sp_avg_u": "",
    "src_pb_ann": 0, "src_pb_ann_status": S_NOT_QUERIED,
    "pb_ann_hcpcs": "", "pb_ann_yr": "", "pb_ann_spend": "",
    "pb_ann_clm": "", "pb_ann_ben": "", "pb_ann_units": "", "pb_ann_avg_u": "",
    "src_pb_q": 0, "src_pb_q_status": S_NOT_QUERIED,
    "pb_q_hcpcs": "", "pb_q_per": "", "pb_q_spend": "", "pb_q_clm": "", "pb_q_ben": "",
    "source_count": 1,
}

for ndc11 in all_ndc11:
    row = rows_by_ndc11[ndc11]
    row.update({k: v for k, v in INIT.items()})

    # NADAC
    nd = G(nadac_urls[ndc11])
    if is_err(nd):
        row["src_nadac_status"] = S_QUERY_ERROR
    else:
        nr = recs_med(nd)
        if not nr:
            row["src_nadac_status"] = S_NO_DATA
        else:
            exact = [x for x in nr if digits_only(x.get("ndc", "")) == ndc11]
            if exact:
                row["src_nadac"] = 1
                row["src_nadac_status"] = S_HIT
                row["nadac_count"] = str(len(exact))
                exact.sort(key=lambda x: _s(x.get("effective_date", "")), reverse=True)
                la = exact[0]
                row["nadac_eff_date"] = _s(la.get("effective_date", ""))
                row["nadac_per_unit"] = ff(la.get("nadac_per_unit", ""))
                row["nadac_unit"] = _s(la.get("pricing_unit", ""))
                row["nadac_otc"] = _s(la.get("otc", ""))
                row["nadac_class"] = _s(la.get("classification_for_rate_setting", ""))
            else:
                row["src_nadac_status"] = S_BAD_FILTER
                row["nadac_count"] = "0/" + str(len(nr))

    # SDUD
    sd = G(sdud_urls[ndc11])
    if is_err(sd):
        row["src_sdud_status"] = S_QUERY_ERROR
    else:
        sr = recs_med(sd)
        if not sr:
            row["src_sdud_status"] = S_NO_DATA
        else:
            exact = [x for x in sr if ndc_from_rec(x) == ndc11]
            if exact:
                row["src_sdud"] = 1
                row["src_sdud_status"] = S_HIT
                row["sdud_count"] = str(len(exact))
                yrs = [to_int(x.get("year")) for x in exact]
                yrs = [y for y in yrs if y is not None]
                if yrs:
                    ly = max(yrs)
                    row["sdud_year"] = str(ly)
                    qs = [to_int(x.get("quarter")) for x in exact if to_int(x.get("year")) == ly]
                    qs = [q for q in qs if q is not None]
                    if qs:
                        row["sdud_quarter"] = str(max(qs))
                sts = set(_s(x.get("state", "")).strip() for x in exact if x.get("state"))
                row["sdud_states"] = str(len(sts))
                def _sf(recs, keys):
                    t = 0.0
                    f = False
                    for rc in recs:
                        for k in keys:
                            v = to_float(rc.get(k))
                            if v is not None:
                                t += v
                                f = True
                                break
                    return t if f else None
                su = _sf(exact, ("units_reimbursed", "units"))
                sx = _sf(exact, ("number_of_prescriptions", "prescriptions"))
                ss = _sf(exact, ("medicaid_amount_reimbursed", "total_amount_reimbursed"))
                row["sdud_units"] = fi(su)
                row["sdud_rx"] = fi(sx)
                row["sdud_reimb"] = ff(ss)
            else:
                row["src_sdud_status"] = S_BAD_FILTER
                row["sdud_count"] = "0/" + str(len(sr))

    # WAC
    if INCLUDE_WAC:
        for wu, ws, wf, wd, wp in [
            (wac_cur_urls, "src_wac_cur_status", "src_wac_cur", "wac_cur_date", "wac_cur_price"),
            (wac_hist_urls, "src_wac_hist_status", "src_wac_hist", "wac_hist_date", "wac_hist_price"),
        ]:
            wd2 = G(wu[ndc11])
            if is_err(wd2):
                row[ws] = S_QUERY_ERROR
            else:
                wr = recs_chhs(wd2)
                if not wr:
                    row[ws] = S_NO_DATA
                else:
                    we = [x for x in wr if digits_only(x.get("ndc", x.get("NDC", ""))) == ndc11]
                    if we:
                        row[wf] = 1
                        row[ws] = S_HIT
                        we.sort(key=lambda x: _s(x.get("effective_date", x.get("wac_effective_date", ""))), reverse=True)
                        wb = we[0]
                        row[wd] = _s(wb.get("effective_date", wb.get("wac_effective_date", "")))
                        for pk in ("wac_unit_price", "unit_price", "wac_after_increase", "price"):
                            pv = wb.get(pk)
                            if pv is not None and _s(pv).strip():
                                row[wp] = ff(pv)
                                break
                    else:
                        row[ws] = S_BAD_FILTER

log("Enriching brand-level...")

def find_yr(rec, pfx):
    rgx = re.compile("^" + re.escape(pfx) + r"_(\d{4})$")
    yy = []
    for k, v in rec.items():
        m = rgx.match(k)
        if m and v is not None and _s(v).strip() not in ("", "null"):
            yy.append(int(m.group(1)))
    return max(yy) if yy else None

def pick_ov(recs):
    if not recs:
        return []
    ov = [r for r in recs if not _s(r.get("Mftr_Name", "")).strip() or _s(r.get("Mftr_Name", "")).strip().upper() == "OVERALL"]
    return ov if ov else recs

be_map = {}
for brand in brands:
    be = {}
    # Drugs@FDA
    dfd = G(drugsfda_urls[brand])
    dr = recs_fda(dfd)
    if is_err(dfd):
        be["dfd_st"] = S_QUERY_ERROR
    elif not dr:
        be["dfd_st"] = S_NO_DATA
    else:
        be["dfd_st"] = S_HIT
        an = set()
        sp = set()
        ap = []
        for rc in dr:
            if rc.get("application_number"):
                an.add(_s(rc["application_number"]))
            if rc.get("sponsor_name"):
                sp.add(_s(rc["sponsor_name"]))
            for p in (rc.get("products") or []):
                if p.get("approval_date"):
                    ap.append(_s(p["approval_date"]))
        be["dfd_apps"] = sorted(an)
        be["dfd_sponsors"] = sorted(sp)
        be["dfd_approval"] = min(ap) if ap else ""

    # RxNav
    rxd = G(rxnav_urls[brand])
    if is_err(rxd):
        be["rx_st"] = S_QUERY_ERROR
    else:
        sbd_r = []
        sbd_n = []
        try:
            for cg in (rxd.get("drugGroup", {}).get("conceptGroup", []) or []):
                if cg.get("tty") == "SBD":
                    for cp in (cg.get("conceptProperties") or []):
                        if cp.get("rxcui"):
                            sbd_r.append(_s(cp["rxcui"]))
                        if cp.get("name"):
                            sbd_n.append(_s(cp["name"]))
        except Exception:
            pass
        be["rx_st"] = S_HIT if sbd_r else S_NO_DATA
        be["rx_rxcuis"] = sorted(set(sbd_r))
        be["rx_names"] = sorted(set(sbd_n))

    # DailyMed
    dmd = G(dailymed_urls[brand])
    if is_err(dmd):
        be["dm_st"] = S_QUERY_ERROR
    else:
        spls = (dmd.get("data", []) or []) if isinstance(dmd, dict) else []
        sids = sorted(set(_s(s.get("setid") or s.get("set_id") or "") for s in spls if (s.get("setid") or s.get("set_id"))))
        be["dm_st"] = S_HIT if sids else S_NO_DATA
        be["dm_sids"] = sids
        be["dm_ct"] = len(sids)

    # Part D Annual
    pda = recs_cms(G(pd_ann_urls[brand]))
    if is_err(G(pd_ann_urls[brand])):
        be["pda_st"] = S_QUERY_ERROR
    elif not pda:
        be["pda_st"] = S_NO_DATA
    else:
        ov = pick_ov(pda)
        best = None
        by = -1
        for rc in ov:
            y = find_yr(rc, "Tot_Spndng")
            if y is not None and y > by:
                by = y
                best = rc
        if best and by > 0:
            be["pda_st"] = S_HIT
            be["pda_yr"] = by
            be["pda_spend"] = to_float(best.get("Tot_Spndng_" + str(by)))
            be["pda_clm"] = to_int(best.get("Tot_Clms_" + str(by)))
            be["pda_ben"] = to_int(best.get("Tot_Benes_" + str(by)))
            be["pda_units"] = to_float(best.get("Tot_Dsg_Unts_" + str(by)))
            be["pda_avg_u"] = to_float(best.get("Avg_Spnd_Per_Dsg_Unt_Wghtd_" + str(by)))
            be["pda_avg_c"] = to_float(best.get("Avg_Spnd_Per_Clm_" + str(by)))
        else:
            be["pda_st"] = S_NO_MATCH

    # Part D Quarterly
    pdq = recs_cms(G(pd_q_urls[brand]))
    if is_err(G(pd_q_urls[brand])):
        be["pdq_st"] = S_QUERY_ERROR
    elif not pdq:
        be["pdq_st"] = S_NO_DATA
    else:
        ov = pick_ov(pdq)
        def _py(s):
            m = re.search(r"(\d{4})", _s(s))
            return int(m.group(1)) if m else -1
        ov.sort(key=lambda r: _py(r.get("Year")), reverse=True)
        if ov:
            be["pdq_st"] = S_HIT
            rc = ov[0]
            be["pdq_per"] = _s(rc.get("Year", ""))
            be["pdq_spend"] = to_float(rc.get("Tot_Spndng"))
            be["pdq_clm"] = to_int(rc.get("Tot_Clms"))
            be["pdq_ben"] = to_int(rc.get("Tot_Benes"))
            be["pdq_avg_c"] = to_float(rc.get("Avg_Spnd_Per_Clm"))
        else:
            be["pdq_st"] = S_NO_MATCH

    # Medicaid Spending
    msr = recs_cms(G(mc_sp_urls[brand]))
    if is_err(G(mc_sp_urls[brand])):
        be["mc_st"] = S_QUERY_ERROR
    elif not msr:
        be["mc_st"] = S_NO_DATA
    else:
        ov = pick_ov(msr)
        best = None
        by = -1
        for rc in ov:
            y = find_yr(rc, "Tot_Spndng")
            if y is not None and y > by:
                by = y
                best = rc
        if best and by > 0:
            be["mc_st"] = S_HIT
            be["mc_yr"] = by
            be["mc_spend"] = to_float(best.get("Tot_Spndng_" + str(by)))
            be["mc_clm"] = to_int(best.get("Tot_Clms_" + str(by)))
            be["mc_units"] = to_float(best.get("Tot_Dsg_Unts_" + str(by)))
            be["mc_avg_u"] = to_float(best.get("Avg_Spnd_Per_Dsg_Unt_Wghtd_" + str(by)))
        else:
            be["mc_st"] = S_NO_MATCH

    # Part B Annual
    pba = recs_cms(G(pb_ann_urls[brand]))
    if is_err(G(pb_ann_urls[brand])):
        be["pba_st"] = S_QUERY_ERROR
    elif not pba:
        be["pba_st"] = S_NO_DATA
    else:
        by = -1
        for rc in pba:
            y = find_yr(rc, "Tot_Spndng")
            if y is not None and y > by:
                by = y
        if by > 0:
            lat = [r for r in pba if find_yr(r, "Tot_Spndng") == by]
            be["pba_st"] = S_HIT
            be["pba_hcpcs"] = sorted(set(_s(r.get("HCPCS_Cd", "")).strip() for r in lat if r.get("HCPCS_Cd")))
            be["pba_yr"] = by
            be["pba_spend"] = sum(x for x in [to_float(r.get("Tot_Spndng_" + str(by))) for r in lat] if x is not None) or None
            be["pba_clm"] = sum(x for x in [to_int(r.get("Tot_Clms_" + str(by))) for r in lat] if x is not None) or None
            be["pba_ben"] = sum(x for x in [to_int(r.get("Tot_Benes_" + str(by))) for r in lat] if x is not None) or None
            be["pba_units"] = sum(x for x in [to_float(r.get("Tot_Dsg_Unts_" + str(by))) for r in lat] if x is not None) or None
            sp2 = be["pba_spend"]
            un2 = be["pba_units"]
            be["pba_avg_u"] = (sp2 / un2) if sp2 and un2 else None
        else:
            be["pba_st"] = S_NO_MATCH

    # Part B Quarterly
    pbq = recs_cms(G(pb_q_urls[brand]))
    if is_err(G(pb_q_urls[brand])):
        be["pbq_st"] = S_QUERY_ERROR
    elif not pbq:
        be["pbq_st"] = S_NO_DATA
    else:
        def _py2(s):
            m = re.search(r"(\d{4})", _s(s))
            return int(m.group(1)) if m else -1
        pbq.sort(key=lambda r: _py2(r.get("Year")), reverse=True)
        if pbq:
            ly2 = _py2(pbq[0].get("Year"))
            same = [r for r in pbq if _py2(r.get("Year")) == ly2]
            be["pbq_st"] = S_HIT
            be["pbq_hcpcs"] = sorted(set(_s(r.get("HCPCS_Cd", "")).strip() for r in same if r.get("HCPCS_Cd")))
            be["pbq_per"] = _s(pbq[0].get("Year", ""))
            be["pbq_spend"] = sum(x for x in [to_float(r.get("Tot_Spndng")) for r in same] if x is not None) or None
            be["pbq_clm"] = sum(x for x in [to_int(r.get("Tot_Clms")) for r in same] if x is not None) or None
            be["pbq_ben"] = sum(x for x in [to_int(r.get("Tot_Benes")) for r in same] if x is not None) or None
        else:
            be["pbq_st"] = S_NO_MATCH

    be_map[brand] = be

log("Projecting brand data...")

for ndc11 in all_ndc11:
    row = rows_by_ndc11[ndc11]
    be = be_map.get(row["brand_name"], {})

    row["src_drugsfda_status"] = be.get("dfd_st", S_NOT_QUERIED)
    if be.get("dfd_st") == S_HIT:
        row["src_drugsfda"] = 1
        row["drugsfda_apps"] = " | ".join(be.get("dfd_apps", []))
        row["drugsfda_sponsors"] = " | ".join(be.get("dfd_sponsors", []))
        row["drugsfda_approval"] = be.get("dfd_approval", "")
        if not row["application_number"] and be.get("dfd_apps"):
            row["application_number"] = be["dfd_apps"][0]

    row["src_rxnav_status"] = be.get("rx_st", S_NOT_QUERIED)
    if be.get("rx_st") == S_HIT:
        row["src_rxnav"] = 1
        row["rxnav_rxcuis"] = " | ".join(be.get("rx_rxcuis", []))
        row["rxnav_names"] = " | ".join(be.get("rx_names", []))

    row["src_dailymed_status"] = be.get("dm_st", S_NOT_QUERIED)
    if be.get("dm_st") == S_HIT:
        row["src_dailymed"] = 1
        row["dm_spl_count"] = str(be.get("dm_ct", ""))
        row["dm_spl_ids"] = " | ".join(be.get("dm_sids", []))
        if not row["spl_setid"] and be.get("dm_sids"):
            row["spl_setid"] = be["dm_sids"][0]

    row["src_pd_ann_status"] = be.get("pda_st", S_NOT_QUERIED)
    if be.get("pda_st") == S_HIT:
        row["src_pd_ann"] = 1
        row["pd_ann_yr"] = str(be.get("pda_yr", ""))
        row["pd_ann_spend"] = ff(be.get("pda_spend"))
        row["pd_ann_clm"] = fi(be.get("pda_clm"))
        row["pd_ann_ben"] = fi(be.get("pda_ben"))
        row["pd_ann_units"] = fi(be.get("pda_units"))
        row["pd_ann_avg_u"] = ff(be.get("pda_avg_u"))
        row["pd_ann_avg_c"] = ff(be.get("pda_avg_c"))

    row["src_pd_q_status"] = be.get("pdq_st", S_NOT_QUERIED)
    if be.get("pdq_st") == S_HIT:
        row["src_pd_q"] = 1
        row["pd_q_per"] = str(be.get("pdq_per", ""))
        row["pd_q_spend"] = ff(be.get("pdq_spend"))
        row["pd_q_clm"] = fi(be.get("pdq_clm"))
        row["pd_q_ben"] = fi(be.get("pdq_ben"))
        row["pd_q_avg_c"] = ff(be.get("pdq_avg_c"))

    row["src_mc_sp_status"] = be.get("mc_st", S_NOT_QUERIED)
    if be.get("mc_st") == S_HIT:
        row["src_mc_sp"] = 1
        row["mc_sp_yr"] = str(be.get("mc_yr", ""))
        row["mc_sp_spend"] = ff(be.get("mc_spend"))
        row["mc_sp_clm"] = fi(be.get("mc_clm"))
        row["mc_sp_units"] = fi(be.get("mc_units"))
        row["mc_sp_avg_u"] = ff(be.get("mc_avg_u"))

    row["src_pb_ann_status"] = be.get("pba_st", S_NOT_QUERIED)
    if be.get("pba_st") == S_HIT:
        row["src_pb_ann"] = 1
        row["pb_ann_hcpcs"] = " | ".join(be.get("pba_hcpcs", []))
        row["pb_ann_yr"] = str(be.get("pba_yr", ""))
        row["pb_ann_spend"] = ff(be.get("pba_spend"))
        row["pb_ann_clm"] = fi(be.get("pba_clm"))
        row["pb_ann_ben"] = fi(be.get("pba_ben"))
        row["pb_ann_units"] = fi(be.get("pba_units"))
        row["pb_ann_avg_u"] = ff(be.get("pba_avg_u"))

    row["src_pb_q_status"] = be.get("pbq_st", S_NOT_QUERIED)
    if be.get("pbq_st") == S_HIT:
        row["src_pb_q"] = 1
        row["pb_q_hcpcs"] = " | ".join(be.get("pbq_hcpcs", []))
        row["pb_q_per"] = str(be.get("pbq_per", ""))
        row["pb_q_spend"] = ff(be.get("pbq_spend"))
        row["pb_q_clm"] = fi(be.get("pbq_clm"))
        row["pb_q_ben"] = fi(be.get("pbq_ben"))

    ct = 1
    for k in row:
        if k.startswith("src_") and not k.endswith("_status") and row[k] == 1:
            ct += 1
    row["source_count"] = ct

matrix = sorted(rows_by_ndc11.values(), key=lambda r: (r.get("brand_name", ""), r.get("product_ndc", ""), r.get("ndc11", "")))

COLS = [
    "ndc11", "ndc11_display", "package_ndc_source", "product_ndc", "ndc9", "ndc6",
    "brand_name", "generic_name", "labeler_name", "dosage_form", "route",
    "package_description", "application_number", "spl_setid", "rxcui",
    "listing_expiration_date", "marketing_start_date", "sample",
    "source_count",
    "src_nadac", "src_nadac_status",
    "src_sdud", "src_sdud_status",
    "src_wac_cur", "src_wac_cur_status",
    "src_wac_hist", "src_wac_hist_status",
    "src_drugsfda", "src_drugsfda_status",
    "src_rxnav", "src_rxnav_status",
    "src_dailymed", "src_dailymed_status",
    "src_pd_ann", "src_pd_ann_status",
    "src_pd_q", "src_pd_q_status",
    "src_mc_sp", "src_mc_sp_status",
    "src_pb_ann", "src_pb_ann_status",
    "src_pb_q", "src_pb_q_status",
    "nadac_eff_date", "nadac_per_unit", "nadac_unit", "nadac_otc",
    "nadac_class", "nadac_count",
    "sdud_count", "sdud_year", "sdud_quarter",
    "sdud_states", "sdud_units", "sdud_rx", "sdud_reimb",
    "wac_cur_date", "wac_cur_price", "wac_hist_date", "wac_hist_price",
    "drugsfda_apps", "drugsfda_sponsors", "drugsfda_approval",
    "rxnav_rxcuis", "rxnav_names",
    "dm_spl_count", "dm_spl_ids",
    "pd_ann_yr", "pd_ann_spend", "pd_ann_clm", "pd_ann_ben",
    "pd_ann_units", "pd_ann_avg_u", "pd_ann_avg_c",
    "pd_q_per", "pd_q_spend", "pd_q_clm", "pd_q_ben", "pd_q_avg_c",
    "mc_sp_yr", "mc_sp_spend", "mc_sp_clm", "mc_sp_units", "mc_sp_avg_u",
    "pb_ann_hcpcs", "pb_ann_yr", "pb_ann_spend",
    "pb_ann_clm", "pb_ann_ben", "pb_ann_units", "pb_ann_avg_u",
    "pb_q_hcpcs", "pb_q_per", "pb_q_spend", "pb_q_clm", "pb_q_ben",
]

COMPACT = [
    "ndc11", "ndc11_display", "product_ndc", "brand_name", "generic_name",
    "labeler_name", "dosage_form", "package_description", "source_count",
    "src_nadac_status", "src_sdud_status", "src_pd_ann_status",
    "src_mc_sp_status", "src_pb_ann_status", "nadac_per_unit", "nadac_unit",
]

def write_csv(path, rows, cols):
    with open(str(path), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})

csv_p = OUTDIR / "ndc11_source_matrix.csv"
cmp_p = OUTDIR / "ndc11_compact.csv"
res_p = OUTDIR / "resolution.json"

write_csv(csv_p, matrix, COLS)
write_csv(cmp_p, matrix, COMPACT)

resolution.update({
    "brands": brands, "brand_count": len(brands),
    "product_count": len(set(r["ndc9"] for r in matrix if r.get("ndc9"))),
    "ndc11_count": len(all_ndc11), "ndc11s": all_ndc11,
    "outdir": str(OUTDIR),
})
res_p.write_text(json.dumps(resolution, indent=2, ensure_ascii=False), encoding="utf-8")

print("")
print("=" * 78)
print("NDC SOURCE MATRIX v2 -- COMPLETE")
print("=" * 78)
print("  INPUT            : " + INPUT)
print("  KIND             : " + INPUT_KIND)
print("  SCOPE            : " + resolution.get("scope", ""))
print("  BRANDS           : " + ", ".join(brands[0:10]) + (" ..." if len(brands) > 10 else ""))
print("  PRODUCTS (NDC9)  : " + str(resolution["product_count"]))
print("  ROWS (NDC11)     : " + str(len(all_ndc11)))
print("")
print("FILES:")
print("  " + str(csv_p))
print("  " + str(cmp_p))
print("  " + str(res_p))
print("")

scols = [c for c in COLS if c.endswith("_status")]
print("SOURCE STATUS SUMMARY:")
print("  {:<24} {:>5} {:>8} {:>8} {:>6} {:>8} {:>5}".format("Source", "hit", "no_data", "bad_flt", "q_err", "no_mtch", "n/q"))
print("  " + "-" * 68)
for sc in scols:
    sn = sc.replace("src_", "").replace("_status", "")
    cc = {}
    for r in matrix:
        sv = r.get(sc, S_NOT_QUERIED)
        cc[sv] = cc.get(sv, 0) + 1
    print("  {:<24} {:>5} {:>8} {:>8} {:>6} {:>8} {:>5}".format(sn, cc.get(S_HIT, 0), cc.get(S_NO_DATA, 0), cc.get(S_BAD_FILTER, 0), cc.get(S_QUERY_ERROR, 0), cc.get(S_NO_MATCH, 0), cc.get(S_NOT_QUERIED, 0)))

print("")
pc = ["ndc11", "brand_name", "source_count", "src_nadac_status", "nadac_per_unit"]
print("PREVIEW (first 15):")
print("  " + " | ".join("{:<22}".format(c) for c in pc))
print("  " + "-" * (24 * len(pc)))
for r in matrix[0:15]:
    print("  " + " | ".join("{:<22}".format(str(r.get(c, ""))) for c in pc))
print("")
ENDOFPYTHON

