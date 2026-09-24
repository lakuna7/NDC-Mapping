#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NDC LOOKUP v1
# ============================================================
# Lightweight family hierarchy browser.
# Shows what you're about to analyze before running the full scripts.
#
# Usage:
#   INPUT="0006"          bash ndc_lookup.sh   # company: all products + packages
#   INPUT="0006-0277"     bash ndc_lookup.sh   # product: all packages under it
#   INPUT="0006-0277-31"  bash ndc_lookup.sh   # package: just that one row
#
# Returns:
#   - scope summary (company/product/package)
#   - brand list
#   - product (NDC9) list with strength + form
#   - package (NDC11) list with descriptions
#   - counts at each level
#   - recommended next commands
# ============================================================

INPUT="${INPUT:-0006}"
OPENFDA_API_KEY="${OPENFDA_API_KEY:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
export PROJECT_ROOT INPUT OPENFDA_API_KEY
export BASH_SOURCE_DIR="$SCRIPT_DIR"

exec python3 - <<'ENDOFPYTHON'
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path

INPUT = os.environ.get("INPUT", "0006").strip()
OPENFDA_API_KEY = os.environ.get("OPENFDA_API_KEY", "").strip()

def _s(x):
    if x is None:
        return ""
    return str(x)

def _ss(x):
    return _s(x).strip()

def digits_only(x):
    return re.sub(r"\D", "", _s(x))

# ============================================================
# NDC NORMALIZATION (same as other scripts)
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

# ============================================================
# HTTP (minimal, no cache needed for lookup)
# ============================================================

def http_get_json(url, timeout=60):
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "NDCLookup/1.0",
            "Accept": "application/json",
        })
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except Exception as exc:
        return {"_error": repr(exc)}

def openfda_url(search, limit=100, skip=0):
    qs = {}
    if OPENFDA_API_KEY:
        qs["api_key"] = OPENFDA_API_KEY
    qs["search"] = search
    qs["limit"] = str(limit)
    qs["skip"] = str(skip)
    return "https://api.fda.gov/drug/ndc.json?" + urllib.parse.urlencode(qs)

def openfda_paginate(search, max_pages=20):
    rows = []
    skip = 0
    for _ in range(max_pages):
        data = http_get_json(openfda_url(search, limit=100, skip=skip), timeout=90)
        if "_error" in data:
            break
        batch = data.get("results", [])
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < 100:
            break
        skip += 100
        time.sleep(0.15)
    return rows

# ============================================================
# RESOLVE
# ============================================================

INPUT_KIND = detect_kind(INPUT)
INPUT_DIGITS = digits_only(INPUT)

def resolve():
    if INPUT_KIND == "package":
        ndc11 = INPUT_DIGITS if len(INPUT_DIGITS) == 11 else normalize_ndc11(INPUT)
        if not ndc11:
            sys.exit("Cannot normalize package input.")
        ndc9 = ndc11[0:9]
        variants = product_ndc_variants(ndc9)
        q = " OR ".join(['product_ndc:"' + v + '"' for v in variants])
        rows = openfda_paginate(q, max_pages=10)
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
        rows = openfda_paginate(q, max_pages=15)
        return [r for r in rows if normalize_ndc9(_s(r.get("product_ndc", ""))) == ndc9]
    else:
        terms = labeler_terms(INPUT_DIGITS)
        all_rows = []
        for t in terms:
            all_rows.extend(openfda_paginate("product_ndc:" + t + "*", max_pages=30))
        seen = set()
        deduped = []
        for r in all_rows:
            key = _s(r.get("product_ndc", ""))
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

rows = resolve()
if not rows:
    sys.exit("No results for INPUT='" + INPUT + "'.")

# ============================================================
# BUILD HIERARCHY
# ============================================================

# Collect: brands -> products -> packages
brands = {}  # brand_name -> {product_ndc -> {ndc11 -> info}}

target_ndc11 = None
if INPUT_KIND == "package":
    target_ndc11 = INPUT_DIGITS if len(INPUT_DIGITS) == 11 else normalize_ndc11(INPUT)

for r in rows:
    brand = _ss(r.get("brand_name")) or _ss(r.get("generic_name")) or "UNKNOWN"
    generic = _ss(r.get("generic_name"))
    labeler = _ss(r.get("labeler_name"))
    dosage_form = _ss(r.get("dosage_form"))
    product_ndc = _ss(r.get("product_ndc"))
    ndc9 = normalize_ndc9(product_ndc) or ""
    marketing_status = _ss(r.get("marketing_status"))

    # Build strength string
    strength = ""
    ai = r.get("active_ingredients", [])
    if isinstance(ai, list) and ai and isinstance(ai[0], dict):
        strength = _ss(ai[0].get("strength"))

    product_label = brand
    if strength:
        product_label = brand + " " + strength
    if dosage_form:
        product_label = product_label + " " + dosage_form

    if brand not in brands:
        brands[brand] = {
            "generic": generic,
            "labeler": labeler,
            "products": {},
        }

    if ndc9 not in brands[brand]["products"]:
        brands[brand]["products"][ndc9] = {
            "product_ndc": product_ndc,
            "label": product_label,
            "dosage_form": dosage_form,
            "strength": strength,
            "marketing_status": marketing_status,
            "packages": {},
        }

    for pkg in (r.get("packaging") or []):
        pkg_ndc_raw = _s(pkg.get("package_ndc", ""))
        ndc11 = normalize_ndc11(pkg_ndc_raw)
        if not ndc11:
            continue
        if target_ndc11 and ndc11 != target_ndc11:
            continue
        pkg_desc = _ss(pkg.get("description"))
        brands[brand]["products"][ndc9]["packages"][ndc11] = {
            "display": display_ndc11(ndc11),
            "description": pkg_desc,
        }

# ============================================================
# COUNT
# ============================================================

total_brands = len(brands)
total_products = sum(len(b["products"]) for b in brands.values())
total_packages = sum(
    len(p["packages"])
    for b in brands.values()
    for p in b["products"].values()
)

# ============================================================
# DISPLAY
# ============================================================

W = 70

print("")
print("=" * W)
print("NDC LOOKUP")
print("=" * W)
print("  INPUT   : " + INPUT)
print("  SCOPE   : " + INPUT_KIND)
print("  BRANDS  : " + str(total_brands))
print("  PRODUCTS: " + str(total_products) + " (unique NDC9)")
print("  PACKAGES: " + str(total_packages) + " (unique NDC11)")
print("")

for brand_name in sorted(brands.keys()):
    binfo = brands[brand_name]
    product_count = len(binfo["products"])
    package_count = sum(len(p["packages"]) for p in binfo["products"].values())

    print("-" * W)
    print("BRAND: " + brand_name)
    print("  Labeler : " + binfo["labeler"])
    print("  Generic : " + binfo["generic"])
    print("  Products: " + str(product_count) + "   Packages: " + str(package_count))
    print("")

    for ndc9 in sorted(binfo["products"].keys()):
        pinfo = binfo["products"][ndc9]
        pkg_count = len(pinfo["packages"])

        print("  PRODUCT: " + pinfo["label"])
        print("    NDC9     : " + pinfo["product_ndc"] + " (" + ndc9 + ")")
        print("    Status   : " + pinfo["marketing_status"])
        print("    Packages : " + str(pkg_count))

        for ndc11 in sorted(pinfo["packages"].keys()):
            pkinfo = pinfo["packages"][ndc11]
            print("      " + pkinfo["display"] + "  " + pkinfo["description"])

        print("")

# ============================================================
# SUGGESTED COMMANDS
# ============================================================

print("=" * W)
print("NEXT STEPS")
print("=" * W)
print("")

if INPUT_KIND == "company":
    print("  Run full analysis for ALL " + str(total_packages) + " packages:")
    print("    INPUT=\"" + INPUT + "\" bash ndc_source_matrix.sh")
    print("")
    if total_products > 1:
        print("  Or pick a specific product:")
        shown = 0
        for b in brands.values():
            for ndc9, p in sorted(b["products"].items()):
                if shown >= 5:
                    break
                print("    INPUT=\"" + p["product_ndc"] + "\" bash ndc_lookup.sh   # " + p["label"])
                shown += 1
            if shown >= 5:
                break
        if total_products > 5:
            print("    ... (" + str(total_products - 5) + " more products)")
        print("")

elif INPUT_KIND == "product":
    print("  Run full analysis for all " + str(total_packages) + " packages:")
    print("    INPUT=\"" + INPUT + "\" bash ndc_source_matrix.sh")
    print("    INPUT=\"" + INPUT + "\" bash ndc_geo_matrix.sh")
    print("    INPUT=\"" + INPUT + "\" bash ndc_shortages.sh")
    print("    INPUT=\"" + INPUT + "\" bash ndc_derived_kpis.sh")
    print("")
    if total_packages > 1:
        print("  Or pick a specific package:")
        shown = 0
        for b in brands.values():
            for p in b["products"].values():
                for ndc11, pk in sorted(p["packages"].items()):
                    if shown >= 5:
                        break
                    print("    INPUT=\"" + pk["display"] + "\" bash ndc_lookup.sh   # " + pk["description"][:40])
                    shown += 1
                if shown >= 5:
                    break
            if shown >= 5:
                break
        if total_packages > 5:
            print("    ... (" + str(total_packages - 5) + " more packages)")
        print("")

elif INPUT_KIND == "package":
    print("  Run full analysis for this package:")
    print("    INPUT=\"" + INPUT + "\" bash ndc_source_matrix.sh")
    print("    INPUT=\"" + INPUT + "\" bash ndc_geo_matrix.sh")
    print("    INPUT=\"" + INPUT + "\" bash ndc_shortages.sh")
    print("")
    print("  Or zoom out to the product:")
    for b in brands.values():
        for ndc9, p in b["products"].items():
            print("    INPUT=\"" + p["product_ndc"] + "\" bash ndc_lookup.sh   # " + p["label"])
    print("")

print("")
ENDOFPYTHON
