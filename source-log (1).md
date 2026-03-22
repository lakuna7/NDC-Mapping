# Source Log

Operational log for all data sources — existing and new.
Each entry captures: description, API endpoints, data dictionary notes, website(s), access status, and raw notes.
Append a new entry whenever a source is added or updated. Do not delete old entries; mark them `DEPRECATED` if retired.

> **How to use:** Send source materials (any format — JSON, URL, description, screenshot notes) and this file gets updated.

---

## Entry format

```
### [SOURCE_NAME]
- **Status:** ACTIVE | BLOCKED | PENDING | DEPRECATED
- **Role:** (one-line semantic role)
- **Website:**
- **API base:**
- **Auth:** none | API key | OAuth | IP-restricted
- **Grain:** (primary key / fact grain)
- **Key fields:**
- **Data dict:**
- **Sample row:**
- **Access notes:**
- **Last updated:** YYYY-MM-DD
```

---

## Confirmed sources (from `source-and-key-semantics.md` §4)

---

### openFDA NDC
- **Status:** ACTIVE
- **Role:** Listed product and package identity — brand name, generic name, labeler, NDC, application number, SPL set ID
- **Website:** https://open.fda.gov/apis/drug/ndc/
- **API base:** `https://api.fda.gov/drug/ndc.json`
- **Auth:** none (rate-limited; API key optional for higher limits)
- **Grain:** one row per `package_ndc` (NDC-11); parent grain `product_ndc`
- **Key fields:** `product_ndc`, `package_ndc`, `brand_name`, `generic_name`, `application_number`, `spl_set_id`, `openfda.rxcui`, `openfda.manufacturer_name`, `packaging.description`, `marketing_start_date`, `marketing_end_date`
- **Data dict:** https://open.fda.gov/apis/drug/ndc/searchable-fields/
- **Sample row:**
  ```json
  {
    "product_ndc": "0006-0041",
    "brand_name": "KEYTRUDA",
    "generic_name": "PEMBROLIZUMAB",
    "labeler_name": "Merck Sharp & Dohme LLC",
    "dosage_form": "INJECTION",
    "route": ["INTRAVENOUS"],
    "marketing_status": "Prescription",
    "active_ingredients": [{"name": "PEMBROLIZUMAB", "strength": "25 mg/mL"}],
    "packaging": [{"package_ndc": "00006-0041-02", "description": "1 VIAL in 1 CARTON"}],
    "application_number": "BLA125514",
    "spl_set_id": "4b9f1a2e-...",
    "openfda": {"rxcui": ["1547545"], "manufacturer_name": ["Merck Sharp & Dohme LLC"]}
  }
  ```
- **Access notes:** No IP block. ~240 req/min without key, ~1000/min with key.
- **Last updated:** 2026-03-19

---

### Drugs@FDA (openFDA drugsfda)
- **Status:** ACTIVE
- **Role:** Regulatory application and product metadata — NDA/ANDA/BLA, sponsor, approval history
- **Website:** https://open.fda.gov/apis/drug/drugsfda/
- **API base:** `https://api.fda.gov/drug/drugsfda.json`
- **Auth:** none (same rate limits as openFDA NDC)
- **Grain:** one row per `application_number`; nested `products[]` array per product within application
- **Key fields:** `application_number`, `sponsor_name`, `products[].product_number`, `products[].proprietary_name`, `products[].dosage_form`, `openfda.product_ndc`, `openfda.package_ndc`, `openfda.rxcui`, `openfda.spl_set_id`
- **Data dict:** https://open.fda.gov/apis/drug/drugsfda/searchable-fields/
- **Sample row:**
  ```json
  {
    "application_number": "NDA020791",
    "sponsor_name": "BAYER HEALTHCARE LLC",
    "products": [{"product_number": "001", "proprietary_name": "ASPIRIN", "dosage_form": "TABLET"}],
    "openfda": {"product_ndc": ["00093-8816"], "package_ndc": ["00093-8816-86"], "rxcui": ["1191"]}
  }
  ```
- **Access notes:** No IP block.
- **Last updated:** 2026-03-19

---

### RxNav / RxNorm
- **Status:** ACTIVE
- **Role:** Concept mapping and NDC status/history — RxCUI, concept name, NDC↔RxCUI bridge
- **Website:** https://rxnav.nlm.nih.gov/
- **API base:** `https://rxnav.nlm.nih.gov/REST/`
- **Auth:** none
- **Grain:** varies by endpoint — `ndcproperties` = one row per NDC-11; `rxcui` lookups = concept level
- **Key fields:** `rxcui`, `name`, `tty`, `ndcItem` (NDC-11), `splSetIdItem`, `status` (ACTIVE/OBSOLETE)
- **Data dict:** https://lhncbc.nlm.nih.gov/RxNav/APIs/RxNormAPIs.html
- **Sample row:**
  ```json
  {
    "ndcPropertyList": {
      "ndcProperty": [{
        "ndcItem": "00378451793",
        "ndc9": "0378-4517",
        "ndc10": "0378-4517-93",
        "rxcui": "597987",
        "splSetIdItem": "4be76756-4114-4d50-a36c-fd410f6c773d",
        "propertyConceptList": {
          "propertyConcept": [{"propName": "LABELER", "propValue": "Mylan Pharmaceuticals Inc."}]
        }
      }]
    }
  }
  ```
- **Access notes:** No IP block. No auth required. NLM infrastructure — reliable.
- **Last updated:** 2026-03-19

---

### DailyMed v2
- **Status:** ACTIVE
- **Role:** SPL label document retrieval — structured label content, sections, NDC↔SPL mapping
- **Website:** https://dailymed.nlm.nih.gov/dailymed/
- **API base:** `https://dailymed.nlm.nih.gov/dailymed/services/v2/`
- **Auth:** none
- **Grain:** SPL set ID level (`spl_setid`); `/ndcs` endpoint returns one row per NDC
- **Key fields:** `spl_set_id`, `drug_name`, `application_number`, `rxcui`, `ndc`, sections (boxed warning, indications, etc.)
- **Data dict:** https://dailymed.nlm.nih.gov/dailymed/webservices-help/v2/
- **Sample row:**
  ```json
  {
    "setid": "4b9f1a2e-3c8d-4e5f-9a1b-2c3d4e5f6a7b",
    "title": "KEYTRUDA- pembrolizumab injection",
    "published_date": "2024-10-15"
  }
  ```
- **Access notes:** No IP block. NLM infrastructure.
- **Last updated:** 2026-03-19

---

### NADAC (CMS Medicaid)
- **Status:** ACTIVE
- **Role:** Package-native acquisition-cost benchmark pricing — weekly NDC-level pharmacy acquisition costs
- **Website:** https://www.medicaid.gov/medicaid/prescription-drugs/national-average-drug-acquisition-cost/index.html
- **API base:** `https://data.medicaid.gov/resource/4u91-w937.json` (Socrata SODA)
- **Dataset ID (data.medicaid.gov):** `fbb83258-11c7-47f5-8b18-5f8e79f7e704`
- **Auth:** none (Socrata app token optional for high-volume)
- **Row count:** ~1,942,577 (as of March 17, 2026)
- **Grain:** `NDC + Effective Date` — one row per 11-digit NDC per weekly pricing period
- **Dashboard level:** package-native — joins directly to package layer via NDC-11
- **Key fields (confirmed — real column headers):**
  | Column (exact name) | Description |
  |---|---|
  | `NDC Description` | Drug name, strength, and dosage form — behaves as a strong product-level label |
  | `NDC` | 11-digit NDC (labeler + product + package), no dashes |
  | `NADAC Per Unit` | Benchmark acquisition cost per unit (the pricing fact) |
  | `Effective Date` | Date the rate applies — **use this for time-series pricing** |
  | `Pricing Unit` | ML / GM / EA — unit of measure for `NADAC Per Unit` |
  | `Pharmacy Type Indicator` | C/I = Community/Independent |
  | `OTC` | Y = OTC, N = Prescription |
  | `Explanation Code` | Code 5 = price calculated based on package size |
  | `Classification for Rate Setting` | Brand/generic/special classification (B-ANDA, B-BIO, etc.) — belongs in pricing detail / tooltip layer |
  | `Corresponding Generic Drug NADAC Per Unit` | Generic comparator price where applicable |
  | `Corresponding Generic Drug Effective Date` | Effective date for the generic comparator price |
  | `As of Date` | Snapshot/publication date of the file row — **use this for source freshness tracking only** |
- **Date semantics (critical distinction):**
  - `Effective Date` = when the price rate applies → use for time-series pricing view
  - `As of Date` = when the file was published / row was written → use for source freshness / update metadata only
  - These must never be conflated.
- **Platform grain (normalized):** `ndc_11 + effective_date + benchmark_type` where `benchmark_type = 'NADAC'`
- **Data dict:** https://data.medicaid.gov/resource/4u91-w937
- **Field descriptions PDF:** https://www.cms.gov/files/document/medicaid-state-drug-utilization-data-field-descriptions.pdf
- **Sample row (confirmed field names):**
  ```
  NDC Description          | NDC         | NADAC Per Unit | Effective Date | Pricing Unit | Pharmacy Type Indicator | OTC | Explanation Code | Classification for Rate Setting | Corresponding Generic Drug NADAC Per Unit | Corresponding Generic Drug Effective Date | As of Date
  JANUVIA 100MG TABLET     | 00006001462 | 22.3451        | 2026-03-12     | EA           | C/I                     | N   | 1                | B                               |                                           |                                           | 2026-03-17
  ```
- **JANUVIA hierarchy model (from NDC Description pattern):**
  - Brand: `JANUVIA`
  - Product / NDC9: `JANUVIA 100MG TABLET` ← NDC Description already behaves at this level
  - Package / NDC11: `JANUVIA 100MG TABLET × 30` (packaging count distinguishes NDC11s)
- **Access notes:** No IP block. Socrata endpoint. CSV bulk download also at download.medicaid.gov. License: public domain (usa.gov/publicdomain/label/1.0).
- **Last updated:** 2026-03-20

---

### SDUD (CMS Medicaid State Drug Utilization Data)
- **Status:** ACTIVE
- **Role:** Package-native Medicaid utilization and spend — state-level FFS + MCO claims, units, and reimbursement
- **Website:** https://www.medicaid.gov/medicaid/prescription-drugs/state-drug-utilization-data/index.html
- **API base:** `https://data.medicaid.gov/resource/d89o-9mu2.json` (Socrata SODA)
- **2024 dataset page:** https://data.medicaid.gov/dataset/61729e5a-7aa8-448c-8903-ba3e0cd0ea3c
- **Auth:** none
- **Dashboard level:** package-native — NDC-11 is the join key; state is mandatory dimension
- **Grain:** `NDC-11 + State + Year + Quarter + Utilization Type` — one row per NDC per state per quarter per record type (FFSU or MCOU)
  - **FFSU** = Fee-For-Service Utilization (available all quarters)
  - **MCOU** = Managed Care Organization Utilization (available from 1Q2010 onward per ACA requirement)
- **Key fields (confirmed — from CMS field descriptions PDF):**
  | Column (exact name) | Description |
  |---|---|
  | `Utilization Type` | Record type: `FFSU` (FFS) or `MCOU` (MCO) |
  | `State` | 2-char state abbreviation |
  | `Labeler Code` | 5-digit NDC segment 1 — identifies labeler (right-justified, zero-padded) |
  | `Product Code` | 4-char NDC segment 2 — identifies drug/strength/form (right-justified, zero-padded) |
  | `Package Size` | 2-char NDC segment 3 — package size code |
  | `Year` | Reporting year |
  | `Quarter` | Reporting quarter (1–4) |
  | `Product Name` | Drug product name |
  | `Units Reimbursed` | Units (by unit type) reimbursed/dispensed during the period — 12 whole + 3 decimal |
  | `Number of Prescriptions` | Prescription claims reimbursed or dispensed during the period |
  | `Total Amount Reimbursed` | Sum of Medicaid + Non-Medicaid reimbursement (before rebates) — TAR |
  | `Medicaid Amount Reimbursed` | Medicaid-only reimbursement to pharmacies/providers — MAR |
  | `Non Medicaid Amount Reimbursed` | Non-Medicaid entity reimbursement (ineligible for Federal match) — NMAR |
  | `Rebate Amount Claimed` | State-calculated rebate owed = Units Reimbursed × URA |
  | `Suppression Used` | Flag: data suppressed because count < 11 (HIPAA/Privacy Act) |
  | `Delete Flag` | Used in submissions only — marks a previously reported record for deletion |
- **Data dict PDF:** https://www.cms.gov/files/document/medicaid-state-drug-utilization-data-field-descriptions.pdf
- **Sample row:**
  ```
  Utilization Type | State | Labeler Code | Product Code | Package Size | Year | Quarter | Product Name | Units Reimbursed | Number of Prescriptions | Total Amount Reimbursed | Medicaid Amount Reimbursed | Non Medicaid Amount Reimbursed | Suppression Used
  FFSU             | CA    | 00007        | 4148         | 62           | 2023 | 1       | ASPIRIN      | 1200.000         | 300                     | 15000.00                | 14500.00                   | 500.00                         | false
  ```
- **Suppression rule:** Records with < 11 prescriptions are suppressed per HIPAA / Privacy Act. `Suppression Used` flag must be respected — do not impute or interpolate suppressed cells.
- **MCO note:** MCO data (MCOU) unavailable pre-2010. Both FFSU and MCOU rows exist for the same NDC+State+Year+Quarter — must aggregate or keep separate depending on use case.
- **Access notes:** No IP block. Socrata endpoint. Annual CSV files also available (e.g., `sdud-2024-updated-dec2025.csv`).
- **Last updated:** 2026-03-20

---

### Orange Book
- **Status:** ACTIVE (no adapter yet)
- **Role:** Small-molecule therapeutic equivalence, patents, exclusivities
- **Website:** https://www.fda.gov/drugs/drug-approvals-and-databases/approved-drug-products-therapeutic-equivalence-evaluations-orange-book
- **API base:** None — download only (ZIP file: `OrangeBook.zip`)
- **Auth:** none
- **Grain:** `application_number + product_number` per product/TE row
- **Key fields:** `appl_type`, `appl_no`, `product_no`, `ingredient`, `df_route`, `trade_name`, `applicant`, `strength`, `appl_type`, `te_code`, `patent_no`, `patent_expire_date_text`, `exclusivity_code`, `exclusivity_date`
- **Data dict:** https://www.fda.gov/drugs/drug-approvals-and-databases/orange-book-data-files
- **Sample row:**
  ```
  NDA  | 020791 | 001 | ASPIRIN | TABLET;ORAL | ASPIRIN | BAYER | 325MG | AB | 2023-09-15
  ```
- **Access notes:** File download, no IP restriction.
- **Last updated:** 2026-03-19

---

### Purple Book
- **Status:** ACTIVE (no adapter yet)
- **Role:** Biologic reference products and biosimilar/interchangeability relationships
- **Website:** https://purplebooksearch.fda.gov/
- **API base:** None — web search interface only, no public REST API
- **Auth:** N/A
- **Grain:** BLA-level (`application_number`)
- **Key fields:** `proper_name`, `tradename`, `application_no`, `bla_type`, `reference_product_exclusivity_expiration`, `interchangeable`, `biosimilar_applicant`
- **Data dict:** https://www.fda.gov/drugs/biosimilars/biosimilar-product-information
- **Sample row:** N/A — no API, web scraping required
- **Access notes:** No public API. Web scraping or periodic manual download needed.
- **Last updated:** 2026-03-19

---

### Medicaid Drug Rebate Program (MDRP) Product File
- **Status:** ACTIVE (no adapter yet)
- **Role:** Medicaid program product-reference layer — innovator/non-innovator flag, OTC flag, unit type, TE code, COD status
- **Website:** https://www.medicaid.gov/medicaid/prescription-drugs/medicaid-drug-rebate-program/medicaid-drug-rebate-program-data
- **Dataset page:** https://data.medicaid.gov/dataset/0ad65fe5-3ad3-5d79-a3f9-7893ded7963a
- **Also on healthdata.gov:** `9huc-ebz3` → `https://healthdata.gov/resource/9huc-ebz3.json`
- **API base:** `https://data.medicaid.gov/api/1/datastore/query/0ad65fe5-3ad3-5d79-a3f9-7893ded7963a`
- **Data dictionary (metastore):** `https://data.medicaid.gov/api/1/metastore/schemas/data-dictionary/items/8b3e3880-fd1b-487c-9817-9aa93009f2aa`
- **Docs endpoint:** `https://data.medicaid.gov/api/1/metastore/schemas/dataset/items/0ad65fe5-3ad3-5d79-a3f9-7893ded7963a/docs`
- **Auth:** none
- **Grain:** `ndc` (11-digit) per product; quarterly snapshot + weekly "newly reported" delta
- **Key fields:**
  | Field | Description |
  |---|---|
  | `ndc` | 11-digit NDC identifying the drug |
  | `labeler_code` | 5-digit labeler segment of NDC |
  | `unit_type` | Reported unit type (EA / GM / ML) — used in URA rebate calculation |
  | `units_per_package_size` | Units per package |
  | `product_name` | Drug product name |
  | `fda_approval_date` | FDA approval date |
  | `market_date` | Date drug entered market |
  | `innovator_flag` | Innovator (1) or non-innovator (0) |
  | `otc_flag` | OTC (Y) or prescription (N) |
  | `te_code` | FDA therapeutic equivalence code |
  | `covered_outpatient_drug` | COD status (replaces DESI rating in newer versions) |
  | `desi_rating` | Legacy DESI efficacy rating |
  | `termination_date` | Date drug terminated from MDRP |
- **Sample row:**
  ```
  0007414862 | 00007 | MG | 1 | ASPIRIN TABLET | 1995-01-01 | 1995-01-01 | 1 | N | AB | Y | DESI-2 | 2025-12-31
  ```
- **Update cadence:** Quarterly snapshot (main dataset) + weekly delta file (newly reported drugs)
- **Access notes:** data.medicaid.gov API endpoint available. healthdata.gov mirror at `9huc-ebz3` IP-blocked from cloud. Use data.medicaid.gov API.
- **Last updated:** 2026-03-20

---

### ACA Federal Upper Limits (FUL)
- **Status:** ACTIVE (no adapter yet)
- **Role:** Reimbursement ceiling benchmark — CMS-published FUL prices based on weighted AMP
- **Website:** https://www.medicaid.gov/medicaid/prescription-drugs/federal-upper-limits/index.html
- **API base:** None — CSV download via healthdata.gov
- **Auth:** none
- **Grain:** NDC-level (grain TBD pending implementation validation — do not assume `ndc_11` until confirmed)
- **Key fields:** `ndc`, `unit_type`, `price_unit`, `federal_upper_limit`
- **Data dict:** CMS FUL data dictionary
- **Sample row:**
  ```
  0007414862 | ML | 1 | 3.1234
  ```
- **Access notes:** No IP block. Bulk CSV only.
- **Last updated:** 2026-03-19

---

## Sources in progress / blocked

---

### WAC Price Increases (HCAI / California)
- **Status:** BLOCKED (IP restriction on cloud environments) — schema fully documented, adapter pending access resolution
- **Role:** List-price change events — WAC before/after per NDC, effective date, cost factors, 5-year history; mandated under California SB 17 / Health & Safety Code §127677
- **Threshold:** Applies to drugs with WAC > $40/course and WAC increase > 16% over the WAC on Dec 31 of 3 years prior. Reports due within 1 month after end of the quarter the increase took effect.
- **Website:** https://hcai.ca.gov/visualizations/prescription-drug-cost-transparency-public-reporting/
- **CHHS dataset page:** https://data.chhs.ca.gov/dataset/prescription-drug-wholesale-acquisition-cost-wac-increases
- **CA Open Data mirror:** https://data.ca.gov/dataset/prescription-drug-wholesale-acquisition-cost-wac-increases
- **catalog.data.gov:** https://catalog.data.gov/dataset/prescription-drug-wholesale-acquisition-cost-wac-increases-76f5a
- **CHHS dataset ID (CKAN):** `0c693b50-6d23-46a0-a1ae-7c320fe23dff`
- **CKAN API (datastore):** `https://data.chhs.ca.gov/api/action/datastore_search?resource_id=3a133d3f-da34-43ae-8171-14cdab782b1d&limit=0`
  - `3a133d3f-da34-43ae-8171-14cdab782b1d` = datastore resource for the WAC Increases table
  - `2fe618fd-b03d-4453-aa32-de5b4a470e00` = resource for the "5 Year History" monthly update (Excel/CSV)
- **Harvest records (catalog metadata):**
  - `https://catalog.data.gov/harvest/object/4eba3d1f-e46c-4aaa-9fe6-bd4127fc1bdc` (DCAT-US harvest object)
  - `https://catalog-beta.data.gov/harvest_record/342851c3-e496-424b-a01a-a2c9d2fba8bf/raw` (raw harvest record)
- **Auth:** none (CKAN API; app token optional for high-volume)
- **Structure:** 27 total data elements split across **two files**:
  1. `Prescription Drug WAC Increase` — current increase facts (amount, WAC after, effective date, factors)
  2. `Prescription Drug WAC Increase – 5 Year History` — prior 5 years of WAC change events per NDC
- **Grain:** `ndc_11 + wac_effective_date` — one row per WAC change event per NDC
- **Key fields:**
  | Field | Description | Notes |
  |---|---|---|
  | `ndc` | 11-digit NDC (labeler + product + package) | Leading zeros must be preserved — do NOT save as CSV without quoting |
  | `drug_product_description` | Drug name/description | |
  | `labeler_name` | Manufacturer / labeler name | |
  | `wac_before_increase` | WAC prior to the reported increase | |
  | `wac_after_increase` | WAC after the reported increase | |
  | `wac_increase_amount` | Dollar amount of the increase | |
  | `wac_increase_pct` | Percentage WAC increase | |
  | `effective_date` | Quarter effective date of the WAC increase | |
  | `patent_expiration_date` | Patent expiration date | |
  | `cost_increase_factors` | Narrative: reasons cited for the increase | |
  | `unit_sales_volume_us` | Unit sales volume in US (**pre-April 2024 only**) | Dropped April 1, 2024 |
  | `total_gross_sales_usd` | Total gross sales in USD (**post-April 2024 only**) | Replaces unit_sales_volume_us |
  | *(5-year history fields)* | Prior WAC increase amounts + effective dates for up to 5 years | Separate file |
- **Schema change (April 1, 2024):** `unit_sales_volume_us` replaced by `total_gross_sales_usd`. Both field names must be handled in the adapter.
- **Update cadence:** Monthly updates for current year; prior years updated as needed. Check 'Data last updated' per resource.
- **Supporting docs:**
  - Format & File Specifications v2.0: https://hcai.ca.gov/wp-content/uploads/2024/03/Format-and-File-Specifications-version-2.0-ada.pdf
  - Quick Guide (linking datasets): https://hcai.ca.gov/wp-content/uploads/2024/03/QuickGuide_LinkingTheDatasets.pdf
  - Program Regulations: https://hcai.ca.gov/wp-content/uploads/2024/03/CTRx-Regulations-Text.pdf
  - DCAT-US standard (harvest format reference): https://resources.data.gov/resources/dcat-us/
- **Sample row (illustrative):**
  ```json
  {
    "ndc": "00006004102",
    "drug_product_description": "KEYTRUDA 25 MG/ML INJ",
    "labeler_name": "MERCK SHARP & DOHME LLC",
    "wac_before_increase": "920.00",
    "wac_after_increase": "945.00",
    "wac_increase_amount": "25.00",
    "wac_increase_pct": "2.72",
    "effective_date": "2026-01-01",
    "patent_expiration_date": "2028-06-30",
    "cost_increase_factors": "Research and development costs; market conditions",
    "total_gross_sales_usd": "4200000000.00"
  }
  ```
- **Access notes:** **IP BLOCKED from cloud/hosted environments** — both CKAN API and direct download return 403. Workarounds: (1) fetch via residential/VPN proxy, (2) schedule pull from non-cloud machine → push to storage, (3) contact HCAI for bulk export. **Do not use Socrata SODA URL** (`/resource/2fe618fd...json`) — that's the Excel resource, not the datastore. Use the CKAN datastore API (`/api/action/datastore_search`) once access is resolved.
- **Last updated:** 2026-03-20

---

## New sources logged 2026-03-20

---

### Medicare Part B — Annual (Spending by Drug)
- **Status:** ACTIVE (no adapter yet)
- **Role:** Annual HCPCS-native drug spend for physician-administered drugs in Medicare Part B
- **Website:** https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-part-b-spending-by-drug
- **Dataset ID:** `76a714ad-3a2c-43ac-b76d-9dadf8f7d890`
- **API base:** `https://data.cms.gov/data-api/v1/dataset/76a714ad-3a2c-43ac-b76d-9dadf8f7d890/data`
- **API docs:** https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-part-b-spending-by-drug/api-docs
- **Auth:** none
- **Dashboard level:** HCPCS-native — grain is HCPCS code, NOT drug name, NOT NDC
- **Grain:** `HCPCS_Cd + year` (one row per HCPCS code per year)
- **Key fields (confirmed from source-log-combined):**
  | Column (exact name, year-suffixed) | Description |
  |---|---|
  | `HCPCS_Cd` | HCPCS procedure code — primary identifier for Part B drugs |
  | `HCPCS_Desc` | HCPCS code description — **this is what fills Brand/Generic name fields when no drug name exists** |
  | `Brnd_Name` | Brand name — defaults to HCPCS description if unavailable; **not a reliable drug name in Part B** |
  | `Gnrc_Name` | Generic name — same caveat as `Brnd_Name` in Part B context |
  | `Mftr_Name` | Manufacturer — **not available in Part B** (no manufacturer dimension) |
  | `Tot_Spndng_YYYY` | Total Part B spending (Medicare + beneficiary liability; no rebates deducted) |
  | `Tot_Dsg_Unts_YYYY` | Total dosage units (defined per HCPCS — not comparable to pharmacy dosage units) |
  | `Tot_Clms_YYYY` | Total service claims |
  | `Tot_Benes_YYYY` | Total distinct beneficiaries |
  | `Avg_Spndng_Per_Dsg_Unt_YYYY` | Avg spending per dosage unit — **note: `Spndng` not `Spnd`** (differs from Part D naming) |
  | `Avg_Spndng_Per_Clm_YYYY` | Avg spending per claim |
  | `Avg_Spndng_Per_Bene_YYYY` | Avg spending per beneficiary |
  | `Avg_DY23_ASP_Price` | Average Sales Price per unit for the data year — **Part B-specific; year-tagged** |
  | `Outlier_Flag_YYYY` | 1 = per-unit price substantially impacted by outliers |
  | `Chg_Avg_Spndng_Per_Dsg_Unt_22_23` | Year-over-year change in avg spend per dosage unit |
  | `CAGR_Avg_Spnd_Per_Dsg_Unt_19_23` | 5-year CAGR of avg spend per dosage unit (2019–2023) |
- **Part B naming trap:** `Brnd_Name` and `Gnrc_Name` in Part B default to the HCPCS description — do NOT treat them as true drug names. Use `HCPCS_Cd` as the primary identifier.
- **ASP vs NADAC:** `Avg_DY23_ASP_Price` = Medicare reimbursement-based unit price. Never substitute for NADAC (acquisition cost).
- **Data dict PDF (2025-11, confirmed):** https://data.cms.gov/sites/default/files/2025-11/b2529e9f-8ef2-4863-b2d0-21fd22752702/Medicare%20Quarterly%20Part%20B%20Spending%20by%20Drug%20Data%20Dictionary%20508.pdf
- **Data dict page:** https://data.cms.gov/resources/medicare-part-b-spending-by-drug-data-dictionary
- **Scope exclusions:** Medicare Advantage excluded. No NOC codes (J3490, J3590, J9999). Medicare-primary payer only. No critical access hospital claims.
- **Access notes:** No IP block. **NDC not in this file** — HCPCS→NDC crosswalk required to bridge to package layer.
- **Last updated:** 2026-03-20

---

### Medicare Part B — Quarterly (Preliminary Spending by Drug)
- **Status:** ACTIVE (no adapter yet)
- **Role:** Preliminary quarterly Part B spending — same HCPCS-native grain + `Year`/`Quarter`; 6-month claims lag
- **Website:** https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-quarterly-part-b-spending-by-drug
- **Dataset ID:** `bf6a5b3b-31ee-4abb-b1ad-2607a1e7510a`
- **API base:** `https://data.cms.gov/data-api/v1/dataset/bf6a5b3b-31ee-4abb-b1ad-2607a1e7510a/data`
- **Auth:** none
- **Grain:** `HCPCS_Cd + Year + Quarter`
- **Key fields:** Same as annual Part B above but with non-suffixed spending columns + explicit `Year` + `Quarter` fields. `Tot_Dsg_Unts` not present in quarterly.
- **Data dict PDF (2025-11, confirmed):** https://data.cms.gov/sites/default/files/2025-11/b2529e9f-8ef2-4863-b2d0-21fd22752702/Medicare%20Quarterly%20Part%20B%20Spending%20by%20Drug%20Data%20Dictionary%20508.pdf
- **Data dict page:** https://data.cms.gov/resources/medicare-quarterly-part-b-spending-by-drug-data-dictionary
- **Methodology PDF:** https://data.cms.gov/sites/default/files/2025-12/Medicare%20Quarterly%20Part%20B%20Spending%20by%20Drug%20Methodology_508.pdf
- **Update cadence:** Quarterly; 6-month claims lag; preliminary until superseded by annual.
- **Access notes:** No IP block. NDC not in file — HCPCS→NDC crosswalk required.
- **Last updated:** 2026-03-20

---

### Medicare Part D — Annual (Spending by Drug)
- **Status:** ACTIVE (no adapter yet)
- **Role:** Program-period grain drug spending — annual gross Part D spend; NOT package-native
- **Website:** https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-part-d-spending-by-drug
- **Dataset ID:** `7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b`
- **API base:** `https://data.cms.gov/data-api/v1/dataset/7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b/data`
- **API docs:** https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-part-d-spending-by-drug/api-docs
- **Auth:** none
- **Dashboard level:** program-period grain — drug name level, NOT NDC/package level
- **Grain:** `Brnd_Name + Gnrc_Name + year` (one row per drug per year, aggregated across all NDCs and manufacturers for that drug)
- **Key fields (confirmed — real column names from CMS data portal, year-suffixed):**
  | Column (exact name, 2023 vintage) | Description |
  |---|---|
  | `Brnd_Name` | Brand name |
  | `Gnrc_Name` | Generic name |
  | `Tot_Mftr` | Total number of manufacturers reporting |
  | `Mftr_Name` | Manufacturer name |
  | `Tot_Spndng_2023` | Total gross drug cost 2023 (Medicare + plan + beneficiary; **rebates NOT deducted**) |
  | `Tot_Dsg_Unts_2023` | Total dosage units 2023 |
  | `Tot_Clms_2023` | Total prescription claims/fills 2023 |
  | `Tot_Benes_2023` | Total distinct Part D beneficiaries 2023 |
  | `Avg_Spnd_Per_Dsg_Unt_Wghtd_2023` | Weighted average spend per dosage unit 2023 |
  | `Avg_Spnd_Per_Clm_2023` | Average spend per claim 2023 |
  | `Avg_Spnd_Per_Bene_2023` | Average spend per beneficiary 2023 |
  | `Outlier_Flag_2023` | Flag = 1 when avg spend/unit substantially impacted by outlier records; shown as `^` in dashboard |
  | `Chg_Avg_Spnd_Per_Dsg_Unt_22_23` | Year-over-year change in avg spend per dosage unit (2022→2023) |
  | `CAGR_Avg_Spnd_Per_Dsg_Unt_19_23` | 4-year CAGR of avg spend per dosage unit (2019→2023) |
- **Schema note:** Spending columns are **year-suffixed** (e.g., `Tot_Spndng_2023`), not generic. Each annual release uses its own year suffix. The quarterly dataset uses non-suffixed names + a `Year`/`Quarter` column.
- **Data dict PDF (2025-05, confirmed):** https://data.cms.gov/sites/default/files/2025-05/Medicare%20Part%20D%20Spending%20by%20Drug%20Data%20Dictionary%2020250425_508.pdf
- **Data dict page:** https://data.cms.gov/resources/medicare-part-d-spending-by-drug-data-dictionary
- **Data dict 2023:** https://data.cms.gov/resources/medicare-part-d-spending-by-drug-data-dictionary-2023
- **Quarterly data dict PDF (2025-12, confirmed):** https://data.cms.gov/sites/default/files/2025-12/08c80ec8-e57c-4a2c-9470-5ff26e76dace/Medicare%20Quarterly%20Part%20D%20Spending%20by%20Drug%20Data%20Dictionary%20508.pdf
- **Methodology:** https://data.cms.gov/resources/medicare-part-d-spending-by-drug-methodology
- **Sample row:**
  ```
  Brnd_Name  | Gnrc_Name      | Tot_Mftr | Mftr_Name             | Tot_Spndng_2023    | Tot_Clms_2023 | Tot_Benes_2023 | Avg_Spnd_Per_Dsg_Unt_Wghtd_2023 | Outlier_Flag_2023
  KEYTRUDA   | PEMBROLIZUMAB  | 1        | MERCK SHARP & DOHME   | 4200000000.00      | 45000         | 38000          | 945.00                          | 0
  ```
- **Important:** Gross cost only — **no rebate adjustment**. Cannot be used as net price. CMS is legally prohibited from disclosing rebates.
- **Join limitation:** Drug-level grain — cannot join directly to package layer. Name-based bridge to RxNorm or openFDA NDC required, with confidence scoring per `source-and-key-semantics.md` §10.
- **Last updated:** 2026-03-20

---

### Medicare Part D — Quarterly (Preliminary Spending by Drug)
- **Status:** ACTIVE (no adapter yet)
- **Role:** Preliminary quarterly Part D spending — same drug-level grain + `Year`/`Quarter`; 6-month claims lag
- **Website:** https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-quarterly-part-d-spending-by-drug
- **Dataset ID:** `4ff7c618-4e40-483a-b390-c8a58c94fa15`
- **API base:** `https://data.cms.gov/data-api/v1/dataset/4ff7c618-4e40-483a-b390-c8a58c94fa15/data`
- **Auth:** none
- **Dashboard level:** program-period grain — drug name level, NOT NDC/package level
- **Grain:** `Brnd_Name + Gnrc_Name + Mftr_Name + Year + Quarter`
- **Key fields (confirmed from source-log-combined):**
  | Column | Description |
  |---|---|
  | `Brnd_Name` | Brand name |
  | `Gnrc_Name` | Generic name |
  | `Mftr_Name` | Manufacturer name — blank = "Overall" aggregate row across all manufacturers |
  | `Tot_Mftr` | Number of distinct manufacturers |
  | `Tot_Spndng` | Total gross drug cost (non-suffixed in quarterly) |
  | `Tot_Clms` | Total claims |
  | `Tot_Benes` | Total beneficiaries |
  | `Avg_Spnd_Per_Dsg_Unt_Wghtd` | Weighted avg spend per dosage unit |
  | `Avg_Spnd_Per_Clm` | Avg spend per claim |
  | `Avg_Spnd_Per_Bene` | Avg spend per beneficiary |
  | `Drug_Uses` | Consumer-friendly clinical indication text — **present in Part D Quarterly only** |
  | `Year` | Explicit year field (absent in annual) |
  | `Quarter` | Quarter (1–4) |
- **Overall vs manufacturer rows:** When `Tot_Mftr > 1`, dataset contains one blank-`Mftr_Name` "Overall" row plus individual manufacturer rows. Use Overall for aggregate; use specific rows for manufacturer breakdown.
- **`Drug_Uses` note:** This field exists in quarterly but not annual Part D. Use it for clinical indication lookups.
- **`Tot_Dsg_Unts` not present in quarterly** — only in annual.
- **Data dict PDF (2025-12, confirmed):** https://data.cms.gov/sites/default/files/2025-12/08c80ec8-e57c-4a2c-9470-5ff26e76dace/Medicare%20Quarterly%20Part%20D%20Spending%20by%20Drug%20Data%20Dictionary%20508.pdf
- **Data dict page:** https://data.cms.gov/resources/medicare-quarterly-part-d-spending-by-drug-data-dictionary
- **Update cadence:** Quarterly; preliminary until superseded by annual.
- **Access notes:** No IP block. NDC not in file.
- **Last updated:** 2026-03-20

---

### Medicaid Spending by Drug
- **Status:** ACTIVE (no adapter yet)
- **Role:** Program-period drug-level Medicaid spending — annual gross spend for covered outpatient drugs; NOT package-native; NOT the same as SDUD
- **Relationship to SDUD:** SDUD is the raw package-level utilization fact (NDC-11 × state × quarter). This dataset is an aggregated drug-level spending summary — analogous to Part D Annual but for Medicaid.
- **Website:** https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicaid-spending-by-drug
- **Dataset ID:** `be64fce3-e835-4589-b46b-024198e524a6`
- **API base:** `https://data.cms.gov/data-api/v1/dataset/be64fce3-e835-4589-b46b-024198e524a6/data`
- **Dashboard:** https://data.cms.gov/tools/medicaid-drug-spending-dashboard
- **Auth:** none
- **Dashboard level:** program-period grain — drug name + manufacturer level, NOT NDC/package level
- **Grain:** `Brnd_Name + Gnrc_Name + Mftr_Name + year`
- **Spending basis:** Total reimbursed by Medicaid AND non-Medicaid entities (Federal + State + dispensing fees). **Rebates NOT deducted.**
- **Key fields (confirmed from source-log-combined):**
  | Column (year-suffixed) | Description |
  |---|---|
  | `Brnd_Name` | Brand name |
  | `Gnrc_Name` | Generic name |
  | `Mftr_Name` | Manufacturer — blank = "Overall" row |
  | `Tot_Mftr` | Number of distinct manufacturers |
  | `Tot_Spndng_YYYY` | Total reimbursement (year-suffixed) |
  | `Tot_Dsg_Unts_YYYY` | Total dosage units (year-suffixed) |
  | `Tot_Clms_YYYY` | Total claims (year-suffixed) |
  | `Avg_Spnd_Per_Dsg_Unt_Wghtd_YYYY` | Weighted avg spend per dosage unit |
  | `Avg_Spnd_Per_Clm_YYYY` | Avg spend per claim |
  | `Outlier_Flag_YYYY` | Outlier flag |
  | `Chg_Avg_Spnd_Per_Dsg_Unt_22_23` | Year-over-year change in avg spend per unit |
  | `CAGR_Avg_Spnd_Per_Dsg_Unt_18_23` | CAGR 2018–2023 — **base year 2018, not 2019 (differs from Part D)** |
- **No beneficiary field** — Medicaid does not track `Tot_Benes`. Do not attempt to derive beneficiary counts from Medicaid spending data.
- **Overall vs manufacturer rows:** Same pattern as Part D — blank `Mftr_Name` = overall aggregate.
- **Data dict PDF (2025-05, confirmed):** https://data.cms.gov/sites/default/files/2025-05/Medicaid%20Spending%20by%20Drug%20Data%20Dictionary.pdf
- **Data dict page:** https://data.cms.gov/resources/medicaid-spending-by-drug-data-dictionary
- **catalog.data.gov:** https://catalog.data.gov/dataset/medicaid-spending-by-drug-b6f77
- **Join limitation:** Drug-level grain — name-based bridge to RxNorm/openFDA required for package-layer join (confidence-scored per `source-and-key-semantics.md` §10).
- **Access notes:** No IP block.
- **Last updated:** 2026-03-20

---

### CMS Data API Guide (Reference)
- **Status:** ACTIVE — reference document, not a data source
- **Role:** Technical guide for all CMS data API access (pagination, filtering, sorting, authentication)
- **PDF:** https://data.cms.gov/sites/default/files/2024-10/7ef65521-65a4-41ed-b600-3a0011f8ec4b/API%20Guide%20Formatted%201_6.pdf
- **API catalog (data.json):** https://data.cms.gov/data.json
- **Provider data API:** https://data.cms.gov/provider-data/api/1?authentication=false
- **Auth:** none for public datasets; app tokens available for higher rate limits
- **Notes:** All CMS data API endpoints follow pattern `https://data.cms.gov/data-api/v1/dataset/{dataset-id}/data`. Supports `?filter[field]=value`, `?size=`, `?offset=` pagination, and `?sort[field]=asc` ordering.
- **Last updated:** 2026-03-20

---

### data.medicaid.gov Catalog
- **Status:** ACTIVE — catalog/discovery endpoint
- **Role:** Full catalog of all Medicaid open data datasets (NADAC, SDUD, MDRP, etc.)
- **data.json:** https://data.medicaid.gov/data.json
- **Notes:** Use to discover dataset IDs and check for new datasets. Follows DCAT standard.
- **Last updated:** 2026-03-20

---

## Pending / to be logged

> Sources sent by user but not yet fully documented go here as stubs until materials arrive.

---

*End of log. Append new entries above this line.*
