# Operational validation of six candidate NDC-11 data sources

Four of the six candidate sources pass operational validation and are integration-ready; two are partially ready with significant bridging constraints. The **CMS Part D Formulary PUF** and **CMS ASP NDC-HCPCS Crosswalk** emerge as the highest-value additions because both carry **native NDC-11** and unlock entirely new analytical dimensions (formulary coverage intelligence and Part B pricing bridging, respectively). The FDA Drug Shortages API and RxClass ATC chain are also ready but serve narrower enrichment roles. The FAERS adverse events endpoint and Part D Prescribers dataset both require non-trivial bridging — FAERS through NDC format normalization with incomplete coverage, Prescribers through lossy drug-name matching with zero NDC content.

-----

## Source 1: FDA Drug Shortages API — READY

**Endpoint tested:** `https://api.fda.gov/drug/shortages.json` → HTTP 200, valid JSON, last updated 2026-03-21

**Fields observed in response (top-level):** `generic_name`, `package_ndc`, `company_name`, `status`, `availability`, `update_type`, `initial_posting_date`, `update_date`, `therapeutic_category` (array), `dosage_form`, `presentation`, `contact_info`. Additional documented fields include `proprietary_name`, `shortage_reason`, `strength`, `resolved_note`, `discontinued_date`.

**openfda block present:** Yes — richly populated with `application_number`, `brand_name`, `generic_name`, `manufacturer_name`, `product_ndc`, `package_ndc`, `rxcui`, `spl_id`, `spl_set_id`, `substance_name`, `product_type`, `route`, `unii`.

|Attribute                    |Finding                                                                                                            |
|-----------------------------|-------------------------------------------------------------------------------------------------------------------|
|Native grain                 |**Package-native** — one record = one shortage presentation identified by a specific package NDC                   |
|Primary identifiers          |`package_ndc` (top-level, single string), composite with `company_name` and `generic_name`; no explicit shortage_id|
|NDC-11 native?               |**No** — NDCs are in FDA 10-digit variable-segment format (4-4-2, 5-3-2, or 5-4-1). Zero-padding to 5-4-2 required |
|NDC join strategy            |Apply segment-format detection + zero-padding normalization; also bridge via `openfda.rxcui` as fallback           |
|Total records                |**1,679** active shortage records                                                                                  |
|Rate limits                  |240 req/min, 1,000/day without key; 120,000/day with free API key                                                  |
|Auth required                |None (API key optional)                                                                                            |
|Update frequency             |Daily                                                                                                              |
|Semantic grain classification|**Package-native**                                                                                                 |

**Implementation notes:** The dataset is small enough to ingest entirely via a single paginated pull (~17 calls at limit=100). The top-level `package_ndc` identifies the specific package in shortage, while `openfda.package_ndc` lists all related packages for the product. A **standard openFDA NDC normalizer** (10-digit → 11-digit zero-padding) is the only prerequisite. The `shortage_reason`, `availability`, and `status` fields enable a binary shortage flag at the NDC-11 grain with no aggregation ambiguity.

**Verdict: READY** — flat-script compatible, small dataset, daily refresh, direct package-NDC grain. Implement with a single `curl | python` pipeline.

-----

## Source 2: openFDA FAERS adverse events — PARTIALLY READY

**Endpoint tested:** `https://api.fda.gov/drug/event.json?limit=1` → HTTP 200, valid JSON

**Fields observed at top level of each result:** `safetyreportid`, `safetyreportversion`, `receivedate`, `receiptdate`, `serious`, `seriousnessdeath`, `seriousnesshospitalization`, `seriousnesslifethreatening`, `seriousnessdisabling`, `seriousnesscongenitalanomali`, `seriousnessother`, `reporttype`, `fulfillexpeditecriteria`, `companynumb`, `authoritynumb`, `occurcountry`, `primarysourcecountry`, `duplicate`, `transmissiondate`, `sender`, `receiver`, `primarysource`, `patient`.

**Fields under `patient.drug[]`:** `medicinalproduct`, `drugcharacterization`, `drugindication`, `drugdosagetext`, `drugdosageform`, `drugadministrationroute`, `drugstartdate`, `drugenddate`, `actiondrug`, `drugauthorizationnumb`, `drugbatchnumb`, `drugstructuredosagenumb`, `drugstructuredosageunit`, `drugcumulativedosagenumb`, `drugcumulativedosageunit`, `activesubstance.activesubstancename`, `openfda` block.

**Fields under `patient.drug[].openfda`:** `application_number`, `brand_name`, `generic_name`, `manufacturer_name`, `product_ndc`, `package_ndc`, `substance_name`, `rxcui`, `spl_id`, `spl_set_id`, `pharm_class_cs`, `pharm_class_epc`, `pharm_class_pe`, `pharm_class_moa`, `route`, `product_type`, `nui`, `unii`.

|Attribute                    |Finding                                                                                                         |
|-----------------------------|----------------------------------------------------------------------------------------------------------------|
|Native grain                 |**Report-native** — one record = one ICSR (Individual Case Safety Report), identified by `safetyreportid`       |
|Primary identifier           |`safetyreportid` + `safetyreportversion`                                                                        |
|NDC-11 native?               |**No** — `openfda.package_ndc` uses FDA 10-digit format; requires zero-padding normalization                    |
|NDC coverage                 |**Incomplete** — many drug entries lack `openfda` block entirely (foreign drugs, misspelled names, OTC products)|
|Searchable by NDC?           |Yes — `search=patient.drug.openfda.product_ndc:"0078-0357"` works                                               |
|Total records                |**~18 million** safety reports                                                                                  |
|Rate limits                  |240 req/min; max 1,000 results/call; **26K pagination ceiling** (Elasticsearch hard limit)                      |
|Bulk alternative             |Downloadable JSON archives at open.fda.gov/data/downloads/                                                      |
|Semantic grain classification|**Report-native**                                                                                               |

**Critical implementation constraints:** The report-native grain creates a **many-to-many explosion** when joining to NDC-11: each report contains multiple drugs, each drug maps to multiple NDCs. There is no drug-reaction linkage within a report, making causal signal extraction impossible from this source alone.  The **26,000-record pagination ceiling** blocks full enumeration via API — bulk JSON downloads are mandatory for comprehensive ingestion. The incomplete `openfda` coverage means a significant fraction of reports will be un-joinable to NDC-11. 

**Verdict: PARTIALLY READY** — live, searchable, but requires bulk download pipeline (not simple API pagination), NDC normalization, and acceptance of incomplete NDC coverage. Best suited for signal-enrichment (adverse event counts per NDC) rather than as a primary analytical source.

-----

## Source 3: CMS Part D Formulary PUF — READY

**Download location:** `https://data.cms.gov/provider-summary-by-type-of-service/medicare-part-d-prescribers/monthly-prescription-drug-plan-formulary-and-pharmacy-network-information`

Direct download example (February 2026): `https://data.cms.gov/sites/default/files/2026-02/d20b96a8-8acb-43cc-91e0-4f0b94c1d3f0/2026_20260219.zip`

**File structure:** ZIP containing **8 pipe-delimited flat files** with headers — Plan Information, Geographic Locator, Basic Drugs Formulary, Excluded Drugs Formulary, Beneficiary Cost, Pharmacy Network, IBC Formulary, Insulin Beneficiary Cost.  Quarterly PUFs additionally include a Pricing file.  

**Basic Drugs Formulary File columns (the core file):**

|Column                  |Type        |Description                                                |
|------------------------|------------|-----------------------------------------------------------|
|`FORMULARY_ID`          |Char(8)     |Unique formulary identifier                                |
|`FORMULARY_VERSION`     |Char(5)     |Version identifier                                         |
|`CONTRACT_YEAR`         |Char(4)     |Contract year                                              |
|`RXCUI`                 |Char(8)     |RxNorm Concept Unique Identifier                           |
|**`NDC`**               |**Char(11)**|**11-digit proxy NDC — natively NDC-11**                   |
|`TIER_LEVEL_VALUE`      |Num(2)      |Cost-share tier level                                      |
|`QUANTITY_LIMIT_YN`     |Char(1)     |Quantity limit flag                                        |
|`QUANTITY_LIMIT_AMOUNT` |Char(7)     |Quantity limit amount                                      |
|`QUANTITY_LIMIT_DAYS`   |Char(3)     |Quantity limit days                                        |
|`PRIOR_AUTHORIZATION_YN`|Char(1)     |Prior authorization required flag                          |
|`STEP_THERAPY_YN`       |Char(1)     |Step therapy flag                                          |
|`SELECTED_DRUG_YN`      |New (2025+) |IRA Medicare Drug Price Negotiation selected drug indicator|

|Attribute                    |Finding                                                                             |
|-----------------------------|------------------------------------------------------------------------------------|
|Native grain                 |**Formulary-native** — one row = one FORMULARY_ID + NDC combination                 |
|Primary identifiers          |`FORMULARY_ID` + `NDC` (composite key)                                              |
|NDC-11 native?               |**Yes** — `NDC` column is Char(11), described as “11-digit proxy National Drug Code”|
|Also has RXCUI?              |Yes — both RXCUI and NDC-11 in same row, enabling bidirectional mapping             |
|Record count                 |Tens of millions per monthly file (~3,600+ plans × thousands of NDCs per formulary) |
|Update frequency             |Monthly (monthly PUF) and quarterly (quarterly PUF with pricing)                    |
|Auth required                |None — free public download, no login                                               |
|Available years              |CY2019–CY2026 (free); pre-2019 files can be purchased                               |
|Semantic grain classification|**Formulary-native**                                                                |

**The “proxy NDC” caveat:** CMS maps each RXCUI to a single representative NDC-11 via the Formulary Reference File.  This means the NDC is canonical, not necessarily the specific NDC dispensed. Multiple distinct NDC-11 codes may share an RXCUI, but each formulary row presents one proxy NDC per RXCUI. This is acceptable for formulary coverage analysis but should not be treated as dispensing-level data.

**High-value fields for the intelligence system:** The `PRIOR_AUTHORIZATION_YN`, `STEP_THERAPY_YN`, `QUANTITY_LIMIT_YN`, and `TIER_LEVEL_VALUE` fields — keyed to NDC — unlock **formulary access barrier analysis** at the NDC-11 grain.  The new `SELECTED_DRUG_YN` flag (IRA provision) identifies drugs subject to Medicare price negotiation.  Joining the Plan Information file via `FORMULARY_ID` adds geographic and premium dimensions.

**Verdict: READY** — native NDC-11, pipe-delimited flat files ideal for bash+python, monthly cadence, no auth barriers. **Highest-value new source** for the system.

-----

## Source 4: WHO ATC via RxClass API — READY

**Endpoints tested:**

- `https://rxnav.nlm.nih.gov/REST/rxclass/allClasses.json?classTypes=ATC1-4` → Returns ATC levels 1–4 classes
- `https://rxnav.nlm.nih.gov/REST/rxclass/classMembers.json?classId=N02BE&relaSource=ATCPROD` → Returns product-level RxCUIs
- `https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/ndcs.json` → Returns NDC-11 codes

**Fields from `allClasses`:** `classId` (ATC code), `className` (human-readable name), `classType` (“ATC1-4”). 

**Fields from `classMembers`:** `minConcept.rxcui`, `minConcept.name`, `minConcept.tty` (IN/SCD/SBD), `nodeAttr[].attrName` (SourceId, SourceName, Relation), `nodeAttr[].attrValue`.

**Fields from `getNDCs`:** `ndcGroup.ndcList.ndc` — array of **11-digit unhyphenated NDC strings** in CMS 5-4-2 format (e.g., “00069420030”). 

|Attribute                    |Finding                                                                                                    |
|-----------------------------|-----------------------------------------------------------------------------------------------------------|
|Native grain                 |**Terminology** — ATC class code is the native key (levels 1–4 only; level 5 appears as SourceId attribute)|
|Primary identifiers          |`classId` (ATC code) + `rxcui` at member level                                                             |
|NDC-11 native?               |**Yes at the end of the chain** — `getNDCs` returns 11-digit unhyphenated NDCs                             |
|Chain validation             |ATC → RxCUI → NDC-11 works end-to-end via 2-step API (using `relaSource=ATCPROD`)                          |
|Total ATC classes            |~1,200–1,400 (levels 1–4 combined)                                                                         |
|Rate limits                  |**20 requests/second** per IP (much tighter than openFDA)                                                  |
|Auth required                |None — no API key or UMLS license for API access                                                           |
|Update frequency             |Monthly (following RxNorm release, first Monday of month)                                                  |
|Semantic grain classification|**Terminology**                                                                                            |

**Two `relaSource` options matter:** Using `relaSource=ATC` returns ingredient-level RxCUIs (tty=IN) which **cannot** directly resolve to NDCs — an extra hop through `getRelatedByType` is required. Using **`relaSource=ATCPROD`** returns product-level RxCUIs (SCD/SBD) which resolve directly to NDCs via `getNDCs`.   ATCPROD is the preferred path, covering **>97% of Medicare Part D prescriptions**. 

**Implementation strategy for bulk mapping:** A full ATC-to-NDC crosswalk requires ~1,300 classMembers calls + thousands of getNDCs calls. At 20 req/sec, this takes roughly 5–10 minutes. Cache results and refresh monthly. Alternatively, use RxNav-in-a-Box (Docker local install, requires UMLS license) for zero-latency bulk operations.  

**Verdict: READY** — the ATC→RxCUI→NDC-11 chain works end-to-end, NDC-11 is returned natively, and the API is free with no auth. The 20 req/sec rate limit is manageable with caching.

-----

## Source 5: CMS ASP Pricing + NDC-HCPCS Crosswalk — READY

**Download location:** `https://www.cms.gov/medicare/payment/part-b-drugs/asp-pricing-files` — contains both file types per quarter.

**File format:** ZIP archives containing Excel spreadsheets (XLS/XLSX). Click-through license agreement required (no account needed).

**ASP Pricing File columns:** `HCPCS Code`, `Short Description`, `HCPCS Code Dosage`, `Payment Limit` (106% of ASP per billable unit), `Vaccine AWP%`, `Notes`. Some recent files add a `Co-insurance` column. Starting Q1 2026, renamed to “Medicare Part B Payment Limit Files.”

**NDC-HCPCS Crosswalk columns:** `HCPCS Code`, `NDC` (11-digit, 5-4-2 with dashes), `Drug Name`, `Package Size`, `Billable Units Per 11-Digit NDC`. 

|Attribute                    |Finding                                                                                                 |
|-----------------------------|--------------------------------------------------------------------------------------------------------|
|ASP Pricing grain            |**HCPCS-native** — one row per HCPCS code per quarter (~600–800 codes)                                  |
|Crosswalk grain              |**NDC-to-HCPCS mapping** — one row per NDC-11 to HCPCS pair (thousands of rows)                         |
|NDC-11 native?               |**Yes** — crosswalk `NDC` column is explicitly “11-Digit National Drug Code” in 5-4-2 hyphenated format |
|HCPCS as join key            |Yes — present in both files, enabling NDC-11 → HCPCS → Payment Limit lookup                             |
|Update frequency             |Quarterly (January, April, July, October), with retroactive revisions                                   |
|Auth required                |Click-through license only, no account                                                                  |
|Most recent file             |April 2026 (finalized 2026-03-19)                                                                       |
|Semantic grain classification|**HCPCS-native** (pricing file) / **package-native** (crosswalk)                                        |

**This source unlocks the existing Part B spending data.** The current system already has Medicare Part B Spending by Drug at HCPCS grain. The crosswalk provides the missing **HCPCS→NDC-11 bridge**, enabling Part B spending figures to be mapped down to package-level.  The `Billable Units Per 11-Digit NDC` field enables unit-cost calculations at the NDC-11 grain. 

**Implementation note:** Dashes in the NDC column must be stripped for numeric matching (`00069-4200-30` → `00069420030`).  Some rows contain “Alternate IDs” for non-drug products (skin substitutes) rather than standard NDCs — filter these during ingestion.

**Verdict: READY** — native NDC-11, quarterly cadence, direct HCPCS bridge, small file sizes. Excel-to-CSV conversion via `ssconvert` or `openpyxl` in the flat-script pipeline.

-----

## Source 6: CMS Part D Prescribers by Provider and Drug — PARTIALLY READY

**Dataset location:** `https://data.cms.gov/provider-summary-by-type-of-service/medicare-part-d-prescribers/medicare-part-d-prescribers-by-provider-and-drug`

**Dataset IDs (CMS Data API UUID, not Socrata):** 2023: `9552739e-3d05-4c1b-8eff-ecabf391e2e5`; 2022: `b101f457-ffa4-49bb-8fd9-27c1266086e2`. API pattern: `https://data.cms.gov/data-api/v1/dataset/{UUID}/data`

**All 22 columns:**

|Column                 |Description                       |
|-----------------------|----------------------------------|
|`Prscrbr_NPI`          |National Provider Identifier      |
|`Prscrbr_Last_Org_Name`|Prescriber last/org name          |
|`Prscrbr_First_Name`   |Prescriber first name             |
|`Prscrbr_City`         |City                              |
|`Prscrbr_State_Abrvtn` |State abbreviation                |
|`Prscrbr_State_FIPS`   |State FIPS code                   |
|`Prscrbr_Type`         |Provider specialty                |
|`Prscrbr_Type_Src`     |Specialty source                  |
|`Brnd_Name`            |Brand name (from First Databank)  |
|`Gnrc_Name`            |Generic name (from First Databank)|
|`Tot_Clms`             |Total Part D claims               |
|`Tot_30day_Fills`      |Total 30-day fill count           |
|`Tot_Day_Suply`        |Total days supply                 |
|`Tot_Drug_Cst`         |Total drug cost                   |
|`Tot_Benes`            |Total beneficiaries               |
|`GE65_Sprsn_Flag`      |Suppression flag (≥65 subgroup)   |
|`GE65_Tot_Clms`        |Claims (≥65)                      |
|`GE65_Tot_30day_Fills` |30-day fills (≥65)                |
|`GE65_Tot_Drug_Cst`    |Drug cost (≥65)                   |
|`GE65_Tot_Day_Suply`   |Days supply (≥65)                 |
|`GE65_Bene_Sprsn_Flag` |Beneficiary suppression (≥65)     |
|`GE65_Tot_Benes`       |Beneficiaries (≥65)               |

|Attribute                    |Finding                                                                                                                        |
|-----------------------------|-------------------------------------------------------------------------------------------------------------------------------|
|Native grain                 |**Provider-native** — one row = `Prscrbr_NPI` + `Brnd_Name` + `Gnrc_Name` per calendar year                                    |
|Primary identifiers          |NPI + drug name strings (no structured drug code)                                                                              |
|NDC-11 native?               |**No — NDC is completely absent**. Drug identification is exclusively by `Brnd_Name`/`Gnrc_Name` text strings                  |
|Bridging difficulty          |**High** — requires fuzzy name matching via RxNorm or First Databank; many-to-many: one drug name maps to multiple NDC-11 codes|
|Dataset size                 |**~25 million rows** per year (2–4 GB CSV)                                                                                     |
|Available years              |2013–2023 (11 annual files)                                                                                                    |
|Auth required                |None                                                                                                                           |
|Semantic grain classification|**Provider-native**                                                                                                            |

**The fundamental problem:** CMS aggregates the underlying PDE (Prescription Drug Event) claims — which do contain NDC-11 in the `PROD_SRVC_ID` field  — up to the drug-name level before publishing this PUF. All package/strength/formulation variation is collapsed. Bridging back to NDC-11 is inherently lossy because one `Gnrc_Name` string like “Atorvastatin Calcium” maps to dozens of distinct NDC-11 codes across manufacturers, strengths, and package sizes. No deterministic join is possible.

**Verdict: PARTIALLY READY** — rich provider-level utilization data but fundamentally grain-incompatible with an NDC-11 system. Useful only for provider-level analytics (prescribing patterns, specialty concentration) where drug-name-level granularity is acceptable, or as context enrichment after accepting the lossy name-to-NDC bridge.

-----

## Consolidated readiness matrix

|Source                       |Verdict            |NDC-11 Native           |Grain               |Bridge Required         |Priority       |
|-----------------------------|-------------------|------------------------|--------------------|------------------------|---------------|
|CMS Part D Formulary PUF     |**READY**          |✅ Yes (Char 11)         |Formulary + NDC     |None                    |**1 — Highest**|
|CMS ASP + NDC-HCPCS Crosswalk|**READY**          |✅ Yes (5-4-2 hyphenated)|NDC→HCPCS map       |Strip dashes only       |**2 — High**   |
|FDA Drug Shortages           |**READY**          |❌ (10-digit)            |Package shortage    |Zero-pad 10→11          |**3 — Medium** |
|WHO ATC via RxClass          |**READY**          |✅ (at chain end)        |Terminology class   |2-hop API chain         |**4 — Medium** |
|openFDA FAERS                |**PARTIALLY READY**|❌ (10-digit, incomplete)|Safety report       |Zero-pad + bulk download|**5 — Lower**  |
|CMS Part D Prescribers       |**PARTIALLY READY**|❌ (absent entirely)     |Provider + drug name|Lossy name matching     |**6 — Lowest** |

-----

## Five grain-safe derived KPIs from existing sources

These KPIs require **no new sources** and are computable entirely from already-implemented data (NADAC, SDUD, openFDA NDC, CMS spending files). Each respects the native grain of its inputs.

**1. NADAC price velocity (NDC-11 grain, temporal).** Compute the rolling 90-day rate of change in NADAC `nadac_per_unit` for each `ndc` value. NADAC is updated weekly and carries `effective_date`, `as_of_date`, and `pricing_unit` natively. The derivative `Δ(nadac_per_unit) / Δ(effective_date)` at the NDC-11 grain identifies drugs with accelerating or decelerating acquisition costs. Flag NDCs where the 90-day annualized velocity exceeds **±20%** as pricing anomalies. This is grain-safe because NADAC is package-native with NDC as its primary key.

**2. Medicaid reimbursement-to-NADAC spread (NDC-11 × state grain).** Join SDUD’s `total_amount_reimbursed / units_reimbursed` to NADAC’s `nadac_per_unit` on NDC-11. The spread `(SDUD_cost_per_unit − NADAC_per_unit) / NADAC_per_unit` reveals which NDCs and states show the largest reimbursement-over-acquisition gaps. Both SDUD and NADAC are package-native; SDUD adds the state dimension. This KPI is defensible because both numerator and denominator reference the same NDC-11 grain — no aggregation bridging is needed.

**3. State utilization concentration index (NDC-11 grain, geographic).** From SDUD, compute a Herfindahl-Hirschman Index (HHI) across states for each NDC-11: `HHI = Σ(state_share²)` where `state_share = state_units / national_units` for each `ndc`. Low HHI indicates broad geographic distribution; high HHI flags regionally concentrated utilization (potential supply chain or formulary concentration risk). SDUD is both state-native and package-native, making this a fully grain-safe geographic dispersion metric.

**4. Generic-to-brand NADAC ratio by product (product-level, derived from NDC-11).** Using the openFDA NDC directory’s `openfda.product_type` and `nonproprietary_name` fields (already fetched), group NDC-11 codes into brand/generic clusters for the same active ingredient. Then compute `median(NADAC_generic) / median(NADAC_brand)` per ingredient. This ratio tracks generic pricing efficiency. Both the grouping (openFDA NDC) and pricing (NADAC) sources operate at NDC-11 grain; the aggregation to ingredient level is an explicit, documented rollup.

**5. Medicare-to-Medicaid spending divergence (brand-name grain).** Compare CMS Medicare Part D Spending by Drug (`total_spending` and `total_dosage_units`) against CMS Medicaid Spending by Drug on matching `brand_name`/`generic_name` strings. Both sources are program-summary at brand level — the same native grain. The ratio `Medicare_cost_per_unit / Medicaid_cost_per_unit` for the same drug identifies systematic cross-program pricing disparities. This is grain-safe because both sources share the identical brand-name aggregation level; no downward bridging to NDC-11 is attempted.

-----

## Underused fields in existing sources

Several fields already returned by the implemented source adapters carry analytical value that the current `ndc_source_matrix.sh` and `ndc_geo_matrix.sh` scripts likely do not surface.

**NADAC underused fields.** The `classification_for_rate_setting` field (values: G=generic, B=brand, OTC) provides an authoritative generic/brand classification at the NDC level that most systems derive indirectly from openFDA. The `explanation_code` field flags non-standard pricing methodologies (e.g., when NADAC cannot be computed from survey data and a proxy is used). The `otc` flag (Y/N) identifies over-the-counter status. The `effective_date` and `as_of_date` pair enables point-in-time historical reconstruction, but scripts that only fetch the latest snapshot discard this temporal dimension.

**SDUD underused fields.** The `suppression_used` flag indicates whether CMS applied data suppression (values below 11 claims), which affects utilization totals — ignoring it introduces systematic downward bias in low-volume NDC estimates. The `product_name` field provides the CMS-canonical drug name at the NDC level (distinct from openFDA’s `brand_name`), useful for cross-source name reconciliation. The `number_of_prescriptions` vs. `units_reimbursed` distinction enables average-prescription-size calculations not available from any other source.

**openFDA NDC underused fields.** The `pharm_class` array (EPC, MoA, PE, CS sub-classifications from NDF-RT) provides therapeutic classification without needing the RxClass ATC chain.   The `dea_schedule` field identifies controlled substance scheduling (CII–CV).  The `listing_expiration_date` indicates whether an NDC listing is still active or lapsed  — critical for identifying withdrawn or discontinued products.  The `package_ndc` → `description` field contains package-size text (e.g., “100 TABLET in 1 BOTTLE”) that enables unit-of-use inference. 

**MDRP Product File underused fields.** The `FDA_Therapeutic_Equivalence_Code` (TE code, e.g., AB, BX) is the FDA’s substitutability rating — essential for generic interchange analysis but not typically surfaced. The `COD_Status` (change of data) flag tracks manufacturer-reported data corrections. The `Unit_Type` field (e.g., TAB, CAP, ML, GM) standardizes the billing unit, enabling cross-source unit normalization between NADAC (which uses `pricing_unit`) and SDUD (which uses `unit_type` implicitly).

**Medicare Part B Spending underused fields.** The `average_total_cost_per_dosage_unit` field already contains a pre-computed cost metric that could be directly compared against ASP payment limits once the HCPCS crosswalk is implemented, without requiring raw claim-level calculation.

-----

## Implementation sequencing recommendation

The optimal integration order, considering value delivered per engineering effort:

1. **CMS Part D Formulary PUF** — native NDC-11, pipe-delimited (bash-native), unlocks formulary coverage/access-barrier analytics.  A single `wget | unzip | awk -F'|'` pipeline suffices for the Basic Drugs Formulary file.
1. **CMS ASP NDC-HCPCS Crosswalk** — native NDC-11, unlocks the already-implemented Part B spending data at the NDC level. Requires `openpyxl` or `ssconvert` for the Excel-to-CSV step, then standard pipeline processing.
1. **FDA Drug Shortages** — trivial integration (same openFDA adapter pattern as existing NDC and Drugs@FDA endpoints, same NDC normalization logic). Only 1,679 records. Adds a high-signal binary shortage flag.
1. **RxClass ATC** — extends the existing RxNav adapter. Build a cached ATC→NDC-11 crosswalk table refreshed monthly. Adds therapeutic classification as a filterable dimension.
1. **FAERS** — defer to a Phase 2 implementation. Requires bulk JSON download infrastructure (not simple API pagination) and acceptance of incomplete NDC coverage.  The analytical value (adverse event signal enrichment) is meaningful but the engineering cost is substantially higher than Sources 1–4.
1. **Part D Prescribers** — defer or deprioritize. The absence of NDC and the lossy name-matching bridge make this source grain-incompatible with the core NDC-11 system. Consider only if provider-level analytics become a stated requirement.