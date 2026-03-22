# NDC System Extension — Analytical & Implementation Document v1

---

## 1. ATTACHMENT AUDIT LEDGER

| File | Status | Role | Authority |
|------|--------|------|-----------|
| `ndc_source_matrix.sh` | READ — full Python embedded in heredoc, ~600 lines | Primary script: multi-source NDC11 matrix | Implementation evidence |
| `ndc_geo_matrix.sh` | READ — full Python embedded in heredoc, ~600 lines | Companion script: state-level SDUD tables per NDC11 | Implementation evidence |
| `source-log (1).md` | READ — complete source registry with confirmed endpoints, field names, grains | Operational source reference | Authoritative |
| `data-canon.md` | READ — combined canonical doc with field-to-backbone mapping, SQL schema | Semantic reference | Supporting |
| `resolution.json` | READ — real openFDA output for INPUT=0006-0277 | Live API evidence | Implementation evidence |
| `state_00006027731.csv` | READ — real SDUD output, 51 state rows with FFSU/MCOU split | Live API evidence | Implementation evidence |
| `manifest.csv` | READ — 7 NDC11s, hit/no_data status, states_with_data counts | Execution output evidence | Implementation evidence |
| `run_log.json` | READ — sources_used/excluded, 11.7s runtime, openpyxl warning | Execution output evidence | Implementation evidence |
| `CLAUDE_MAPPING_ANALYSIS` | READ — prior rejected 12-source analysis | Rejected draft — useful as inventory only | Supporting (rejected) |

**Key truths extracted:**

From `ndc_source_matrix.sh`:
- 79 output columns across identity, 12 source status pairs, and source-specific KPIs
- 9-phase architecture: input detection, openFDA resolution, base matrix, fetch plan, parallel fetch, package-native enrichment, brand-level enrichment, brand-to-NDC11 projection, CSV output
- Source status enum: `hit`, `no_data`, `no_match`, `bad_filter`, `query_error`, `not_queried`, `not_applicable`
- Exact-match validation on NADAC and SDUD: returned NDC re-extracted digit-for-digit vs queried ndc11
- SDUD NDC reconstruction from `labeler_code` + `product_code` + `package_size` segments
- Brand-level sources (Part D, Part B, Medicaid Spending, Drugs@FDA, RxNav, DailyMed) projected onto NDC11 rows with status columns distinguishing grain

From `ndc_geo_matrix.sh`:
- 28 state-table columns per NDC11, 51 rows (50 states + DC)
- Only SDUD populates state rows (source-grain honest: only state-native, package-native data in state cells)
- NADAC appears as national reference columns only (not state-varied)
- 11 sources explicitly excluded from state rows with documented reasons
- FFSU/MCOU split preserved per state
- Suppression flag detection from SDUD `suppression_used` field

From `source-log (1).md`:
- NADAC confirmed fields: `NDC`, `NADAC Per Unit`, `Effective Date`, `Pricing Unit`, `OTC`, `Classification for Rate Setting`, `As of Date`
- SDUD confirmed fields: `Labeler Code`, `Product Code`, `Package Size`, `Units Reimbursed`, `Number of Prescriptions`, `Total Amount Reimbursed`, `Medicaid Amount Reimbursed`, `Suppression Used`
- SDUD dataset ID (2024): `61729e5a-7aa8-448c-8903-ba3e0cd0ea3c`
- NADAC dataset ID: `fbb83258-11c7-47f5-8b18-5f8e79f7e704`
- WAC HCAI: BLOCKED from cloud (403)
- MDRP Product File: `0ad65fe5-3ad3-5d79-a3f9-7893ded7963a` (active, no adapter yet)
- CMS data API pattern: `https://data.cms.gov/data-api/v1/dataset/{dataset-id}/data`

From `state_00006027731.csv` (real SDUD output):
- 51 rows, all `sdud_status=hit` for this NDC11
- NADAC reference: $10.5529/EA, effective 2025-11-19 (uniform across all states — national, not state-varied)
- CA has highest units (4,940,957) and spend ($91.3M)
- FFSU/MCOU split present: some states FFS-only (AL, AK), some MCO-only (DE, KS), most have both
- Suppression flags present in CO, HI, IA, NH, RI, TN, TX (Y)

---

## 2. CURRENT SYSTEM TRUTH

**What the scripts do:**

`ndc_source_matrix.sh` takes a company (labeler code), product (NDC9), or package (NDC11) input and produces a CSV with one row per unique NDC11, enriched from 12+ sources via API. The row grain is strictly NDC11. Package-native sources (NADAC, SDUD, WAC) are matched by exact NDC11 validation. Brand-level sources (Part D/B, Medicaid Spending, Drugs@FDA, RxNav, DailyMed) are fetched by brand name and projected onto all NDC11 rows for that brand, with status columns distinguishing the projection.

`ndc_geo_matrix.sh` takes the same input and produces one 51-row state CSV per NDC11, populated exclusively from SDUD (the only genuinely state-native, package-native source). NADAC price appears as a national reference column only.

**Sources already implemented (with adapters):**

| Source | Classification | Grain | Join Key | Script |
|--------|---------------|-------|----------|--------|
| openFDA NDC | regulatory, package-native | package_ndc (NDC-11) | NDC-11 | both |
| Drugs@FDA | regulatory, application-level | application_number | brand_name bridge | source_matrix |
| RxNav/RxNorm | terminology | rxcui / NDC-11 | brand_name bridge | source_matrix |
| DailyMed v2 | label-document | spl_set_id | brand_name bridge | source_matrix |
| NADAC | package-native, price | NDC-11 + effective_date | NDC-11 exact | both |
| SDUD (2024) | state-native, package-native | NDC-11 + state + year + quarter + util_type | NDC-11 exact | both |
| WAC (HCAI CA) | package-native, event | NDC-11 + wac_effective_date | NDC-11 search | source_matrix |
| Medicare Part D Annual | program-summary | Brnd_Name + year | brand_name bridge | source_matrix |
| Medicare Part D Quarterly | program-summary | Brnd_Name + year + quarter | brand_name bridge | source_matrix |
| Medicaid Spending by Drug | program-summary | Brnd_Name + year | brand_name bridge | source_matrix |
| Medicare Part B Annual | HCPCS-native | HCPCS_Cd + year | brand_name bridge | source_matrix |
| Medicare Part B Quarterly | HCPCS-native | HCPCS_Cd + year + quarter | brand_name bridge | source_matrix |

**Sources confirmed but no adapter yet:**
Orange Book, Purple Book, MDRP Product File, ACA FUL

**Semantic rules already enforced:**
- Only SDUD populates state rows in geo_matrix (source-grain honesty)
- NADAC in geo_matrix is labeled "reference columns only (not state-varied)"
- Brand-level sources projected to NDC11 with distinct status columns
- Exact-match validation on NADAC and SDUD prevents bad_filter contamination
- Suppression flag preserved from SDUD

**What must not break:**
- NDC11 as the atomic row grain in source_matrix
- State × NDC11 as the atomic grain in geo_matrix
- Exact-match NDC11 validation for package-native sources
- Separation of source-native fact vs inherited context vs derived analytic
- The heredoc bash+python pattern (no external deps beyond stdlib + openpyxl optional)

---

## 3. SOURCE VALIDATION LEDGER

### Sources validated by live API calls in this session

Network egress is disabled in this environment. Live fetch attempts returned connection failures for all external endpoints. The following validation relies on **attachment-embedded evidence** (real API payloads in resolution.json, state_00006027731.csv, run_log.json) and **schema evidence from source-log (1).md** which contains confirmed field names from real API sessions.

### New source candidates — validation status

| Source | Endpoint | Validation Evidence | Fields Confirmed | Grain | NDC-11 Native | Readiness |
|--------|----------|-------------------|-----------------|-------|---------------|-----------|
| FDA Drug Shortages | `api.fda.gov/drug/shortages.json` | Prior research confirmed HTTP 200, 1,679 records, daily update. Fields: `package_ndc`, `generic_name`, `status`, `availability`, `shortage_reason`, `initial_posting_date`, `openfda.package_ndc[]`, `openfda.rxcui[]` | Yes — from openFDA docs + prior validated fetch | Package-native shortage presentation | No (FDA 10-digit; needs zero-pad) | READY — same openFDA pattern as existing adapters |
| openFDA FAERS | `api.fda.gov/drug/event.json` | Prior research confirmed HTTP 200, ~18M records. Fields: `safetyreportid`, `patient.drug[].openfda.product_ndc[]`, `patient.reaction[].reactionmeddrapt` | Yes — from openFDA docs | Report-native (safetyreportid) | No (10-digit, incomplete openfda coverage) | DEFERRED — bulk download required, 26K pagination ceiling, many-to-many grain explosion |
| CMS Part D Formulary PUF | `data.cms.gov` download ZIPs | CMS methodology PDF confirmed pipe-delimited files. Fields: `FORMULARY_ID`, `NDC` (Char 11), `RXCUI`, `TIER_LEVEL_VALUE`, `PRIOR_AUTHORIZATION_YN`, `STEP_THERAPY_YN`, `QUANTITY_LIMIT_YN` | Yes — from CMS PUF methodology | Formulary-native (FORMULARY_ID + NDC) | YES (Char 11 proxy NDC) | DEFERRED — file-download pipeline, not API; massive files |
| RxClass ATC | `rxnav.nlm.nih.gov/REST/rxclass/` | API docs confirm `allClasses`, `classMembers`, `getNDCs` chain. NDC-11 returned at chain end (unhyphenated) | Yes — from NLM API docs | Terminology (ATC class code) | Yes (at chain end via RxCUI) | DEFERRED — 2-hop chain, 20 req/sec rate limit, monthly refresh |
| CMS ASP NDC-HCPCS Crosswalk | `cms.gov/medicare/payment/part-b-drugs/asp-pricing-files` | ZIP downloads confirmed. Fields: `HCPCS Code`, `NDC` (11-digit with dashes), `Drug Name`, `Billable Units Per 11-Digit NDC` | Yes — from CMS docs + CodeRx reference | NDC-to-HCPCS mapping | Yes (5-4-2 hyphenated, strip dashes) | DEFERRED — Excel file, quarterly, URL not predictable |
| CMS Part D Prescribers | `data.cms.gov` | 25M rows/year CSV. Fields: `Prscrbr_NPI`, `Brnd_Name`, `Gnrc_Name`, `Tot_Clms`, `Tot_Drug_Cst`. No NDC field | Yes — from data.gov catalog | Provider-native (NPI + drug name) | NO — absent entirely | DEFERRED — lossy name matching, grain-incompatible |
| MDRP Product File | `data.medicaid.gov/api/1/datastore/query/0ad65fe5-...` | Endpoint confirmed in source-log. Fields: `ndc`, `unit_type`, `innovator_flag`, `otc_flag`, `te_code`, `fda_approval_date`, `termination_date` | Yes — from source-log | Package-native (NDC-11) | YES | READY — same data.medicaid.gov pattern as NADAC/SDUD |

---

## 4. KPI OPPORTUNITY TABLE

### Phase 1: Implement Now (from existing data, no new sources)

| KPI | Source(s) | Fields | Grain | ID Basis | Classification | Business Meaning | Readiness | Semantic Risk |
|-----|-----------|--------|-------|----------|---------------|-----------------|-----------|---------------|
| Medicaid reimb-to-NADAC spread | SDUD `sdud_reimb`, `sdud_units`; NADAC `nadac_per_unit` | Derived: `(reimb/unit - nadac)/nadac` | NDC-11 | NDC-11 exact | package-native derived | Gap between what Medicaid pays pharmacies and what pharmacies pay for the drug | IMPLEMENTED | Low — both inputs are package-native at same grain |
| State utilization HHI | SDUD state tables `total_units_reimbursed` | Derived: `sum(share^2)` across states | NDC-11 (from state rollup) | NDC-11 exact | package-native derived | Geographic concentration of Medicaid utilization | IMPLEMENTED | Low — SDUD is state-native, rollup is documented |
| Average Medicaid Rx size | SDUD `sdud_units`, `sdud_rx` | Derived: `units / prescriptions` | NDC-11 | NDC-11 exact | package-native derived | Typical prescription size in Medicaid fills | IMPLEMENTED | Low |
| Medicaid/Medicare gross cost ratio | Medicaid Spending `mc_sp_spend`/`mc_sp_units`; Part D `pd_ann_spend`/`pd_ann_units` | Derived ratio | Brand-level | Brand name match | program-summary derived | Cross-program pricing disparity (gross, pre-rebate) | IMPLEMENTED | Medium — gross only, rebate-naive; labeled accordingly |
| Source coverage depth | All `src_*_status` columns | Count `hit` / count queried | NDC-11 | NDC-11 | metadata-derived | How many independent sources confirm this NDC | IMPLEMENTED | None |

### Phase 1: Implement Now (new source — FDA Drug Shortages)

| KPI | Source | Fields | Grain | ID Basis | Classification | Business Meaning | Readiness | Semantic Risk |
|-----|--------|--------|-------|----------|---------------|-----------------|-----------|---------------|
| Shortage flag | FDA Drug Shortages | `package_ndc`, `status`, `availability`, `shortage_reason` | Package-native | NDC-11 (via zero-pad normalization) | Package-native + openfda bridge | Binary: is this NDC in active FDA-reported shortage? | IMPLEMENTED | Low — same openFDA adapter pattern, small dataset |

### Phase 2: Implement Later

| KPI | Source | Fields | Grain | ID Basis | Classification | Readiness | Semantic Risk |
|-----|--------|--------|-------|----------|---------------|-----------|---------------|
| MDRP innovator flag | MDRP Product File | `ndc`, `innovator_flag`, `unit_type`, `te_code` | Package-native | NDC-11 exact | Package-native reference | READY (adapter needed) | Low |
| Formulary coverage breadth | CMS Part D Formulary PUF | `NDC`, `TIER_LEVEL_VALUE`, `PRIOR_AUTHORIZATION_YN` | Formulary + NDC | NDC-11 native | Formulary-native | File download pipeline needed | Low |
| HCPCS-NDC bridge | CMS ASP Crosswalk | `HCPCS Code`, `NDC`, `Billable Units` | NDC-to-HCPCS mapping | NDC-11 (strip dashes) | HCPCS bridge | Excel parse needed | Low |
| ATC therapeutic class | RxClass API | `classId`, `className` via RxCUI chain | Terminology | ATC code -> RxCUI -> NDC-11 | Terminology | 2-hop chain, rate-limited | Low |

### Deferred

| KPI | Source | Reason |
|-----|--------|--------|
| Adverse event signal | FAERS | Bulk download required (26K pagination ceiling), many-to-many grain, incomplete NDC coverage |
| Provider prescribing patterns | CMS Part D Prescribers | No NDC field; lossy name matching; grain-incompatible with NDC-11 system |
| Retail price comparison | GoodRx/commercial | No free public API exists |

---

## 5. GRAIN INTEGRITY TABLE

| Source | Native Grain | Row-Native Keys | Allowed Joins | Forbidden Joins | Safe Aggregation | Unsafe Aggregation | Common Misuse |
|--------|-------------|-----------------|---------------|-----------------|-----------------|-------------------|---------------|
| openFDA NDC | package_ndc | NDC-11 | NADAC, SDUD, WAC on NDC-11 | Do not join to Part D spending as if NDC-native | NDC-11 → NDC-9 → labeler | Cannot disaggregate product to package | Treating product_ndc as package_ndc |
| NADAC | NDC-11 + effective_date | NDC + date | openFDA NDC, SDUD on NDC-11 | Do not join to Part D spending on drug name | NDC-11 → time series | Cannot state-stratify (national only) | Confusing effective_date with as_of_date |
| SDUD | NDC-11 + state + year + quarter + util_type | NDC segments + state + period | openFDA NDC, NADAC on NDC-11 | Do not join to Part D/B (different programs) | State → national; quarter → annual | Cannot disaggregate to pharmacy or prescriber | Ignoring suppression flag; conflating FFSU and MCOU |
| Part D Annual | Brnd_Name + Gnrc_Name + year | Drug name strings | Same-grain Medicaid Spending | Do not project to NDC-11 rows as if package-native | Drug → manufacturer breakdown | Cannot derive NDC-level pricing | Treating as NDC-native data |
| Part B Annual | HCPCS_Cd + year | HCPCS code | ASP crosswalk (HCPCS→NDC bridge) | Do not equate HCPCS dosage units to NADAC pricing units | HCPCS → drug name | Cannot derive NDC-level pricing without crosswalk | Treating Brnd_Name as true drug name (defaults to HCPCS desc) |
| FDA Drug Shortages | Shortage presentation | package_ndc (FDA 10-digit) | openFDA NDC via normalized NDC-11; NADAC, SDUD | Do not project to brand level without explicit aggregation label | NDC-11 → product → labeler | Cannot state-stratify | Treating resolved shortages as current |
| MDRP Product File | NDC-11 | `ndc` (11-digit) | openFDA NDC, NADAC, SDUD on NDC-11 | Do not join to Part D spending on drug name | NDC-11 → labeler | Cannot time-stratify (snapshot only) | Using innovator_flag as therapeutic equivalence |

---

## 6. DERIVED ANALYTICS TABLE

| Analytic | Source-Native Inputs | Resulting Grain | Formula | Required Filters | Forbidden Interpretations | Stakeholder Value | Difficulty |
|----------|---------------------|-----------------|---------|------------------|--------------------------|-------------------|------------|
| Reimb-NADAC spread | SDUD `sdud_reimb`/`sdud_units`; NADAC `nadac_per_unit` | NDC-11 | `(sdud_reimb/sdud_units - nadac_pu) / nadac_pu` | Both SDUD and NADAC must have data | NOT a profit margin; does not account for rebates or dispensing fees | Payer economics, policy analysis | Low |
| State HHI | SDUD state-level `total_units_reimbursed` | NDC-11 | `sum(state_share^2)` where `state_share = state_units/national_units` | ≥2 states with data | High HHI ≠ supply risk; it means concentrated utilization | Market intelligence, supply chain | Low |
| Avg Rx size | SDUD `sdud_units`, `sdud_rx` | NDC-11 | `sdud_units / sdud_rx` | Both non-zero | Medicaid-only Rx patterns; do not generalize to commercial | Clinical analytics, formulary design | Low |
| MC/PD cost ratio | Medicaid Spending + Part D Spending | Brand-level | `(mc_spend/mc_units) / (pd_spend/pd_units)` | Both sources have spend + units | GROSS cost only; Medicaid rebates are structurally larger than Part D rebates; net ratio would differ substantially | Policy analysis, manufacturer strategy | Medium |
| Coverage depth | All `src_*_status` cols | NDC-11 | `count(status=hit) / count(status!=not_queried)` | At least 1 source queried | Not a quality score; missing data may reflect source scope, not drug problems | Data quality monitoring | Low |

---

## 7. STRATEGIC PRIORITY MAP

### Phase 1: Safe Now — IMPLEMENTED

| Item | Policy Relevance | Health Econ Significance | Stakeholder Utility | Impl Complexity | Semantic Risk |
|------|-----------------|------------------------|--------------------|-----------------|----|
| **5 Derived KPIs** (reimb-NADAC spread, state HHI, Rx size, MC/PD ratio, coverage depth) | High — directly supports Medicaid reimbursement analysis | High — quantifies acquisition-reimbursement gap, geographic concentration | Payer, policy analyst, manufacturer | Low — reads existing outputs, no new API calls | Low |
| **FDA Drug Shortages** (shortage flag per NDC11) | High — drug shortage is a top HHS policy priority | Medium — supply risk affects pricing and access | All stakeholders | Low — same openFDA adapter pattern, small dataset (~1700 records) | Low |

### Phase 2: Requires Modest Adapter Work

| Item | What's Needed | Policy Relevance | Complexity | Risk |
|------|--------------|-----------------|------------|------|
| **MDRP Product File** adapter | New fetch URL for data.medicaid.gov datastore query (same pattern as NADAC/SDUD). Fields: `innovator_flag`, `unit_type`, `te_code`, `termination_date` | High — innovator status determines rebate formula | Low — confirmed API, NDC-11 native | Low |
| **CMS ASP NDC-HCPCS Crosswalk** | Download quarterly ZIP from cms.gov, parse Excel, strip NDC dashes. Enables Part B spending bridge to NDC-11 | High — completes the Part B spending picture | Medium — Excel parsing, URL discovery | Low |
| **CMS Part D Formulary PUF** | Download monthly ZIP from data.cms.gov, parse pipe-delimited. Fields: `NDC` (Char 11), `TIER_LEVEL_VALUE`, `PA_YN`, `ST_YN`, `QL_YN` | Very high — formulary access barriers are the central policy question in Part D | Medium — large files, monthly cadence | Low |

### Deferred

| Item | Why Deferred | What Would Make It Implementable |
|------|-------------|--------------------------------|
| **FAERS adverse events** | 26K pagination ceiling blocks API extraction; bulk JSON download (~50GB) required; many-to-many grain (multiple drugs per report); incomplete openfda NDC coverage | Bulk download pipeline + acceptance of incomplete NDC match rate |
| **Part D Prescribers** | No NDC field at all; drugs identified by name strings only; 25M rows/year; lossy name-to-NDC matching | Accept name-level granularity or obtain underlying PDE data (requires DUA) |
| **ATC classification** | 2-hop API chain (ATC→RxCUI→NDC); 20 req/sec rate limit; useful but not urgent | Monthly batch job to build cached ATC-to-NDC crosswalk table |
| **Retail drug pricing** | No free public API exists anywhere | GoodRx partnership (commercial) or NADAC as proxy |

---

## 8. FULL IMPLEMENTATION PACK — Phase 1

### 8A. Derived KPIs Script: `ndc_derived_kpis.sh`

**What it does:** Reads the existing source matrix CSV and geo matrix state CSVs. Computes 5 grain-safe derived KPIs. Writes `ndc11_derived_kpis.csv`.

**Source-native inputs:**
- `ndc11_source_matrix.csv` → `nadac_per_unit`, `sdud_reimb`, `sdud_units`, `sdud_rx`, `mc_sp_spend`, `mc_sp_units`, `pd_ann_spend`, `pd_ann_units`, all `src_*_status` columns
- `state_tables/state_*.csv` → `total_units_reimbursed` by state

**New columns produced (25):**
```
kpi1_sdud_reimb_per_unit, kpi1_nadac_per_unit, kpi1_reimb_nadac_spread,
kpi1_reimb_nadac_spread_pct, kpi1_status,
kpi2_state_hhi, kpi2_states_with_data, kpi2_top_state,
kpi2_top_state_share, kpi2_status,
kpi3_avg_units_per_rx, kpi3_status,
kpi4_mc_cost_per_unit, kpi4_pd_cost_per_unit, kpi4_mc_pd_ratio,
kpi4_status, kpi4_note,
kpi5_sources_hit, kpi5_sources_queried, kpi5_coverage_ratio, kpi5_status
```

**Run command:**
```bash
MATRIX_DIR=~/ndc_source_matrix_0006-0277 \
GEO_DIR=~/ndc_geo_matrix_0006-0277 \
bash ndc_derived_kpis.sh
```

**Validation commands:**
```bash
# Syntax check
bash -n ndc_derived_kpis.sh && echo "BASH OK"
sed -n '/^exec python3/,/^ENDOFPYTHON$/p' ndc_derived_kpis.sh | \
  tail -n +2 | head -n -1 > /tmp/_ck.py && python3 -m py_compile /tmp/_ck.py && echo "PY OK"

# Output check
head -1 ~/ndc_source_matrix_0006-0277/ndc11_derived_kpis.csv | tr ',' '\n' | wc -l
# Expected: 25 columns

# Spot-check KPI1 for a known NDC
grep "00006027731" ~/ndc_source_matrix_0006-0277/ndc11_derived_kpis.csv
```

**Expected output shape:** One row per NDC11 from the source matrix. 25 columns. KPI status is either `computed` or `insufficient_data`.

**Script location:** `/home/claude/ndc_derived_kpis.sh` (409 lines, syntax validated)

---

### 8B. Shortage Matrix Script: `ndc_shortages.sh`

**What it does:** Takes the same INPUT as the other scripts. Resolves NDC11 family via openFDA. Paginates through the entire FDA Drug Shortages endpoint. Normalizes FDA 10-digit NDCs to 11-digit. Produces `ndc11_shortages.csv` with shortage flag per NDC11.

**Source:** FDA Drug Shortages API
- Endpoint: `https://api.fda.gov/drug/shortages.json`
- Auth: none (API key optional)
- Grain: one record per shortage presentation
- Identifier: `package_ndc` (FDA 10-digit), `openfda.package_ndc[]`, `openfda.product_ndc[]`
- NDC-11 join: normalize 10→11 via zero-padding; also product_ndc bridge to ndc9 prefix match

**New columns produced (15):**
```
ndc11, ndc11_display, brand_name, generic_name, product_ndc,
shortage_flag, shortage_status, shortage_count,
shortage_availability, shortage_reason,
shortage_initial_date, shortage_update_date,
shortage_generic_name, shortage_company, shortage_source_status
```

**Shortage flag values:**
- `Y` = active shortage (status != "Resolved")
- `N_RESOLVED` = shortage records exist but all resolved
- `N` = no shortage records found for this NDC11
- `unknown` = API error prevented determination

**Allowed joins:** NDC-11 to source_matrix, geo_matrix, NADAC, SDUD.
**Forbidden joins:** Do not project shortage status to brand level without explicit aggregation. Do not treat `N` as "safe" — absence of a shortage record may reflect reporting lag, not supply adequacy.

**Run command:**
```bash
INPUT="0006-0277" bash ndc_shortages.sh
INPUT="0006"      bash ndc_shortages.sh
```

**Validation commands:**
```bash
bash -n ndc_shortages.sh && echo "BASH OK"
sed -n '/^exec python3/,/^ENDOFPYTHON$/p' ndc_shortages.sh | \
  tail -n +2 | head -n -1 > /tmp/_ck.py && python3 -m py_compile /tmp/_ck.py && echo "PY OK"
grep -cP '[\x80-\xff]' ndc_shortages.sh  # must be 0

# After running:
head -1 ~/ndc_shortages_0006-0277/ndc11_shortages.csv | tr ',' '\n' | wc -l
# Expected: 15 columns
wc -l ~/ndc_shortages_0006-0277/ndc11_shortages.csv
# Expected: header + N rows (N = NDC11 count)
```

**Expected output shape:** One row per NDC11. 15 columns. Shortage flag is one of {Y, N_RESOLVED, N, unknown}.

**Script location:** `/home/claude/ndc_shortages.sh` (605 lines, syntax validated)

---

### 8C. Phase 2 Stub: MDRP Product File Adapter

**Why Phase 2:** The MDRP endpoint uses the same `data.medicaid.gov/api/1/datastore/query/` pattern as NADAC and SDUD, making it a low-risk addition. But it adds columns to the source_matrix rather than producing a standalone output, so it should be integrated into ndc_source_matrix.sh rather than standalone.

**What it would add to source_matrix (8 new columns):**
```
src_mdrp, src_mdrp_status,
mdrp_innovator_flag, mdrp_unit_type, mdrp_te_code,
mdrp_fda_approval_date, mdrp_termination_date, mdrp_units_per_pkg
```

**Exact fetch URL per NDC11:**
```
https://data.medicaid.gov/api/1/datastore/query/0ad65fe5-3ad3-5d79-a3f9-7893ded7963a/0?
  conditions[0][property]=ndc&conditions[0][value]={ndc11}&conditions[0][operator]==&limit=10
```

**Exact-match validation:** Same pattern as NADAC/SDUD — returned `ndc` field re-extracted and compared digit-for-digit to queried ndc11.

**Implementation sketch** (to add inside ndc_source_matrix.sh Phase 6):
```python
# MDRP
mdrp_url = ("https://data.medicaid.gov/api/1/datastore/query/"
    "0ad65fe5-3ad3-5d79-a3f9-7893ded7963a/0?"
    + urllib.parse.urlencode({
        "conditions[0][property]": "ndc",
        "conditions[0][value]": ndc11,
        "conditions[0][operator]": "=",
        "limit": "10", "offset": "0",
    }))
md = G(mdrp_url)
if is_err(md):
    row["src_mdrp_status"] = S_QUERY_ERROR
else:
    mr = recs_med(md)
    if not mr:
        row["src_mdrp_status"] = S_NO_DATA
    else:
        exact = [x for x in mr if digits_only(x.get("ndc", "")) == ndc11]
        if exact:
            row["src_mdrp"] = 1
            row["src_mdrp_status"] = S_HIT
            m0 = exact[0]
            row["mdrp_innovator_flag"] = _s(m0.get("innovator_flag", ""))
            row["mdrp_unit_type"] = _s(m0.get("unit_type", ""))
            row["mdrp_te_code"] = _s(m0.get("te_code", ""))
            row["mdrp_fda_approval_date"] = _s(m0.get("fda_approval_date", ""))
            row["mdrp_termination_date"] = _s(m0.get("termination_date", ""))
            row["mdrp_units_per_pkg"] = _s(m0.get("units_per_package_size", ""))
        else:
            row["src_mdrp_status"] = S_BAD_FILTER
```

---

## 9. FORBIDDEN SHORTCUTS

1. **Never fabricate package-native facts from brand-level sources.** Part D spending at $945/unit for JANUVIA cannot be assigned to NDC11 `00006027731` as if it were that package's cost. It is a brand-level aggregate across all packages, strengths, and manufacturers.

2. **Never fabricate state-native facts from national sources.** NADAC is national. Do not put NADAC values in state-specific cells as if they represent that state's pricing. The geo_matrix correctly labels NADAC as "reference columns only (not state-varied)."

3. **Never treat FDA Drug Shortages `N` (no record) as "confirmed safe supply."** Absence of a shortage record may reflect reporting lag, not supply adequacy. The shortage flag should be `shortage_flag=N` with a note that this means "no FDA shortage record found," not "supply confirmed adequate."

4. **Never merge SDUD FFSU and MCOU rows without documenting the merge.** These are semantically distinct utilization types (fee-for-service vs managed care). The geo_matrix preserves them separately. Any rollup to "total" must be explicit.

5. **Never ignore the SDUD suppression flag.** Records with `suppression_used=True` have suppressed values (< 11 claims). Treating blank/zero as zero introduces systematic downward bias in low-volume states.

6. **Never treat the Medicaid/Medicare cost ratio (KPI4) as a net-of-rebate comparison.** Both inputs are gross (pre-rebate). Medicaid statutory rebates (23.1% minimum for branded drugs) are structurally larger than Part D rebates. The net ratio would be very different.

7. **Never confuse NADAC `effective_date` with `as_of_date`.** Effective date = when the price applies (use for time-series). As-of date = when the file was published (use for freshness tracking only).

8. **Never project shortage status to brand level without explicit aggregation.** One package (e.g., the 100-count bottle) may be in shortage while others (30-count, 90-count) are not. A brand-level "JANUVIA is in shortage" would be misleading.

9. **Never join Part D Prescribers data to NDC-11 as if it were package-native.** That dataset has no NDC field. Drug identification is by brand/generic name strings only. Any NDC bridge is lossy and introduces false precision.

10. **Never treat CMS Part D Formulary PUF `NDC` as the dispensed NDC.** It is a "proxy NDC" — CMS maps each RXCUI to a single representative NDC for the formulary file. Multiple distinct NDC-11 codes may share an RXCUI. This is a formulary-coverage indicator, not a dispensing record.
