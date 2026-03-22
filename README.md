# U.S. Pharmaceutical NDC Intelligence System

A standalone, terminal-runnable toolkit for querying, cross-referencing, and analyzing U.S. pharmaceutical products at the 11-digit National Drug Code (NDC-11) package grain. The system pulls live data from 12+ federal public APIs and data portals, validates every record at the package level, and produces structured CSV outputs suitable for pricing analytics, Medicaid utilization analysis, geographic dispersion studies, and supply-risk monitoring.

No databases. No web apps. No repos. One input, one command, real answers.

---

## What This Project Does

A pharmaceutical analyst, policy researcher, or pricing operations team member types a single identifier — a labeler code, a product NDC, or a full package NDC — and gets back a complete dossier: every public data source that has anything to say about that drug, cross-referenced at the package level, with explicit source status tracking and grain-honest semantics.

The system answers questions like:

- What is the current NADAC acquisition cost for every package of JANUVIA?
- Which states have the highest Medicaid utilization for this specific NDC-11?
- Does Medicare Part D or Medicaid Spending data exist for this brand?
- Is this drug in active FDA shortage?
- What is the gap between what Medicaid reimburses pharmacies and what pharmacies pay to acquire the drug?
- How geographically concentrated is Medicaid utilization across states?

---

## Scripts

| Script | Purpose | Output |
|--------|---------|--------|
| `ndc_source_matrix.sh` | Multi-source NDC-11 matrix | One row per package, ~85 columns across 12 sources |
| `ndc_geo_matrix.sh` | State-level geographic analysis | One 51-row state table per NDC-11, SDUD-only |
| `ndc_shortages.sh` | FDA Drug Shortage flag enrichment | Shortage status per NDC-11 |
| `ndc_derived_kpis.sh` | Derived analytics from existing outputs | 5 computed KPIs per NDC-11 |

All scripts share the same interface:

```bash
INPUT="0006"          bash ndc_source_matrix.sh   # company scope (all Merck packages)
INPUT="0006-0277"     bash ndc_source_matrix.sh   # product scope (all JANUVIA 100mg packages)
INPUT="0006-0277-02"  bash ndc_source_matrix.sh   # package scope (single NDC-11)
```

The derived KPIs script reads existing outputs instead of calling APIs:

```bash
MATRIX_DIR=~/ndc_source_matrix_0006-0277 \
GEO_DIR=~/ndc_geo_matrix_0006-0277 \
bash ndc_derived_kpis.sh
```

---

## Data Sources

### Why These Sources

The U.S. pharmaceutical data environment is layered. No single source covers identity, pricing, utilization, and regulatory status. Each source occupies a specific grain (the level at which one row of data exists) and a specific role. The system uses 12+ sources because that is what it takes to build a complete picture while respecting what each source actually measures.

### Source Inventory

**Tier A — Identity & Regulatory** (who makes it, what is it, is it approved)

| Source | Endpoint | Grain | NDC-11 Native | Role |
|--------|----------|-------|---------------|------|
| openFDA NDC Directory | `api.fda.gov/drug/ndc.json` | package_ndc | Yes | Identity backbone: brand, generic, labeler, strength, dosage form, application number, SPL set ID, RxCUI |
| openFDA Drugs@FDA | `api.fda.gov/drug/drugsfda.json` | application_number | Via openfda block | Regulatory metadata: NDA/ANDA/BLA, sponsor, approval history |
| FDA Drug Shortages | `api.fda.gov/drug/shortages.json` | shortage presentation | Via zero-pad normalization | Active/resolved shortage status, reason, availability |

**Tier B — Concept & Terminology** (what is this drug in standardized terms)

| Source | Endpoint | Grain | NDC-11 Native | Role |
|--------|----------|-------|---------------|------|
| RxNav / RxNorm | `rxnav.nlm.nih.gov/REST/` | rxcui / NDC-11 | Yes (via ndcproperties) | NDC-to-RxCUI bridge, concept names, SBD term types |
| DailyMed v2 | `dailymed.nlm.nih.gov/dailymed/services/v2/` | spl_set_id | Via NDC list | SPL label documents, NDC-to-SPL mapping |

**Tier C — Price Benchmarks** (what does this drug cost)

| Source | Endpoint | Grain | NDC-11 Native | Role |
|--------|----------|-------|---------------|------|
| NADAC | `data.medicaid.gov` dataset `fbb83258-...` | NDC-11 + effective_date | Yes | Weekly national pharmacy acquisition cost per unit |
| WAC (CA HCAI) | `data.chhs.ca.gov` CKAN datastore | NDC-11 + wac_effective_date | Yes | Manufacturer-reported wholesale price increase events (California SB 17) |

**Tier D — Utilization & Spend** (how much is used, who pays)

| Source | Endpoint | Grain | NDC-11 Native | Role |
|--------|----------|-------|---------------|------|
| SDUD | `data.medicaid.gov` dataset `61729e5a-...` | NDC-11 + state + year + quarter + util_type | Yes | State-level Medicaid FFS + MCO claims, units, and reimbursement |
| Medicare Part D Annual | `data.cms.gov` dataset `7e0b4365-...` | Brnd_Name + year | No (brand-level) | Annual gross Part D spending by drug |
| Medicare Part D Quarterly | `data.cms.gov` dataset `4ff7c618-...` | Brnd_Name + year + quarter | No (brand-level) | Preliminary quarterly Part D spending |
| Medicaid Spending by Drug | `data.cms.gov` dataset `be64fce3-...` | Brnd_Name + year | No (brand-level) | Annual gross Medicaid spending by drug |
| Medicare Part B Annual | `data.cms.gov` dataset `76a714ad-...` | HCPCS_Cd + year | No (HCPCS-native) | Annual Part B physician-administered drug spending |
| Medicare Part B Quarterly | `data.cms.gov` dataset `bf6a5b3b-...` | HCPCS_Cd + year + quarter | No (HCPCS-native) | Preliminary quarterly Part B spending |

### Sources Documented But Not Yet Adapted

These are confirmed in `source-log.md` with endpoints, fields, and grain, but do not yet have script adapters:

- **MDRP Product File** — NDC-11 native, package-native reference (innovator flag, unit type, TE code, termination date). Endpoint: `data.medicaid.gov` dataset `0ad65fe5-...`
- **Orange Book** — Regulatory, application-level. Download-only ZIP from FDA. Patents, exclusivities, TE codes.
- **Purple Book** — Regulatory, BLA-level. No public API. Biologic reference products and biosimilar status.
- **ACA FUL** — NDC-level reimbursement ceiling. CSV download. Federal Upper Limits based on weighted AMP.

### Sources Evaluated and Deferred

These were evaluated for integration but deferred for documented reasons:

- **openFDA FAERS** (adverse events) — 26K pagination ceiling blocks API extraction; bulk download (~50GB) required; many-to-many grain (multiple drugs per report); incomplete NDC coverage.
- **CMS Part D Prescribers** — No NDC field; drugs identified by name strings only; lossy name-to-NDC matching; grain-incompatible.
- **CMS Part D Formulary PUF** — Native NDC-11, high value, but requires file-download pipeline and produces massive files. Strategically important for Phase 2.
- **CMS ASP NDC-HCPCS Crosswalk** — Native NDC-11 in crosswalk file, would complete the Part B bridge. Requires Excel parsing and quarterly URL discovery.
- **RxClass ATC** — Therapeutic classification via 2-hop API chain (ATC→RxCUI→NDC-11). Rate-limited at 20 req/sec. Useful for market segmentation but not urgent.
- **GoodRx / retail pricing** — No free public API exists.

---

## Data Dictionary

### Source Matrix Output (`ndc11_source_matrix.csv`)

**Identity Columns** (from openFDA NDC)

| Column | Type | Description |
|--------|------|-------------|
| `ndc11` | string(11) | Normalized 11-digit NDC. Primary row key. |
| `ndc11_display` | string | Human-readable 5-4-2 hyphenated form (e.g., `00006-0277-31`) |
| `package_ndc_source` | string | Original package NDC string from openFDA before normalization |
| `product_ndc` | string | Product-level NDC (labeler + product, typically 9 digits with dash) |
| `ndc9` | string(9) | Normalized 9-digit product code |
| `ndc6` | string(6) | First 6 digits of NDC-11 (labeler prefix + partial product) |
| `brand_name` | string | Proprietary/brand name |
| `generic_name` | string | Non-proprietary/generic name |
| `labeler_name` | string | Manufacturer/labeler |
| `dosage_form` | string | Dosage form (TABLET, INJECTION, etc.) |
| `route` | string | Administration route(s), pipe-delimited |
| `package_description` | string | Package size text (e.g., "30 TABLET in 1 BOTTLE") |
| `application_number` | string | FDA application number (NDA/ANDA/BLA) |
| `spl_setid` | string | SPL Set ID linking to DailyMed label |
| `rxcui` | string | RxNorm Concept Unique Identifier(s), pipe-delimited |
| `listing_expiration_date` | string | NDC listing expiration |
| `marketing_start_date` | string | Package marketing start date |
| `sample` | string | Sample package flag |

**Source Status Columns** (one pair per source)

Each source has a binary flag (`src_<name>` = 0 or 1) and a status string (`src_<name>_status`).

Status values: `hit` (data found and exact-match validated), `no_data` (source queried, nothing returned), `bad_filter` (source returned data but NDC did not match digit-for-digit), `query_error` (API call failed), `no_match` (brand-level source found records but none matched), `not_queried` (source not applicable or not called).

| Flag Column | Status Column | Source |
|-------------|---------------|--------|
| `src_nadac` | `src_nadac_status` | NADAC |
| `src_sdud` | `src_sdud_status` | SDUD |
| `src_wac_cur` | `src_wac_cur_status` | WAC Current |
| `src_wac_hist` | `src_wac_hist_status` | WAC History |
| `src_drugsfda` | `src_drugsfda_status` | Drugs@FDA |
| `src_rxnav` | `src_rxnav_status` | RxNav |
| `src_dailymed` | `src_dailymed_status` | DailyMed |
| `src_pd_ann` | `src_pd_ann_status` | Part D Annual |
| `src_pd_q` | `src_pd_q_status` | Part D Quarterly |
| `src_mc_sp` | `src_mc_sp_status` | Medicaid Spending |
| `src_pb_ann` | `src_pb_ann_status` | Part B Annual |
| `src_pb_q` | `src_pb_q_status` | Part B Quarterly |

**NADAC KPIs** (package-native, NDC-11 exact)

| Column | Description |
|--------|-------------|
| `nadac_eff_date` | Most recent NADAC effective date |
| `nadac_per_unit` | Acquisition cost per unit (the pricing fact) |
| `nadac_unit` | Pricing unit (EA, ML, GM) |
| `nadac_otc` | OTC flag (Y/N) |
| `nadac_class` | Classification for rate setting (B=brand, G=generic) |
| `nadac_count` | Number of NADAC records returned |

**SDUD KPIs** (package-native, state-aggregated to national)

| Column | Description |
|--------|-------------|
| `sdud_count` | Total SDUD records returned |
| `sdud_year` | Most recent year with data |
| `sdud_quarter` | Most recent quarter with data |
| `sdud_states` | Count of distinct states with utilization |
| `sdud_units` | Total units reimbursed (all states, all periods returned) |
| `sdud_rx` | Total prescriptions |
| `sdud_reimb` | Total Medicaid amount reimbursed |

**Program-Level KPIs** (brand-level, projected onto NDC-11 rows)

Part D Annual: `pd_ann_yr`, `pd_ann_spend`, `pd_ann_clm`, `pd_ann_ben`, `pd_ann_units`, `pd_ann_avg_u`, `pd_ann_avg_c`

Part D Quarterly: `pd_q_per`, `pd_q_spend`, `pd_q_clm`, `pd_q_ben`, `pd_q_avg_c`

Medicaid Spending: `mc_sp_yr`, `mc_sp_spend`, `mc_sp_clm`, `mc_sp_units`, `mc_sp_avg_u`

Part B Annual: `pb_ann_hcpcs`, `pb_ann_yr`, `pb_ann_spend`, `pb_ann_clm`, `pb_ann_ben`, `pb_ann_units`, `pb_ann_avg_u`

Part B Quarterly: `pb_q_hcpcs`, `pb_q_per`, `pb_q_spend`, `pb_q_clm`, `pb_q_ben`

### State Table Output (`state_<ndc11>.csv`)

One file per NDC-11. 51 rows (50 states + DC). Only SDUD populates state-level measures. NADAC appears as national reference only.

| Column | Source | State-Native? | Description |
|--------|--------|--------------|-------------|
| `state_code` | — | — | 2-letter state abbreviation |
| `state_name` | — | — | Full state name |
| `ndc11` | openFDA | — | Package identifier |
| `sdud_status` | SDUD | Yes | hit, no_data, bad_filter, query_error |
| `sdud_record_count` | SDUD | Yes | Records returned for this state |
| `latest_period` | SDUD | Yes | Most recent year+quarter (e.g., 2024Q4) |
| `period_count` | SDUD | Yes | Number of distinct quarters |
| `total_units_reimbursed` | SDUD | Yes | Combined FFSU + MCOU units |
| `total_prescriptions` | SDUD | Yes | Combined FFSU + MCOU Rx count |
| `total_amount_reimbursed` | SDUD | Yes | Total reimbursement (Medicaid + non-Medicaid) |
| `medicaid_amount_reimbursed` | SDUD | Yes | Medicaid-only reimbursement |
| `non_medicaid_amount_reimbursed` | SDUD | Yes | Non-Medicaid entity reimbursement |
| `ffsu_units` / `ffsu_prescriptions` / `ffsu_total_amount` | SDUD | Yes | Fee-for-service breakout |
| `mcou_units` / `mcou_prescriptions` / `mcou_total_amount` | SDUD | Yes | Managed care breakout |
| `suppression_flag_present` | SDUD | Yes | Y if any record had suppression_used=true |
| `nadac_latest_per_unit` | NADAC | No (national) | Reference: same for all states |
| `nadac_effective_date` | NADAC | No (national) | Reference: NADAC date |
| `nadac_pricing_unit` | NADAC | No (national) | Reference: EA/ML/GM |

### Derived KPIs Output (`ndc11_derived_kpis.csv`)

| Column | Formula | Grain | Inputs |
|--------|---------|-------|--------|
| `kpi1_reimb_nadac_spread_pct` | `(sdud_reimb/sdud_units - nadac_per_unit) / nadac_per_unit` | NDC-11 | SDUD + NADAC |
| `kpi2_state_hhi` | `sum(state_share^2)` across 51 jurisdictions | NDC-11 | SDUD state tables |
| `kpi3_avg_units_per_rx` | `sdud_units / sdud_rx` | NDC-11 | SDUD |
| `kpi4_mc_pd_ratio` | `(mc_spend/mc_units) / (pd_spend/pd_units)` | Brand-level | Medicaid Spending + Part D |
| `kpi5_coverage_ratio` | `count(status=hit) / count(queried)` | NDC-11 | All source statuses |

### Shortage Output (`ndc11_shortages.csv`)

| Column | Description |
|--------|-------------|
| `shortage_flag` | `Y` (active), `N_RESOLVED` (resolved), `N` (no record), `unknown` (API error) |
| `shortage_status` | FDA status string (Current, Resolved, etc.) |
| `shortage_availability` | Availability description |
| `shortage_reason` | Reason for shortage |
| `shortage_initial_date` | Date first posted |
| `shortage_update_date` | Most recent update |

---

## Methodology

### Input Resolution

The system accepts three input scopes and expands them to NDC-11 rows:

- **Company** (4-6 digits, e.g., `0006`): resolves all products and packages under that labeler via openFDA wildcard search on `product_ndc`. Matches by normalized 5-digit labeler prefix.
- **Product** (8-9 digits or hyphenated, e.g., `0006-0277`): resolves all packages under that product NDC. Uses product_ndc variant generation (handles 4-4, 5-3, 5-4 segment formats).
- **Package** (11 digits or 3-segment hyphenated, e.g., `0006-0277-31`): resolves exactly one NDC-11.

openFDA pagination with 0.15s inter-page sleep. Exact-match post-filtering ensures only the requested scope appears in output.

### Source Grain Discipline

The core methodological principle: never fabricate precision that the source does not provide.

- **Package-native sources** (NADAC, SDUD, WAC) are validated digit-for-digit. If the API returns NDC `00006027702` but we queried `00006027731`, the response is marked `bad_filter`, not `hit`. The SDUD NDC is reconstructed from `labeler_code` + `product_code` + `package_size` segments and compared to the queried NDC-11.

- **Brand-level sources** (Part D, Part B, Medicaid Spending) are fetched by brand name and projected onto all NDC-11 rows for that brand. The status columns (`src_pd_ann_status` etc.) distinguish this projection from package-native hits. The projected values are semantically honest: they represent the brand aggregate, not the specific package's share.

- **State-native sources** (SDUD only) populate the geographic tables. No national or program-summary source is spread across states. NADAC appears as a national reference column, explicitly labeled as not state-varied.

### Exact-Match Validation

For NADAC and SDUD, the system enforces a post-fetch validation step: the NDC returned in the API response is re-extracted, digit-stripped, and compared character-by-character to the queried NDC-11. This catches a real failure mode where Medicaid API `conditions` filters behave as prefix matches or return related-but-different NDCs. A mismatch produces `bad_filter` status, preventing contamination of the matrix with wrong-NDC data.

### Parallel Fetch with Caching

All HTTP calls go through `http_get_json()` which implements SHA-256 URL-keyed filesystem caching with configurable TTL (default 24 hours). Batch fetches use `ThreadPoolExecutor` bounded by `MAX_WORKERS` (default 8). Package-native and brand-level fetches are batched separately to maximize parallelism. This keeps a full company-scope run (100+ NDC-11s, 200+ API calls) under 30 seconds on a cached run and under 2 minutes cold.

### SDUD Utilization Type Handling

SDUD records come in two utilization types: FFSU (Fee-For-Service) and MCOU (Managed Care Organization). Both can exist for the same NDC + state + quarter. The geo matrix preserves the split (`ffsu_*` and `mcou_*` columns) alongside combined totals. MCO data is only available from 2010 onward per ACA requirements.

### Suppression Handling

SDUD suppresses records where fewer than 11 prescriptions were filled (HIPAA/Privacy Act). The system detects the `suppression_used` flag and surfaces it as `suppression_flag_present=Y` in state tables. Suppressed cells are left blank, not zero. This prevents systematic downward bias in low-volume state estimates.

### Derived KPI Methodology

All derived KPIs are computed from existing script outputs with no additional API calls. Each KPI documents its source-native inputs, resulting grain, exact formula, and forbidden interpretations.

The Medicaid reimb-to-NADAC spread is grain-safe because both SDUD (reimbursement per unit) and NADAC (acquisition cost per unit) operate at NDC-11 grain. The state HHI uses SDUD state-level units directly (SDUD is the only state-native, package-native source). The Medicaid/Medicare cost ratio operates at brand-level grain, matching the native grain of both input sources — no downward bridging to NDC-11 is attempted.

---

## Architecture

```
INPUT (company | product | package)
  |
  v
Phase 1: Input Detection & openFDA Family Resolution
  - detect_kind() -> company / product / package
  - openFDA paginated search with variant generation
  - exact-match post-filtering
  |
  v
Phase 2: NDC-11 Identity Map
  - one entry per unique normalized NDC-11
  - identity fields from openFDA (brand, generic, labeler, etc.)
  |
  v
Phase 3: Source Fetch Plan
  - package-native URLs keyed by NDC-11 (NADAC, SDUD, WAC)
  - brand-level URLs keyed by brand name (Part D, Part B, Medicaid Spending, etc.)
  |
  v
Phase 4: Parallel Fetch (ThreadPoolExecutor, SHA-256 cache)
  - batch 1: package-native sources
  - batch 2: brand-level sources
  |
  v
Phase 5-6: Enrichment
  - package-native: exact-match validated per NDC-11
  - brand-level: fetched per brand, projected onto all NDC-11 rows
  |
  v
Phase 7: Output
  - ndc11_source_matrix.csv (full matrix, ~85 columns)
  - ndc11_compact.csv (identity + key statuses)
  - resolution.json (scope metadata)
```

Each script is a single bash file wrapping embedded Python via `exec python3 - <<'ENDOFPYTHON'`. No external Python packages required beyond stdlib (openpyxl optional for Excel workbook generation). No databases, no config files, no environment setup beyond Python 3.6+.

---

## Project Files

```
ndc_source_matrix.sh       Main multi-source NDC-11 matrix
ndc_geo_matrix.sh          State-level geographic companion
ndc_shortages.sh           FDA Drug Shortage flag enrichment
ndc_derived_kpis.sh        Derived analytics from existing outputs
source-log.md              Operational source registry (endpoints, fields, grains, access status)
data-canon.md              Canonical semantic model (field-to-backbone mapping, schema, join rules)
ndc_system_extension_v1.md Analytical extension document (validation, KPI opportunities, grain integrity)
README.md                  This file
```

---

## Running

**Prerequisites:** Python 3.6+ and `bash`. No pip installs. No npm. No Docker. Optional: `openpyxl` for Excel workbook output in geo_matrix.

**Quick start:**

```bash
# Get full JANUVIA (product 0006-0277) package matrix
INPUT="0006-0277" bash ndc_source_matrix.sh

# Get state-level utilization for the same product
INPUT="0006-0277" bash ndc_geo_matrix.sh

# Check shortage status
INPUT="0006-0277" bash ndc_shortages.sh

# Compute derived KPIs from the above outputs
MATRIX_DIR=~/ndc_source_matrix_0006-0277 \
GEO_DIR=~/ndc_geo_matrix_0006-0277 \
bash ndc_derived_kpis.sh
```

**Syntax validation (run before first execution):**

```bash
bash -n ndc_source_matrix.sh && echo "BASH OK"
sed -n '/^exec python3/,/^ENDOFPYTHON$/p' ndc_source_matrix.sh \
  | tail -n +2 | head -n -1 > /tmp/_check.py \
  && python3 -m py_compile /tmp/_check.py && echo "PYTHON OK"
grep -cP '[\x80-\xff]' ndc_source_matrix.sh  # must print 0
```

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `INPUT` | `0006` | NDC input (company, product, or package) |
| `OPENFDA_API_KEY` | *(empty)* | Optional openFDA API key for higher rate limits |
| `MAX_WORKERS` | `8` | Thread pool size for parallel fetches |
| `CACHE_TTL_HOURS` | `24` | HTTP cache lifetime in hours |
| `INCLUDE_WAC` | `1` | Set to `0` to skip WAC (blocked from cloud) |
| `OUTDIR` | `~/ndc_<script>_<INPUT>/` | Override output directory |

---

## What This System Does Not Do

- It does not provide net-of-rebate pricing. All spending figures are gross (pre-rebate). CMS is legally prohibited from disclosing rebate amounts.
- It does not provide retail pharmacy prices. No free public API for retail pricing exists.
- It does not fabricate state-level data from national sources. If a source is national-only, it stays national.
- It does not bridge Part D spending to NDC-11 rows as if it were package-native. Part D spending is brand-level and is labeled as such.
- It does not impute suppressed SDUD values. Suppressed cells remain blank.
- It does not require any infrastructure beyond a terminal with Python 3.
