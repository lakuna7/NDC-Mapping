# NDC Intelligence System — Session Bootstrap

Read this file first. It contains everything needed to resume work on this project.

## System

Four standalone bash+python scripts that query 12+ U.S. federal pharmaceutical APIs and produce CSV outputs at NDC-11 (package) grain. No repos, no databases, no pip installs. Python 3.6+ only.

## Scripts

| Script | Purpose | Input | Output |
|--------|---------|-------|--------|
| `ndc_source_matrix.sh` | Multi-source package matrix | `INPUT="0006-0277"` | `ndc11_source_matrix.csv` (~85 cols), `ndc11_compact.csv`, `resolution.json` |
| `ndc_geo_matrix.sh` | State-level Medicaid utilization | `INPUT="0006-0277"` | One `state_<ndc11>.csv` per package (51 rows), `manifest.csv`, `run_log.json` |
| `ndc_shortages.sh` | FDA drug shortage flag | `INPUT="0006-0277"` | `ndc11_shortages.csv` |
| `ndc_derived_kpis.sh` | Derived analytics (no API calls) | `MATRIX_DIR=... GEO_DIR=...` | `ndc11_derived_kpis.csv` |

Input scopes: company (`0006`), product (`0006-0277`), package (`0006-0277-02`). Scripts resolve to all matching NDC-11 rows via openFDA.

## Implemented Sources

| Source | Endpoint | Grain | NDC-11 Native | Classification | Script |
|--------|----------|-------|---------------|----------------|--------|
| openFDA NDC | `api.fda.gov/drug/ndc.json` | package_ndc | Yes | regulatory | both |
| Drugs@FDA | `api.fda.gov/drug/drugsfda.json` | application_number | Via openfda | regulatory | source_matrix |
| RxNav/RxNorm | `rxnav.nlm.nih.gov/REST/` | rxcui | Via ndcproperties | terminology | source_matrix |
| DailyMed v2 | `dailymed.nlm.nih.gov/dailymed/services/v2/` | spl_set_id | Via NDC list | label-document | source_matrix |
| NADAC | `data.medicaid.gov` `fbb83258-...` | NDC-11 + effective_date | Yes | package-native price | both |
| SDUD (2024) | `data.medicaid.gov` `61729e5a-...` | NDC-11 + state + year + qtr + util_type | Yes | state-native, package-native | both |
| WAC (CA HCAI) | `data.chhs.ca.gov` CKAN | NDC-11 + wac_effective_date | Yes | package-native event | source_matrix |
| Part D Annual | `data.cms.gov` `7e0b4365-...` | Brnd_Name + year | No | program-summary | source_matrix |
| Part D Quarterly | `data.cms.gov` `4ff7c618-...` | Brnd_Name + year + qtr | No | program-summary | source_matrix |
| Medicaid Spending | `data.cms.gov` `be64fce3-...` | Brnd_Name + year | No | program-summary | source_matrix |
| Part B Annual | `data.cms.gov` `76a714ad-...` | HCPCS_Cd + year | No | HCPCS-native | source_matrix |
| Part B Quarterly | `data.cms.gov` `bf6a5b3b-...` | HCPCS_Cd + year + qtr | No | HCPCS-native | source_matrix |
| FDA Drug Shortages | `api.fda.gov/drug/shortages.json` | shortage presentation | Via zero-pad | package-native | shortages |

## Source Status Semantics

Every source gets a status column: `hit` (data found, NDC exact-matched), `no_data` (queried, nothing returned), `bad_filter` (returned data but NDC mismatch digit-for-digit), `query_error` (API failed), `no_match` (brand-level source found records but none matched), `not_queried`.

NADAC and SDUD enforce exact-match validation: the NDC in the API response is re-extracted and compared character-by-character to the queried NDC-11.

## Output Column Groups

Source matrix: identity (18 cols: ndc11, brand, generic, labeler, dosage, route, package_description, application_number, spl_setid, rxcui, etc.), source flags (12 pairs of src_X / src_X_status), NADAC KPIs (6), SDUD KPIs (7), WAC KPIs (4), Part D Annual (7), Part D Quarterly (5), Medicaid Spending (5), Part B Annual (7), Part B Quarterly (5).

State tables: 28 cols. State-native measures from SDUD only (units, prescriptions, reimbursement, FFSU/MCOU split, suppression). NADAC as national reference (same value all states).

Derived KPIs: reimb-NADAC spread (SDUD/NADAC), state HHI (SDUD), avg Rx size (SDUD), Medicaid/Medicare cost ratio (brand-level), source coverage depth.

## Semantic Rules (Non-Negotiable)

1. Only SDUD populates state rows. No national or program-summary data in state cells.
2. NADAC in state tables is labeled "reference only (not state-varied)."
3. Brand-level sources (Part D, Part B, Medicaid Spending) are projected onto NDC-11 rows but status columns distinguish the projection.
4. NADAC and SDUD exact-match validation prevents bad_filter contamination.
5. Suppression flag from SDUD is preserved; suppressed cells are blank, not zero.
6. All spending figures are gross (pre-rebate). CMS cannot disclose rebates.
7. Part B Brnd_Name defaults to HCPCS description — not a real drug name.

## Confirmed But Not Yet Adapted

- MDRP Product File (`data.medicaid.gov` `0ad65fe5-...`) — NDC-11 native, innovator flag, TE code. Same API pattern as NADAC/SDUD.
- Orange Book — download-only ZIP, patents/exclusivities.
- ACA FUL — CSV download, reimbursement ceiling.

## Evaluated and Deferred

- FAERS — 26K pagination ceiling, bulk download required, many-to-many grain.
- Part D Prescribers — no NDC field, lossy name matching.
- Part D Formulary PUF — native NDC-11, high value, requires file-download pipeline. Phase 2 priority.
- ASP NDC-HCPCS Crosswalk — native NDC-11, would complete Part B bridge. Excel parse needed.
- RxClass ATC — 2-hop chain, rate-limited. Useful for classification.
- Retail pricing — no free public API exists.

## Implementation Pattern

All scripts: bash wrapper with `exec python3 - <<'ENDOFPYTHON'` heredoc. No external Python packages (openpyxl optional). SHA-256 URL-keyed filesystem cache. ThreadPoolExecutor for parallel fetches. All ASCII (zero non-ASCII bytes required for scripts to run).

## Deep Reference Files

- `source-log.md` — full source registry with every endpoint, field name, sample row, and access caveat
- `ndc-system-extension.md` — source validation ledger, KPI opportunity table, grain integrity table, forbidden shortcuts
- `README.md` — full project documentation with data dictionary
