# NDC Intelligence System - Master Context

Version: 2.1 (2026-09-24)
Supersedes: BOOTSTRAP.md v1 (85 lines, February layout) as the session loader.
Scope: everything needed to resume work on the NDC scripts without re-auditing: environment, full development history, current file state, architecture, sources, rules, today's patches, the open-issue register, and the roadmap.

---

## 0. How to use this document

**New session, read in this order:**
1. Sections 0 to 2 (what this is, where it runs).
2. Section 9 (known-issue register) before touching any code, so fixed bugs are not reintroduced and open ones are not rediscovered from scratch.
3. Sections 5 to 7 (architecture, sources, schemas, rules) and section 8 (latest patches) as reference.
4. Section 3 (history) only when the reason behind a decision matters.

**Order of authority when sources disagree:**
1. The code in `commands/` (implementation truth).
2. This document.
3. `reference/source-log.md` (endpoint and field registry).
4. `reference/ndc-system-extension.md` (analysis, KPI design, forbidden shortcuts).
5. `README.md` (human orientation; paths inside it are partly stale, see section 11).

**Rule for every future session:** when code changes, update section 9 (issue status) and section 13 (changelog) in the same session. A stale loader is worse than none, because the next session trusts it.

---

## 1. Project summary

A set of command-line tools that take an NDC input (company labeler, product, or package) and build package-grain (NDC-11) intelligence from free U.S. federal APIs: FDA, CMS, Medicaid (data.medicaid.gov), NLM, and California HCAI.

- **Row grain:** NDC-11 (package). State x NDC-11 in the geo tables.
- **Data:** public APIs only. No internal, proprietary or licensed data anywhere in the repo or outputs.
- **Dependencies:** Python 3 standard library only (`openpyxl` optional for the geo workbook).
- **Design principle:** source-grain honesty. Every value is labelled by where it came from and at what grain; brand-level facts are never presented as package facts; national facts are never presented as state facts.
- **Status:** working, run successfully end to end on the VPS; five data-integrity fixes applied on 2026-09-24 (section 8); a documented backlog of open issues (section 9).

**Ownership and governance note.** Personal project on public data. Repo is private (changed 2026-09-23). Before running it on company hardware or proposing it as a departmental asset, check the employer's policy on personally developed code, approved AI tools, and use of personal servers from corporate devices. Neutralise company-specific defaults first (section 11).

---

## 2. Environment and infrastructure

### 2.1 Repository
- GitHub: `lakuna7/NDC-Mapping`, branch `claude` (must also be the default branch for the Actions workflow to appear). Visibility: private. Formerly named `lakuna7/Files-for-memory-refresh`; GitHub redirects the old URL, so older clones keep working.
- Clone (fresh host):
  ```
  git clone -b claude https://github.com/lakuna7/NDC-Mapping.git ~/my-ndc-project
  ```
- Existing clone made under the old name: optional cleanup with
  ```
  cd ~/my-ndc-project && git remote set-url origin https://github.com/lakuna7/NDC-Mapping.git
  ```
- Purpose of the repo: memory preservation of code and reference docs only. Outputs never go to GitHub.
- `.gitignore` at root:
  ```
  exports/
  local-data/
  ```
- Repo structure after the Copilot restructure (merged PR, +2,084 / -3,570 lines, 30 files):
  ```
  commands/
    ndc_source_matrix.sh
    ndc_geo_matrix.sh
    ndc_shortages.sh
    ndc_derived_kpis.sh
  reference/
    source-log.md
    ndc-system-extension.md
    repo-audit.md
  BOOTSTRAP.md
  README.md
  .gitignore
  ```
- Added on 2026-09-24 by direct upload: `ndc_lookup.sh`, `run.py`, the patched scripts, the project-layout `ndc_derived_kpis.sh` (resolves I-21), `.github/workflows/ndc-run.yml`, this document.
- GitHub shows a "hidden or bidirectional Unicode" warning on `BOOTSTRAP.md` and `.gitignore`. It comes from markdown characters, is harmless for `.md` files, and would only matter on a `.sh` file. This document is written in plain ASCII to avoid it.

### 2.2 Execution host (VPS)
- Hostname `pharma-mvp`, user `root`. Accessed by SSH (address kept in your SSH client, deliberately not recorded here).
- Clients: Termius on mobile; PowerShell `ssh` from a Windows laptop.
- Home directory was fully cleaned (old scripts, probe logs, failed Copilot clones, old per-run output dirs removed). Hidden config (`.ssh`, `.bashrc`, `.profile` and similar) kept.
- Project clone: `~/my-ndc-project` (clone of `lakuna7/NDC-Mapping`, branch `claude`).
- A separate, unrelated website repo (`Pharma-Intelligence-Platform`) was removed from the host; re-clone from GitHub if needed. Two repos on one host do not interfere; each folder has its own `.git`.
- Disk: 47 GB volume; about 12 GB free after the formulary download.
- Tools installed: `git`, `python3`, `unzip` (installed with `apt install -y unzip`).

### 2.3 Project layout on the host
```
~/my-ndc-project/
  commands/            scripts; run everything from here
  exports/
    tables/            CSV outputs (source_matrix_<INPUT>/, geo_matrix_<INPUT>/,
                       shortages_<INPUT>/, derived_kpis/)
    logs/              resolution.json, run_log_*.json
    debug/             manifest, xlsx workbook
  local-data/
    cache_*            SHA-256 URL-keyed HTTP cache per script and input
    cms-formulary/     2026_20260219.zip (2.15 GB, CY2026 Feb release)
                       PUFRecordLayout-2026.pdf, Methodology-PUF-2026.pdf
```
`exports/` and `local-data/` are created automatically on first run.

### 2.3b GitHub Actions runner (preferred way to run, from 2026-09-24)
- Workflow `.github/workflows/ndc-run.yml`, triggered manually ("Run workflow") from the Actions tab, including from a phone browser.
- Inputs: `ndc` (validated against NDC formats), `scripts` (all, source_matrix, geo_matrix, shortages, lookup), `include_wac` (default off; WAC usually returns 403 from cloud runners).
- Runs on GitHub's Ubuntu runners with Python 3.12; no server needed. API responses cached between runs per NDC (`actions/cache`).
- Results: a summary table on the run page (the verification columns from section 14, shortage flags, derived KPIs, geo warnings) plus the full `exports/` folder as a downloadable artifact kept 30 days.
- Optional repo secret `OPENFDA_API_KEY` for higher openFDA rate limits.
- Budget: private repos on the free plan include 2,000 Actions minutes per month.
- The VPS remains useful only for the 2.2 GB formulary file and ad hoc debugging; GitHub Codespaces is the browser alternative for editing and testing.

### 2.4 Windows laptop
- Bash is unavailable, so `commands/run.py` extracts the Python embedded in each `.sh` and runs it with the same environment variables. The `.sh` files are not modified.
- Remote use from Windows: `ssh root@<host>` from PowerShell, then run exactly as on the VPS.
- Governance: see the note in section 1 before using company hardware.

### 2.5 Hard-won operational rules
1. **Never copy-paste scripts through iOS or macOS text fields.** Smart Punctuation converts ASCII quotes to typographic quotes and destroys indentation; two scripts were corrupted this way (413 and 486 bad characters). Always use the file download button, or switch off Settings > General > Keyboard > Smart Punctuation.
2. **Verify every script is pure ASCII before running:** `grep -cP '[\x80-\xff]' file.sh` must print 0.
3. **Syntax-check before running:**
   ```
   bash -n script.sh && echo "BASH OK"
   python3 -c "import sys; sys.path.insert(0,'.'); from run import extract_python; \
     open('/tmp/_c.py','w').write(extract_python('script.sh'))" && \
     python3 -m py_compile /tmp/_c.py && echo "PY OK"
   ```
4. **Outputs stay on the host.** Regenerable in seconds; never commit them.
5. **Repo maintenance from mobile:** the GitHub Copilot coding agent (assign an issue, it opens a PR) worked well for the restructure. GitHub may refuse `.sh` attachments on issues; zip them first.

---

## 3. Development history (chronological)

Reconstructed from the development thread and the 2026-09-23/24 review session.

**3.1 Source matrix rebuild (v2).** The original `ndc_source_matrix_full_command.sh` was replaced by a nine-phase script: input resolution, base matrix, fetch plans, parallel fetch, package-native enrichment, brand-level enrichment, brand-to-NDC-11 projection, output. Ten explicit improvements over the original:
1. A status column per source (`src_X_status`), not only a 0/1 flag.
2. NADAC and SDUD exact-match validation: the returned NDC is re-extracted and compared digit for digit; mismatch becomes `bad_filter`.
3. SDUD NDC reconstruction from `labeler_code` + `product_code` + `package_size`.
4. WAC exact-match validation.
5. Medicaid endpoints moved to the documented datastore query API.
6. About 85 focused columns instead of 90+ redundant ones.
7. Console status histogram per source.
8. A compact CSV for quick scanning.
9. All URLs deduplicated into two batch fetches.
10. Clean separation of HTTP errors from empty-but-valid responses.

**3.2 Smart-quote rebuild.** A first artifact was unusable: curly quotes throughout, broken heredoc terminator, corrupted indentation, markdown leakage in a regex, `.strip()` called on a `Path`. Rebuilt from scratch with `_s()` / `_ss()` wrappers that make None, bool and int safe everywhere; 0 non-ASCII bytes; `bash -n` and `py_compile` both pass.

**3.3 Geo matrix.** `ndc_geo_matrix.sh` built on one constraint: only SDUD is genuinely state-native at package grain. 51 rows (50 states + DC) per NDC-11, always present; SDUD populates state measures; NADAC appears only as national reference columns; FFSU and MCOU kept separate; suppression flag detected; 11 sources explicitly excluded with reasons (Part D, Part B, Medicaid Spending, WAC, Drugs@FDA, RxNav, DailyMed, Orange Book, Purple Book, MDRP, ACA FUL).

**3.4 Two research reports on candidate sources.** First: 12 candidates (six implementation-ready, four partial, one blocked, one redundant). Second: six candidates against the system's grain rules: Part D Formulary PUF, ASP NDC-HCPCS crosswalk, FDA Drug Shortages and RxClass ATC rated integration-ready; FAERS and Part D Prescribers partial.

**3.5 Extension document and Phase 1 implementation.** Produced `ndc-system-extension.md` (nine sections: audit ledger, system truth, source validation, KPI opportunities, grain integrity, derived analytics, priority map, implementation pack, ten forbidden shortcuts). Written without network access; readiness ratings rest on documentation and earlier run outputs, not live tests. Implemented:
- `ndc_derived_kpis.sh`: five KPIs from existing outputs, no API calls.
- `ndc_shortages.sh`: FDA Drug Shortages flag per NDC-11.
Deferred: FAERS, Formulary PUF, Part D Prescribers, RxClass ATC (reasons in section 10).

**3.6 README.** 400-line human-facing documentation: sources, data dictionary, methodology, architecture, run commands, environment variables, "what this system does not do".

**3.7 Repo audit and BOOTSTRAP v1.** Findings: two scripts corrupted by smart quotes (and indentation loss, so not fixable by find-replace); redundant outputs and binaries in the repo; no session loader. Produced `repo-audit.md` and the 85-line `BOOTSTRAP.md`. Root cause identified as iOS Smart Punctuation during copy-paste.

**3.8 Project-layout update.** All four scripts changed to derive `PROJECT_ROOT` from their own location (`commands/` -> parent) and write to `exports/tables`, `exports/logs`, `exports/debug`, `local-data`. `ndc_derived_kpis.sh` gained `INPUT=` auto-detection of its input folders.

**3.9 Copilot restructure.** A GitHub issue with an explicit file mapping was handed to the Copilot coding agent, which opened a PR; merged. **Error introduced here, found on 2026-09-24:** the mapping told Copilot to use the `_clean` copies of `ndc_shortages.sh` and `ndc_derived_kpis.sh`, on the belief that the other copies were the corrupted ones. In fact the non-`_clean` copies were the newer project-layout versions and are pure ASCII; the `_clean` copies are the older layout. The repo therefore holds old-layout shortages and derived-KPI scripts (issue I-21).

**3.10 Host cleanup and first clean run.** Old files removed, fresh clone to `~/my-ndc-project`, `INPUT="0006-0277" bash ndc_source_matrix.sh` ran end to end. Outputs landed in `exports/`.

**3.11 `ndc_lookup.sh`.** Lightweight pre-flight browser: one paginated openFDA call, no cache, prints the company / product / package tree and suggests next commands. Accepts numeric NDC input only; brand-name search noted as a next step.

**3.12 CMS Part D Formulary PUF download.** CY2026 February release (2.15 GB ZIP) plus record layout and methodology PDFs placed in `local-data/cms-formulary/`. January release deleted for disk space. Plan: extract only the Basic Drugs Formulary table, which carries NDC-11, when building the Phase 2 adapter.

**3.13 `run.py` Windows launcher.** Extracts the heredoc Python from each `.sh` and executes it with the correct environment; aliases for every command. This is effectively step one of moving the Python out of heredocs.

**3.14 Review session (2026-09-23/24).** Full read of every script; fifteen methodology issues identified; inventory of new files; five high-impact fixes applied and unit-tested (section 8); extension document re-read against the code, surfacing four further issues, including the source-matrix suppression and FFSU/MCOU gap; BOOTSTRAP v1 found stale; this document written.

---

## 4. File inventory (state on 2026-09-24)

| File | Lines | Layout | State | Notes |
|---|---|---|---|---|
| `ndc_source_matrix.sh` | 1,194 | project | **Patched 2026-09-24** | SDUD pagination, XX exclusion, NADAC sort, Part B Overall, 3 new columns |
| `ndc_geo_matrix.sh` | 1,009 | project | **Patched 2026-09-24** | SDUD pagination, XX exclusion, NADAC sort, completeness warnings |
| `ndc_shortages.sh` | 631 | project | **Patched 2026-09-24** | Displayed record taken from current records; real date parsing |
| `ndc_derived_kpis.sh` | 425 | project | Unchanged | Accepts `INPUT=`; writes to `exports/tables/derived_kpis/` |
| `ndc_lookup.sh` | 446 | project | Unchanged | Pre-flight family browser; not yet in repo |
| `run.py` | 240 | n/a | Unchanged | Windows launcher; not yet in repo |
| `ndc_shortages_clean.sh` | 605 | **old** | Obsolete | Byte-identical to the old repo version; delete |
| `ndc_derived_kpis_clean.sh` | 409 | **old** | Obsolete | Byte-identical to the old repo version; delete |
| `BOOTSTRAP.md` | 85 | n/a | Stale | Superseded by this document |
| `README.md` | 400 | n/a | Partly stale | Run paths point at old `~/ndc_*` folders |
| `reference/source-log.md` | ~590 | n/a | Needs cleanup | Contains an illustrative KEYTRUDA Part D row with invented figures |
| `reference/ndc-system-extension.md` | 390 | n/a | Needs cleanup | Stale paths; "$945/unit for JANUVIA" example |
| `reference/repo-audit.md` | 145 | n/a | Historical | Its "critical" encoding problem is resolved |

All scripts: 0 non-ASCII bytes, `bash -n` passes, embedded Python compiles.

**Repo versus working copies.** The repo's `commands/ndc_shortages.sh` and `commands/ndc_derived_kpis.sh` are the old-layout versions (issue I-21). The project-layout versions are the non-`_clean` files. The three patched scripts from 2026-09-24 must replace their repo counterparts.

---

## 5. Architecture and usage

### 5.1 Scripts
| Script | Purpose | Input | Main outputs |
|---|---|---|---|
| `ndc_lookup.sh` | Pre-flight family browser | `INPUT` | Console tree + suggested commands |
| `ndc_source_matrix.sh` | Multi-source package matrix | `INPUT` | `exports/tables/source_matrix_<INPUT>/ndc11_source_matrix.csv`, `ndc11_compact.csv`; `exports/logs/resolution_source_matrix_<INPUT>.json` |
| `ndc_geo_matrix.sh` | State-level Medicaid utilization | `INPUT` | `exports/tables/geo_matrix_<INPUT>/state_tables/state_<ndc11>.csv`; `exports/debug/manifest_geo_<INPUT>.csv`, `ndc_geo_matrix_<INPUT>.xlsx`; `exports/logs/run_log_geo_<INPUT>.json` |
| `ndc_shortages.sh` | FDA shortage flag per package | `INPUT` | `exports/tables/shortages_<INPUT>/ndc11_shortages.csv`; `exports/logs/run_log_shortages_<INPUT>.json` |
| `ndc_derived_kpis.sh` | Five derived KPIs, no API calls | `INPUT` or `MATRIX_DIR` + `GEO_DIR` | `exports/tables/derived_kpis/ndc11_derived_kpis.csv` (not keyed by input: see I-29) |

### 5.2 Input scopes
- Company: labeler code, e.g. `"0006"`.
- Product: `"0006-0277"` (hyphenated recommended; unhyphenated 8-digit input is ambiguous, see I-13).
- Package: `"0006-0277-02"` or 11 digits `"00006027702"`.
Scripts resolve every scope to the full set of matching NDC-11 packages through openFDA, then post-filter strictly (prefix for company, NDC-9 equality for product, exact NDC-11 for package).

### 5.3 Run commands
Bash (VPS):
```
cd ~/my-ndc-project/commands
INPUT="0006-0277" bash ndc_lookup.sh
INPUT="0006-0277" bash ndc_source_matrix.sh
INPUT="0006-0277" bash ndc_geo_matrix.sh
INPUT="0006-0277" bash ndc_shortages.sh
INPUT="0006-0277" bash ndc_derived_kpis.sh     # after source_matrix and geo_matrix
```
Windows (`run.py`, from `commands/`):
```
python run.py lookup 0006-0277        # aliases: look, lu
python run.py sm 0006-0277            # source_matrix: matrix, sm
python run.py geo 0006-0277           # geo_matrix: geo, gm
python run.py short 0006-0277         # shortages: short, sh
python run.py kpi 0006-0277           # derived_kpis: kpi, kpis, dk
python run.py help
```
`run.py` flags: `--api-key KEY`, `--workers N`, `--cache-ttl H`, `--no-wac`, `--matrix-dir DIR`, `--geo-dir DIR`.

### 5.4 Environment variables
| Variable | Default | Used by | Meaning |
|---|---|---|---|
| `INPUT` | `0006` (to be removed, I-23) | all | NDC scope |
| `OPENFDA_API_KEY` | empty | all fetching scripts | Higher openFDA rate limits |
| `MAX_WORKERS` | 8 | matrix, geo, shortages | Parallel fetch threads |
| `CACHE_TTL_HOURS` | 24 | matrix, geo, shortages | Cache freshness; 0 disables cache reads |
| `INCLUDE_WAC` | 1 | source matrix | Query California WAC (fails from cloud, see 6.3) |
| `PROJECT_ROOT` | parent of `commands/` | all | Root for `exports/` and `local-data/` |
| `MATRIX_DIR`, `GEO_DIR` | derived from `INPUT` | derived KPIs | Explicit input folders |

### 5.5 Source-matrix pipeline
1. Input detection and normalisation.
2. openFDA family resolution (paginated, post-filtered).
3. Base matrix: one row per unique NDC-11; identity merged across duplicate openFDA rows.
4. Fetch plans: package-native URLs keyed by NDC-11; brand-level URLs keyed by brand.
5. Parallel fetch (thread pool, SHA-256 URL-keyed cache, retries with backoff). Since 2026-09-24: NADAC via `fetch_nadac_latest`, SDUD via `fetch_medicaid_all`.
6. Package-native enrichment with exact-match validation (NADAC, SDUD, WAC).
7. Brand-level enrichment (Drugs@FDA, RxNav, DailyMed, Part D, Medicaid Spending, Part B); Overall rows preferred via `pick_ov`.
8. Projection of brand-level values onto every NDC-11 of that brand, with status columns.
9. Output: full CSV, compact CSV, resolution JSON, console status histogram.

### 5.6 Shared helpers added 2026-09-24 (source and geo matrix)
- `medicaid_url(dataset_id, ndc11, limit, offset, sort_prop=None, sort_order="desc")`
- `fetch_medicaid_all(dataset_id, ndc11)`: full pagination. The offset advances by rows actually received, so a server page cap below 500 cannot skip rows. Returns `_completeness`, `_pages`, `_total_reported`.
- `fetch_nadac_latest(ndc11)`: server-side `effective_date` descending, automatic fallback to the unsorted query; sets `_sort`.
- `fetch_parallel(fn, keys)`: thread-pool map over keys.
- Constants: `NADAC_DATASET`, `SDUD_DATASET`, `MEDICAID_PAGE_SIZE = 500`, `MEDICAID_MAX_PAGES = 40`, `NATIONAL_STATE_CODES = {"XX"}`.
These make any further data.medicaid.gov adapter (for example MDRP) a few lines of code.

---

## 6. Sources

### 6.1 Implemented
| Source | Endpoint / dataset | Native grain | NDC-11 native | Classification | Used in |
|---|---|---|---|---|---|
| openFDA NDC | `api.fda.gov/drug/ndc.json` | package_ndc | Yes | regulatory | all |
| Drugs@FDA | `api.fda.gov/drug/drugsfda.json` | application_number | Via brand | regulatory | source matrix |
| RxNav / RxNorm | `rxnav.nlm.nih.gov/REST/drugs.json` | rxcui | Via brand | terminology | source matrix |
| DailyMed v2 | `dailymed.nlm.nih.gov/.../spls.json` | spl_set_id | Via brand | label document | source matrix |
| NADAC | data.medicaid.gov `fbb83258-11c7-47f5-8b18-5f8e79f7e704` | NDC-11 + effective_date | Yes | package-native price | source, geo |
| SDUD | data.medicaid.gov `61729e5a-7aa8-448c-8903-ba3e0cd0ea3c` (a single year, 2024) | NDC-11 + state + year + quarter + utilization type | Yes | state- and package-native | source, geo |
| WAC (CA HCAI) | data.chhs.ca.gov CKAN `3a133d3f-...` (current), `2fe618fd-...` (history) | NDC-11 + effective date (increase events) | Yes | package-native event | source matrix |
| Part D Annual | data.cms.gov `7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b` | Brnd_Name + year | No | program summary | source matrix |
| Part D Quarterly | data.cms.gov `4ff7c618-4e40-483a-b390-c8a58c94fa15` | Brnd_Name + year + quarter | No | program summary | source matrix |
| Medicaid Spending | data.cms.gov `be64fce3-e835-4589-b46b-024198e524a6` | Brnd_Name + year | No | program summary | source matrix |
| Part B Annual | data.cms.gov `76a714ad-3a2c-43ac-b76d-9dadf8f7d890` | HCPCS + year | No | HCPCS-native | source matrix |
| Part B Quarterly | data.cms.gov `bf6a5b3b-31ee-4abb-b1ad-2607a1e7510a` | HCPCS + year + quarter | No | HCPCS-native | source matrix |
| FDA Drug Shortages | `api.fda.gov/drug/shortages.json` | shortage presentation | Via zero-padding | package-native | shortages |

### 6.2 Status semantics
| Status | Meaning |
|---|---|
| `hit` | Data found and, for package-native sources, exact-matched digit for digit |
| `no_data` | Queried, nothing returned (or, for SDUD since 2026-09-24, only national rows matched) |
| `no_match` | Brand-level records returned but none matched |
| `bad_filter` | Records returned but none matched the queried NDC-11 exactly |
| `query_error` | API failed after retries |
| `not_queried` | Source not called for this row |
| `not_applicable` | Source does not apply |

Completeness (SDUD, since 2026-09-24): `complete`, `partial_error` (a later page failed), `partial_short` (fewer rows than the server's reported total), `truncated_max_pages` (hit the 40-page stop). Anything other than `complete` means totals may be understated.

Shortage flag: `Y` active, `N_RESOLVED` records exist but all resolved, `N` no FDA record found (not "supply confirmed adequate"), `unknown` API error.

### 6.3 Known access limits
- **WAC (HCAI) returns 403 from cloud hosts.** Expect `query_error` on the VPS; some data was pulled manually as CSV.
- **SDUD and NADAC dataset IDs are hardcoded.** SDUD is one year (2024) by construction (I-14).
- **Part B `Brnd_Name` holds HCPCS descriptions**, so brand filters mostly return `no_data`. The fix is the ASP NDC-HCPCS crosswalk (section 10).
- **Network is disabled in Claude chat sandboxes.** Code can be read and unit-tested there, not run against the APIs; live runs happen on the VPS or laptop.

### 6.4 Confirmed, no adapter yet
- MDRP Product File: data.medicaid.gov `0ad65fe5-3ad3-5d79-a3f9-7893ded7963a`. Package-native; innovator flag, unit type, TE code, FDA approval and termination dates, units per package.
- Orange Book: ZIP download (patents, exclusivities).
- ACA FUL: CSV download (reimbursement ceiling).
- Part D Formulary PUF: already downloaded to the VPS (section 2.3).

---

## 7. Output schemas and semantic rules

### 7.1 Source matrix (`ndc11_source_matrix.csv`), column groups
- **Identity (18):** `ndc11, ndc11_display, package_ndc_source, product_ndc, ndc9, ndc6, brand_name, generic_name, labeler_name, dosage_form, route, package_description, application_number, spl_setid, rxcui, listing_expiration_date, marketing_start_date, sample`.
- **Source flags:** `source_count`, then a `src_X` (0/1) and `src_X_status` pair for each of: nadac, sdud, wac_cur, wac_hist, drugsfda, rxnav, dailymed, pd_ann, pd_q, mc_sp, pb_ann, pb_q.
- **NADAC:** `nadac_eff_date`, `nadac_per_unit`, `nadac_unit`, `nadac_otc`, `nadac_class`, `nadac_count`, `nadac_sort` (new).
- **SDUD:** `sdud_count`, `sdud_year`, `sdud_quarter`, `sdud_states`, `sdud_units`, `sdud_rx`, `sdud_reimb`, `sdud_national_excluded` (new), `sdud_completeness` (new).
- **WAC:** `wac_cur_date`, `wac_cur_price`, `wac_hist_date`, `wac_hist_price`.
- **Drugs@FDA / RxNav / DailyMed:** applications, sponsors, approval; rxcuis, names; SPL count and ids.
- **Part D annual:** year, spend, claims, beneficiaries, units, average per unit, average per claim. **Part D quarterly:** period, spend, claims, beneficiaries, average per claim.
- **Medicaid Spending:** year, spend, claims, units, average per unit.
- **Part B annual:** HCPCS, year, spend, claims, beneficiaries, units, average per unit. **Part B quarterly:** HCPCS, period, spend, claims, beneficiaries.

Brand-level groups repeat the same value on every NDC-11 of the brand. Never sum them across rows (I-19).

`ndc11_compact.csv`: identity plus status columns plus NADAC price, for quick scanning.

### 7.2 State tables (`state_<ndc11>.csv`, 51 rows, 28 columns)
`state_code, state_name, ndc11, ndc11_display, brand_name, product_ndc, product_display, package_display, sdud_status, sdud_record_count, latest_period, period_count, total_units_reimbursed, total_prescriptions, total_amount_reimbursed, medicaid_amount_reimbursed, non_medicaid_amount_reimbursed, ffsu_units, ffsu_prescriptions, ffsu_total_amount, mcou_units, mcou_prescriptions, mcou_total_amount, suppression_flag_present, nadac_latest_per_unit, nadac_effective_date, nadac_pricing_unit, notes`
State measures come from SDUD only; the three NADAC columns are identical in every state row.

### 7.3 Shortages (`ndc11_shortages.csv`, 15 columns)
`ndc11, ndc11_display, brand_name, generic_name, product_ndc, shortage_flag, shortage_status, shortage_count, shortage_availability, shortage_reason, shortage_initial_date, shortage_update_date, shortage_generic_name, shortage_company, shortage_source_status`

### 7.4 Derived KPIs (`ndc11_derived_kpis.csv`, 21 KPI columns)
| KPI | Formula | Inputs | Status column |
|---|---|---|---|
| 1 Reimbursement-to-NADAC spread | `(sdud_reimb / sdud_units - nadac) / nadac` | source matrix | `kpi1_status` |
| 2 State utilization HHI | `sum(state_share^2)` | state tables | `kpi2_status` |
| 3 Average units per Rx | `sdud_units / sdud_rx` | source matrix | `kpi3_status` |
| 4 Medicaid / Medicare gross cost ratio | `(mc_spend/mc_units) / (pd_spend/pd_units)` | source matrix | `kpi4_status`, `kpi4_note` |
| 5 Source coverage depth | `hits / sources queried` | status columns | `kpi5_status` |
The extension document says 25 columns; the script produces 21. Known methodology problems: KPI1 (I-6), KPI4 (I-7), KPI5 (I-18); KPI1 and KPI3 also inherit I-16 and I-17.

### 7.5 Semantic rules, with enforcement status
| # | Rule | Enforcement |
|---|---|---|
| R1 | Only SDUD populates state rows | Enforced (geo) |
| R2 | NADAC in state tables is a national reference, never state-varied | Enforced (geo) |
| R3 | Brand-level values are projected with status columns and never presented as package facts | Enforced by labelling; pivot double-count risk remains (I-19) |
| R4 | NADAC, SDUD and WAC require digit-for-digit NDC-11 match | Enforced |
| R5 | SDUD suppression is preserved; suppressed values are blank, not zero, and flagged | Geo: enforced. **Source matrix: not enforced (I-17)** |
| R6 | FFSU and MCOU are never merged without documentation | Geo: enforced. **Source matrix: not enforced (I-16)** |
| R7 | All spending is gross, pre-rebate; KPI4 labelled accordingly | Enforced by label |
| R8 | Part B `Brnd_Name` is a HCPCS description, not a drug name | Known limitation |
| R9 | Shortage `N` means "no FDA record found", not "supply adequate" | Documented |
| R10 | Shortage status is never projected beyond the package without an explicit aggregation label | **Not enforced (I-8)** |
| R11 | NADAC `effective_date` drives time series; `as_of_date` is freshness only | Enforced |
| R12 | SDUD national-total rows (`XX`) are never summed with state rows | Enforced since 2026-09-24 |
| R13 | Truncation is never silent: every capped query reports completeness | Partial: SDUD only (I-12) |
| R14 | Part D Prescribers are never joined to NDC-11 (no NDC field) | n/a (not implemented) |
| R15 | Formulary PUF `NDC` is a proxy per RXCUI, not the dispensed NDC | Applies when the adapter is built |
| R16 | Standard library only; Python embedded in bash heredocs | Under deliberate review: `run.py` already bypasses bash; the planned refactor replaces this rule rather than silently breaking it |

---

## 8. Patches applied on 2026-09-24

Delivered as drop-in replacements for `ndc_source_matrix.sh`, `ndc_geo_matrix.sh`, `ndc_shortages.sh`. Compatible with `run.py` unchanged. Built from the project-layout versions.

| # | Fix | Files | What changed |
|---|---|---|---|
| P1 | SDUD pagination | source, geo | Fetches every page until the reported total (or a short page) is reached. Old limits: 200 (source, caused truncation) and 5,000 (geo, above the likely server cap). New column `sdud_completeness`; geo adds a warning when not complete. |
| P2 | National-row exclusion | source, geo | Rows with state `XX` are excluded before summing and counted in `sdud_national_excluded`. If only national rows match, status is `no_data`, not `hit`. |
| P3 | NADAC server-side sort | source, geo | Query sorts `effective_date` descending on the server; automatic fallback to the unsorted query if rejected; client-side sort retained. New column `nadac_sort` (`server_desc` or `client_only`). |
| P4 | Part B Overall row | source | Annual and quarterly Part B now pass through `pick_ov`, as Part D and Medicaid already did. |
| P5 | Shortage displayed record | shortages | The displayed record is chosen from current (unresolved) records, so status always agrees with `shortage_flag`. Dates parsed as real dates (ISO, MM/DD/YYYY, YYYYMMDD). |

**Tests run in the sandbox:** all three compile; bash syntax clean; zero non-ASCII bytes. Pagination and NADAC helpers passed eight tests against a simulated API: page cap of 100 on 1,200 rows; no total count reported; error on page 2; error on page 1; the 40-page stop; empty result; sort rejected; sort accepted. The shortage test reproduced the old bug (Resolved record displayed under flag `Y`) and confirmed the fix.

**Evidence the SDUD fix mattered:** the documented JANUVIA output (`state_00006027731.csv`) shows all 51 states with data, most with both FFSU and MCOU. One year can reach 51 x 4 x 2 = 408 rows, above the old limit of 200, so source-matrix national totals for 0006-0277 were very likely truncated before this patch.

**Assumptions not yet verified live** (see section 14):
1. data.medicaid.gov accepts `sorts[0][property]` / `sorts[0][order]` (fallback covers a rejection).
2. The datastore response includes a `count` field (a page-size heuristic covers its absence).
3. SDUD national rows use state code `XX`.
4. CMS Part B datasets carry a `Mftr_Name` column with Overall rows (if absent, `pick_ov` returns all rows, which is the previous behaviour).

**First run after patching** is slower: the new URLs miss the cache.

---

## 9. Known-issue register

Severity: **H** = wrong numbers or wrong conclusions possible; **M** = misleading or fragile; **L** = hygiene or convenience.
Status as of 2026-09-24.

| ID | Sev | File | Issue | Status | Fix sketch |
|---|---|---|---|---|---|
| I-1 | H | source | SDUD `limit=200`, no pagination: silent truncation for high-volume packages | **Fixed (P1)** | - |
| I-2 | H | source | SDUD national-total rows summed with states | **Fixed (P2)**, verify `XX` live | - |
| I-3 | M | source, geo | NADAC "latest" chosen from an unsorted page of 50 | **Fixed (P3)** | - |
| I-4 | H | source | Part B annual/quarterly summed manufacturer rows plus Overall | **Fixed (P4)**, verify column live | - |
| I-5 | M | source | Part B quarterly sums every quarter of the latest year into one figure | Open | Pick the latest quarter, record it in `pb_q_per` |
| I-6 | H | derived | KPI1 mixes periods (all 2024 SDUD quarters vs the latest weekly NADAC, e.g. 2025-11-19), uses `medicaid_amount_reimbursed` first while the docs say total, and includes dispensing fees against ingredient-only NADAC | Open | Align on one quarter (average weekly NADAC over that quarter); fix one amount field; label "includes dispensing fees" |
| I-7 | M | derived | KPI4 never checks that Medicaid and Part D years match | Open | Require equal years or set `year_mismatch` |
| I-8 | H | shortages | Product-level match flags every package of the product (breaks R10) | Open | Add `match_level` (package/product) or restrict to package matches |
| I-9 | M | shortages | `current` computed but unused: flag `Y` could display a Resolved record | **Fixed (P5)** | - |
| I-10 | M | shortages | Pagination error after page 1 keeps a partial list as `hit`; hard cap 30 pages x 100 = 3,000 records | Open | Mark run `partial`; flag affected rows `unknown` instead of `N`; raise cap with a completeness check |
| I-11 | M | shortages | `update_date` sorted as a string | **Fixed (P5)** | - |
| I-12 | M | all | Truncation invisible for other capped queries (openFDA family pagination stops silently on error; WAC, DailyMed, CMS limits) | Partial (SDUD only) | `truncated=Y` when rows == limit; record openFDA pagination breaks in resolution JSON |
| I-13 | M | source, geo, shortages, lookup | Unhyphenated 8-digit product input assumed 5-3; 4-4 input such as `00060277` resolves wrongly | Open | Require a hyphen for 8-digit input |
| I-14 | M | source, geo | Hardcoded dataset IDs; SDUD is one year (2024) by construction; NADAC likely yearly too | Open | Resolve IDs from the data.medicaid.gov metastore by title/year; write the ID used into outputs |
| I-15 | M | source | Exact brand-name filters on CMS: case or format differences show as `no_data`, not errors | Open | Check `no_data` rates on known-covered brands; case-normalise or use a name crosswalk |
| I-16 | H | source | National SDUD totals merge FFSU and MCOU without documentation (breaks R6) | Open | Add FFSU/MCOU split columns alongside totals |
| I-17 | H | source | Suppressed SDUD rows silently contribute nothing; no flag (breaks R5); KPI1 and KPI3 inherit the bias | Open | Add `sdud_suppressed_rows`; flag KPI1/KPI3 when > 0 |
| I-18 | L | derived | KPI5 counts brand-level projections equal to package-native hits, overstating package evidence | Open | Split into package coverage and brand coverage |
| I-19 | M | source | Brand-level values repeated on every NDC-11 row get double-counted in pivots | Open | Separate brand table, or a `do_not_sum` marker |
| I-20 | L | source | WAC columns labelled "current" but SB 17 data records reportable increase events, not full WAC history | Open | Rename or document coverage |
| I-21 | H | repo | Repo held the old-layout `ndc_shortages.sh` and `ndc_derived_kpis.sh` (Copilot mapping used the `_clean` copies) | **Fixed 2026-09-24** (direct upload) | - |
| I-22 | L | local | `_clean` duplicates identical to the old versions | Open | Delete |
| I-23 | L | all, run.py | `INPUT` defaults to `0006`; help text and docs use Merck examples | Open | Make `INPUT` required; neutral examples |
| I-24 | M | reference | `source-log.md` contains an invented KEYTRUDA Part D row (round figures; KEYTRUDA is Part B); extension doc cites "$945/unit for JANUVIA" | Open | Replace with real fetched rows or mark clearly illustrative |
| I-25 | L | source | WAC returns 403 from cloud hosts | Known limitation | Manual CSV pull, or run WAC from the laptop |
| I-26 | L | source | DailyMed name search returns SPLs from other labelers with the same name | Open | Filter by set id against openFDA `spl_set_id` |
| I-27 | L | source | Part D quarterly: which quarter lands first is arbitrary; period records the year only | Open | Sort by year and quarter; record both |
| I-28 | L | lookup | Numeric input only; no brand-name search | Enhancement | openFDA `brand_name:"X"` query |
| I-29 | M | derived | Output path `exports/tables/derived_kpis/ndc11_derived_kpis.csv` is not keyed by input: each run overwrites the last | Open | Key the folder or filename by `INPUT` |
| I-30 | L | docs | README, extension doc and BOOTSTRAP v1 carry old `~/ndc_*` paths and old run commands | Open | Update when the repo is refreshed |

**Recommended next batch, in order:** I-22 (delete local `_clean` copies) -> I-16 and I-17 (source-matrix SDUD honesty) -> I-8 (shortage grain) -> I-6 and I-7 (KPI definitions) -> I-29 -> I-23 and I-24 (neutral defaults, clean references) -> I-10, I-12, I-14.

---

## 10. Roadmap

### 10.1 Phase 2 adapters
**MDRP Product File** (lowest effort, high relevance). Package-native; the innovator flag drives the Medicaid rebate formula. With the 2026-09-24 helpers:
```python
MDRP_DATASET = "0ad65fe5-3ad3-5d79-a3f9-7893ded7963a"
mdrp_data = fetch_parallel(lambda n: fetch_medicaid_all(MDRP_DATASET, n), all_ndc11)
# per row: exact = [x for x in _medicaid_rows(mdrp_data[ndc11])
#                   if digits_only(x.get("ndc", "")) == ndc11]
# columns: src_mdrp, src_mdrp_status, mdrp_innovator_flag, mdrp_unit_type,
#          mdrp_te_code, mdrp_fda_approval_date, mdrp_termination_date, mdrp_units_per_pkg
```
Field names come from documentation; confirm on the first live run.

**Part D Formulary PUF** (data already on the VPS).
1. `unzip -l local-data/cms-formulary/2026_20260219.zip` to list contents.
2. Extract only the basic drugs formulary table; delete the ZIP afterwards to reclaim about 2.2 GB. Do not extract the whole archive (disk).
3. Stream it with `csv.reader(f, delimiter="|")`; never load it whole.
4. Aggregate per NDC-11: number of formularies listing it, tier distribution, share with prior authorization, step therapy, quantity limits.
5. Output `formulary_<INPUT>.csv`, exact NDC-11 match, with rule R15 stated in the output notes.

**ASP NDC-HCPCS crosswalk.** Quarterly ZIP/Excel from cms.gov; strip NDC dashes; gives the real bridge for Part B (fixes the root cause behind R8).

**RxClass ATC.** Two-hop chain (ATC -> RxCUI -> NDC), rate-limited; best as a monthly cached crosswalk table.

**Deferred with reasons:** FAERS (26K pagination ceiling, bulk download, many-to-many grain, incomplete NDC coverage); Part D Prescribers (no NDC field); retail pricing (no free public API).

### 10.2 Structural refactor
- Move the Python out of the heredocs into modules under `commands/` (`common.py` for HTTP, cache, normalisation and the Medicaid helpers; one module per tool). `run.py` becomes the single CLI on every platform; the `.sh` files become two-line wrappers or are retired.
- Replace rule R16 explicitly when this happens; do not let the code drift from its documented rules.
- Add a small test set: a handful of known NDCs with expected statuses, plus the simulated-API tests used for P1 to P3.

### 10.3 Towards a governed use case
If this is ever proposed as a departmental capability: repo private (done); employer policy check on personal code, AI tools and servers; neutral defaults (I-23); clean references (I-24); I-16/I-17 fixed; then a one-page case in the format problem, hypothesis, method and data, expected results and timeline, limitations and risks, with owner, governance and measured value.

---

## 11. Documentation hygiene backlog
- Retire BOOTSTRAP v1, or replace its content with a pointer to this document.
- README: update run paths to `exports/` and add `ndc_lookup.sh` and `run.py`.
- Extension doc: remove the `$945/unit for JANUVIA` example and stale `/home/claude/...` and `~/ndc_*` paths; note that KPI output has 21 columns, not 25.
- Source log: replace or clearly mark the illustrative KEYTRUDA Part D row.
- Repo audit: add a line that its encoding problem is resolved and its `_clean` recommendation was wrong (I-21).

---

## 12. Repo update procedure (next refresh)

Preferred (2026-09-24): direct upload in the phone browser. Download files with the download button, unzip in the iOS Files app, then on github.com (branch `claude`) use Add file > Upload files inside the target folder. Folders starting with a dot (`.github`) are hidden by iOS: upload such files at the root, then edit only the filename box to prepend the path (for example `.github/workflows/`). Never edit file contents on the phone.

Alternative: Copilot coding agent issue, as used for the February restructure (requires the coding agent to be enabled; it did not appear as an assignee on 2026-09-24). Zip the files if GitHub refuses `.sh` attachments.
```
Title: Refresh commands/ and add session loader

Replace or add these files at the paths shown:

| Uploaded file              | Repo path                      |
|----------------------------|--------------------------------|
| ndc_source_matrix.sh       | commands/ndc_source_matrix.sh  |
| ndc_geo_matrix.sh          | commands/ndc_geo_matrix.sh     |
| ndc_shortages.sh           | commands/ndc_shortages.sh      |
| ndc_derived_kpis.sh        | commands/ndc_derived_kpis.sh   |
| ndc_lookup.sh              | commands/ndc_lookup.sh         |
| run.py                     | commands/run.py                |
| NDC_Master_Context.md      | NDC_Master_Context.md          |
| ndc-run.yml                | .github/workflows/ndc-run.yml  |

Use the NON-_clean ndc_derived_kpis.sh (project layout, 425 lines).
Do not upload any *_clean.sh file.
Keep reference/ unchanged in this PR.
Verify: every .sh has zero non-ASCII bytes.
```
Then on the VPS: `cd ~/my-ndc-project && git pull`, and run one package to confirm the new columns appear.

---

## 13. Changelog
| Date | Change |
|---|---|
| Early 2026 | Source matrix v2 rebuilt; smart-quote rebuild; geo matrix built |
| Early 2026 | Two source-validation research reports; extension document; derived KPIs and shortages scripts; README |
| Feb 2026 | Repo audit; BOOTSTRAP v1; smart-quote root cause found; project-layout update; Copilot restructure PR merged; host cleaned; first clean run |
| Feb 2026 | `ndc_lookup.sh`; CMS Formulary PUF (CY2026 Feb) downloaded; `run.py` Windows launcher |
| 2026-09-23 | Full code review: 15 methodology issues identified; repo made private |
| 2026-09-24 | Inventory; `_clean` discrepancy found (I-21); patches P1 to P5; extension document re-read against code (I-16 to I-19); this document (v2.0); GitHub Actions workflow added |
| 2026-09-24 | v2.1: repo name corrected to `NDC-Mapping`; direct-upload refresh done (I-21 fixed); upload procedure for iOS documented |

Dates before September are approximate, inferred from file names and the formulary release date.

---

## 14. Verification checklist for the next live run

Run one high-volume package, for example `INPUT="0006-0277-31"`, with the patched scripts, then check:
1. `sdud_completeness` = `complete` and `sdud_count` equal to or higher than in an old output. A higher count confirms I-1 was live.
2. `sdud_national_excluded` > 0 confirms the `XX` code; if always 0, inspect a raw SDUD response for the national-row code and update `NATIONAL_STATE_CODES`.
3. `nadac_sort` = `server_desc` confirms the sort parameter; `client_only` means the fallback is running.
4. `nadac_eff_date` is the most recent weekly date available.
5. Part B values changed only for brands with manufacturer rows; if `Mftr_Name` is absent in Part B, record that here.
6. `grep -c "partial\|truncated" exports/logs/run_log_geo_*.json` returns 0 for normal packages.
7. Shortages: any `Y` row shows a non-Resolved `shortage_status`.
Record the outcome of each check in this section, then remove the corresponding assumption from section 8.
