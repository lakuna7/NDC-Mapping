#!/usr/bin/env bash
set -euo pipefail

# ============================================================

# NDC DERIVED KPIs v1

# ============================================================

# Computes grain-safe derived analytics from EXISTING source

# matrix and geo matrix outputs. No new API calls.

# 

# Reads:

# - ndc11_source_matrix.csv (from ndc_source_matrix.sh)

# - state_tables/state_*.csv (from ndc_geo_matrix.sh)

# 

# Produces:

# - ndc11_derived_kpis.csv

# 

# Usage:

# MATRIX_DIR=~/ndc_source_matrix_0006-0277 \

# GEO_DIR=~/ndc_geo_matrix_0006-0277 \

# bash ndc_derived_kpis.sh

# ============================================================

MATRIX_DIR=”${MATRIX_DIR:-}”
GEO_DIR=”${GEO_DIR:-}”

if [ -z “$MATRIX_DIR” ] || [ -z “$GEO_DIR” ]; then
echo “Usage: MATRIX_DIR=<path> GEO_DIR=<path> bash ndc_derived_kpis.sh” >&2
echo “  MATRIX_DIR = output dir from ndc_source_matrix.sh” >&2
echo “  GEO_DIR    = output dir from ndc_geo_matrix.sh” >&2
exit 1
fi

export MATRIX_DIR GEO_DIR

exec python3 - <<‘ENDOFPYTHON’
import csv
import json
import math
import os
import sys
from pathlib import Path

MATRIX_DIR = Path(os.environ[“MATRIX_DIR”])
GEO_DIR = Path(os.environ[“GEO_DIR”])

def log(msg):
print(”[ndc-kpi] “ + str(msg), file=sys.stderr, flush=True)

def to_float(x):
try:
v = str(x).strip().replace(”,”, “”)
if not v:
return None
return float(v)
except Exception:
return None

def to_int(x):
try:
v = str(x).strip().replace(”,”, “”)
if not v:
return None
return int(float(v))
except Exception:
return None

def ff(x):
if x is None:
return “”
return “{:.4f}”.format(x)

def fi(x):
if x is None:
return “”
return str(int(x))

# ============================================================

# LOAD SOURCE MATRIX

# ============================================================

matrix_csv = MATRIX_DIR / “ndc11_source_matrix.csv”
if not matrix_csv.exists():
sys.exit(“Source matrix not found: “ + str(matrix_csv))

log(“Loading source matrix: “ + str(matrix_csv))
matrix_rows = []
with open(str(matrix_csv), “r”, encoding=“utf-8”) as fh:
reader = csv.DictReader(fh)
for row in reader:
matrix_rows.append(row)
log(”  “ + str(len(matrix_rows)) + “ NDC11 rows loaded”)

# ============================================================

# LOAD GEO STATE TABLES

# ============================================================

geo_state_dir = GEO_DIR / “state_tables”
geo_data = {}  # ndc11 -> list of state rows

if geo_state_dir.exists():
for csv_file in sorted(geo_state_dir.glob(“state_*.csv”)):
ndc11 = csv_file.stem.replace(“state_”, “”)
rows = []
with open(str(csv_file), “r”, encoding=“utf-8”) as fh:
reader = csv.DictReader(fh)
for row in reader:
rows.append(row)
geo_data[ndc11] = rows
log(”  “ + str(len(geo_data)) + “ state tables loaded”)
else:
log(”  No state tables found at “ + str(geo_state_dir))

# ============================================================

# KPI 1: MEDICAID REIMB-TO-NADAC SPREAD

# ============================================================

# Source-native inputs: SDUD (total_amount_reimbursed, units_reimbursed)

# NADAC (nadac_per_unit)

# Resulting grain: NDC-11 (national aggregate from SDUD state rows)

# Formula: (SDUD_reimb_per_unit - NADAC_per_unit) / NADAC_per_unit

# Required filter: Both SDUD and NADAC must have data for the NDC11

# Forbidden interpretation: This is NOT a profit margin. It is the gap

# between Medicaid reimbursement and pharmacy acquisition cost.

# Does not account for rebates, dispensing fees, or negotiated rates.

# ============================================================

log(“Computing KPI 1: Medicaid reimb-to-NADAC spread…”)

def compute_reimb_nadac_spread(row):
“”“From source matrix row. Returns dict of KPI fields.”””
nadac_pu = to_float(row.get(“nadac_per_unit”))
sdud_reimb = to_float(row.get(“sdud_reimb”))
sdud_units = to_float(row.get(“sdud_units”))

```
result = {
    "kpi1_sdud_reimb_per_unit": "",
    "kpi1_nadac_per_unit": "",
    "kpi1_reimb_nadac_spread": "",
    "kpi1_reimb_nadac_spread_pct": "",
    "kpi1_status": "insufficient_data",
}

if nadac_pu is None or nadac_pu <= 0:
    return result
result["kpi1_nadac_per_unit"] = ff(nadac_pu)

if sdud_reimb is None or sdud_units is None or sdud_units <= 0:
    return result

reimb_pu = sdud_reimb / sdud_units
result["kpi1_sdud_reimb_per_unit"] = ff(reimb_pu)

spread = reimb_pu - nadac_pu
spread_pct = spread / nadac_pu

result["kpi1_reimb_nadac_spread"] = ff(spread)
result["kpi1_reimb_nadac_spread_pct"] = ff(spread_pct)
result["kpi1_status"] = "computed"
return result
```

# ============================================================

# KPI 2: STATE UTILIZATION CONCENTRATION (HHI)

# ============================================================

# Source-native inputs: SDUD (units_reimbursed by state)

# Resulting grain: NDC-11 (one HHI per package)

# Formula: HHI = sum(state_share^2) where state_share = state_units / total_units

# Range: 1/51 ~ 0.0196 (perfectly even) to 1.0 (single state)

# Required filter: SDUD hit for at least 2 states

# Forbidden interpretation: High HHI does NOT mean supply risk.

# It means utilization is geographically concentrated.

# ============================================================

log(“Computing KPI 2: State utilization HHI…”)

def compute_state_hhi(ndc11):
“”“From geo state table. Returns dict of KPI fields.”””
result = {
“kpi2_state_hhi”: “”,
“kpi2_states_with_data”: “”,
“kpi2_top_state”: “”,
“kpi2_top_state_share”: “”,
“kpi2_status”: “insufficient_data”,
}

```
state_rows = geo_data.get(ndc11, [])
if not state_rows:
    return result

# Extract state-level units
state_units = {}
for sr in state_rows:
    sc = sr.get("state_code", "")
    if sr.get("sdud_status") != "hit":
        continue
    u = to_float(sr.get("total_units_reimbursed"))
    if u is not None and u > 0:
        state_units[sc] = u

if len(state_units) < 2:
    return result

total = sum(state_units.values())
if total <= 0:
    return result

shares = {sc: u / total for sc, u in state_units.items()}
hhi = sum(s * s for s in shares.values())

top_state = max(shares, key=shares.get)

result["kpi2_state_hhi"] = ff(hhi)
result["kpi2_states_with_data"] = str(len(state_units))
result["kpi2_top_state"] = top_state
result["kpi2_top_state_share"] = ff(shares[top_state])
result["kpi2_status"] = "computed"
return result
```

# ============================================================

# KPI 3: SDUD PRESCRIPTION SIZE

# ============================================================

# Source-native inputs: SDUD (units_reimbursed, number_of_prescriptions)

# Resulting grain: NDC-11 (national aggregate)

# Formula: avg_units_per_rx = total_units / total_prescriptions

# Required filter: Both fields non-zero

# Forbidden interpretation: This is average Medicaid Rx size only.

# Do not generalize to commercial or Medicare Rx patterns.

# ============================================================

log(“Computing KPI 3: SDUD average Rx size…”)

def compute_rx_size(row):
result = {
“kpi3_avg_units_per_rx”: “”,
“kpi3_status”: “insufficient_data”,
}
units = to_float(row.get(“sdud_units”))
rxs = to_float(row.get(“sdud_rx”))
if units is None or rxs is None or rxs <= 0:
return result
result[“kpi3_avg_units_per_rx”] = ff(units / rxs)
result[“kpi3_status”] = “computed”
return result

# ============================================================

# KPI 4: MEDICAID-MEDICARE SPENDING RATIO

# ============================================================

# Source-native inputs: Medicaid Spending (mc_sp_spend, mc_sp_units)

# Part D Spending (pd_ann_spend, pd_ann_units)

# Resulting grain: brand-level (both sources are program-summary)

# Formula: mc_cost_per_unit / pd_cost_per_unit

# Required filter: Both sources hit, both have spend + units

# Forbidden interpretation: This is GROSS cost ratio, not net-of-rebates.

# Medicaid rebates are much larger than Part D rebates, so the

# net ratio would be very different.

# ============================================================

log(“Computing KPI 4: Medicaid/Medicare spend ratio…”)

def compute_mc_pd_ratio(row):
result = {
“kpi4_mc_cost_per_unit”: “”,
“kpi4_pd_cost_per_unit”: “”,
“kpi4_mc_pd_ratio”: “”,
“kpi4_status”: “insufficient_data”,
“kpi4_note”: “gross_cost_only_no_rebate_adjustment”,
}
mc_sp = to_float(row.get(“mc_sp_spend”))
mc_un = to_float(row.get(“mc_sp_units”))
pd_sp = to_float(row.get(“pd_ann_spend”))
pd_un = to_float(row.get(“pd_ann_units”))

```
if mc_sp is None or mc_un is None or mc_un <= 0:
    return result
if pd_sp is None or pd_un is None or pd_un <= 0:
    return result

mc_cpu = mc_sp / mc_un
pd_cpu = pd_sp / pd_un

result["kpi4_mc_cost_per_unit"] = ff(mc_cpu)
result["kpi4_pd_cost_per_unit"] = ff(pd_cpu)
result["kpi4_mc_pd_ratio"] = ff(mc_cpu / pd_cpu) if pd_cpu > 0 else ""
result["kpi4_status"] = "computed"
return result
```

# ============================================================

# KPI 5: MULTI-SOURCE COVERAGE DEPTH

# ============================================================

# Source-native inputs: source_count and individual src_*_status fields

# Resulting grain: NDC-11

# Formula: count of sources with status=hit / total sources queried

# Meaning: How many independent data sources confirm this NDC exists

# ============================================================

log(“Computing KPI 5: Source coverage depth…”)

SRC_STATUS_COLS = [
“src_nadac_status”, “src_sdud_status”, “src_wac_cur_status”,
“src_wac_hist_status”, “src_drugsfda_status”, “src_rxnav_status”,
“src_dailymed_status”, “src_pd_ann_status”, “src_pd_q_status”,
“src_mc_sp_status”, “src_pb_ann_status”, “src_pb_q_status”,
]

def compute_coverage_depth(row):
hit = 0
queried = 0
for col in SRC_STATUS_COLS:
st = row.get(col, “not_queried”)
if st != “not_queried”:
queried += 1
if st == “hit”:
hit += 1
return {
“kpi5_sources_hit”: str(hit),
“kpi5_sources_queried”: str(queried),
“kpi5_coverage_ratio”: ff(hit / queried) if queried > 0 else “”,
“kpi5_status”: “computed” if queried > 0 else “insufficient_data”,
}

# ============================================================

# COMBINE AND WRITE OUTPUT

# ============================================================

log(“Assembling output…”)

ALL_KPI_COLS = [
“ndc11”, “ndc11_display”, “brand_name”, “generic_name”, “product_ndc”,
# KPI 1
“kpi1_sdud_reimb_per_unit”, “kpi1_nadac_per_unit”,
“kpi1_reimb_nadac_spread”, “kpi1_reimb_nadac_spread_pct”, “kpi1_status”,
# KPI 2
“kpi2_state_hhi”, “kpi2_states_with_data”,
“kpi2_top_state”, “kpi2_top_state_share”, “kpi2_status”,
# KPI 3
“kpi3_avg_units_per_rx”, “kpi3_status”,
# KPI 4
“kpi4_mc_cost_per_unit”, “kpi4_pd_cost_per_unit”,
“kpi4_mc_pd_ratio”, “kpi4_status”, “kpi4_note”,
# KPI 5
“kpi5_sources_hit”, “kpi5_sources_queried”,
“kpi5_coverage_ratio”, “kpi5_status”,
]

output_rows = []
for row in matrix_rows:
ndc11 = row.get(“ndc11”, “”)
out = {
“ndc11”: ndc11,
“ndc11_display”: row.get(“ndc11_display”, “”),
“brand_name”: row.get(“brand_name”, “”),
“generic_name”: row.get(“generic_name”, “”),
“product_ndc”: row.get(“product_ndc”, “”),
}
out.update(compute_reimb_nadac_spread(row))
out.update(compute_state_hhi(ndc11))
out.update(compute_rx_size(row))
out.update(compute_mc_pd_ratio(row))
out.update(compute_coverage_depth(row))
output_rows.append(out)

# Write

OUTDIR = MATRIX_DIR  # Co-locate with source matrix output
csv_path = OUTDIR / “ndc11_derived_kpis.csv”

with open(str(csv_path), “w”, newline=””, encoding=“utf-8”) as fh:
w = csv.DictWriter(fh, fieldnames=ALL_KPI_COLS, extrasaction=“ignore”)
w.writeheader()
for row in output_rows:
w.writerow({c: row.get(c, “”) for c in ALL_KPI_COLS})

log(“Output: “ + str(csv_path))

# Summary

print(””)
print(”=” * 70)
print(“NDC DERIVED KPIs v1 – COMPLETE”)
print(”=” * 70)
print(”  NDC11s             : “ + str(len(output_rows)))
print(””)

kpi_counts = {}
for kn in [“kpi1_status”, “kpi2_status”, “kpi3_status”, “kpi4_status”, “kpi5_status”]:
computed = sum(1 for r in output_rows if r.get(kn) == “computed”)
total = len(output_rows)
kpi_counts[kn] = (computed, total)
pct = (computed / total * 100) if total > 0 else 0
label = kn.replace(”_status”, “”).upper()
print(”  {:<8} computed: {:>4} / {:>4} ({:.0f}%)”.format(label, computed, total, pct))

print(””)
print(“KPI DEFINITIONS:”)
print(”  KPI1: Medicaid reimb-to-NADAC spread (SDUD reimb/unit - NADAC per unit)”)
print(”  KPI2: State utilization HHI (Herfindahl index across 51 jurisdictions)”)
print(”  KPI3: Average Medicaid Rx size (SDUD units / prescriptions)”)
print(”  KPI4: Medicaid/Medicare gross cost ratio (brand-level, no rebate adj)”)
print(”  KPI5: Source coverage depth (fraction of sources with hit status)”)
print(””)
print(“FILES:”)
print(”  “ + str(csv_path))
print(””)

# Preview

preview_cols = [“ndc11”, “brand_name”, “kpi1_reimb_nadac_spread_pct”, “kpi2_state_hhi”, “kpi3_avg_units_per_rx”, “kpi5_coverage_ratio”]
print(“PREVIEW:”)
print(”  “ + “ | “.join(”{:<18}”.format(c.replace(“kpi1_reimb_nadac_spread_pct”,“spread%”).replace(“kpi2_state_hhi”,“hhi”).replace(“kpi3_avg_units_per_rx”,“rx_size”).replace(“kpi5_coverage_ratio”,“coverage”)) for c in preview_cols))
print(”  “ + “-” * (20 * len(preview_cols)))
for r in output_rows[0:15]:
print(”  “ + “ | “.join(”{:<18}”.format(str(r.get(c, “”))[:16]) for c in preview_cols))
print(””)
ENDOFPYTHON