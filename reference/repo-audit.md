# Memory Preservation Repo — Audit

## Verdict

The repo structure is sound. The folder logic is right, the file selection is mostly right, and the purpose is clear. There are three problems: two of the four scripts are corrupted and will not run, several files are redundant or misplaced, and there is no quick-reload document optimized for what a future Claude session actually needs.

---

## Problem 1: Two Scripts Are Broken (Critical)

`ndc derived kpis.sh` and `ndc shortages.sh` are infected with Unicode smart quotes. These files will not execute.

| File | Smart Quote Count | Runnable? |
|------|------------------|-----------|
| `ndc_source_matrix.sh` | 0 | Yes |
| `ndc_geo_matrix.sh` | 0 | Yes |
| `ndc derived kpis.sh` | 413 (`"` `"` `'` `'` `–` `…`) | **No** |
| `ndc shortages.sh` | 486 (`"` `"` `'` `'` `–` `…`) | **No** |

This happened during copy-paste from Claude's output through a text editor or macOS Notes/Pages that auto-converts ASCII quotes to typographic ones. The two clean scripts (`ndc_source_matrix.sh`, `ndc_geo_matrix.sh`) were likely saved differently — probably direct file download rather than copy-paste.

**Fix:** Replace the two corrupted files with the clean versions from the outputs directory of this session, or run this on each:

```bash
sed -i \
  -e "s/\xe2\x80\x9c/\"/g" \
  -e "s/\xe2\x80\x9d/\"/g" \
  -e "s/\xe2\x80\x98/'/g" \
  -e "s/\xe2\x80\x99/'/g" \
  -e "s/\xe2\x80\x93/-/g" \
  -e "s/\xe2\x80\xa6/.../g" \
  "ndc derived kpis.sh" "ndc shortages.sh"
```

Then validate:
```bash
grep -cP '[\x80-\xff]' "ndc derived kpis.sh"  # must be 0
grep -cP '[\x80-\xff]' "ndc shortages.sh"     # must be 0
```

Also: the filenames have spaces (`ndc derived kpis.sh`, `ndc shortages.sh`). The originals used underscores (`ndc_derived_kpis.sh`, `ndc_shortages.sh`). Rename them to match.

---

## Problem 2: File Inventory — What Belongs, What Doesn't

### Files that belong and are correctly placed

| File | Location | Why It Matters |
|------|----------|---------------|
| `ndc_source_matrix.sh` | `sh/` | Primary script. Implementation truth. |
| `ndc_geo_matrix.sh` | `sh/` | State-level companion. Implementation truth. |
| `ndc_shortages.sh` | `sh/` | Shortage enrichment. (Fix encoding first.) |
| `ndc_derived_kpis.sh` | `sh/` | Derived KPIs. (Fix encoding first.) |
| `source-log (1).md` | `Definitions & Connections/` | The single most important reference file. Every endpoint, field name, grain, and caveat. |
| `ndc system extension.md` | `Definitions & Connections/` | Extension analysis: validated sources, KPI opportunities, grain integrity, forbidden shortcuts. |
| `readme.md` | root | Project orientation. |

### Files that are redundant or should be moved

| File | Issue | Recommendation |
|------|-------|---------------|
| `data-canon.md` | This is a self-assessment + draft rewrite of a canonical doc that was superseded by `source-log.md` + `ndc system extension.md`. It contains some useful schema SQL and a field-to-backbone mapping table, but also a lot of score-card commentary and stale content. | Keep only if you extract the SQL schema section and the backbone mapping table into a standalone reference. Otherwise remove — the source-log is the operational authority. |
| `Outputs/805a57b8...json` | Raw SDUD API cache response. 146K of JSON. A future session can regenerate this in seconds by running the script. | Remove. Cache artifacts don't belong in a memory repo. |
| `Outputs/ndc_geo_matrix.xlsx` | Binary Excel workbook. Can't be diffed, can't be read by Claude, can't be searched. | Remove. The CSVs are the evidence. |
| `Outputs/ndc11_source_matrix_0006.csv` | 190K, 174 rows. Full company-scope output for labeler 0006. | This is the most useful output sample — keep it. But one sample is enough. |
| `Outputs/ndc11_source_matrix.csv` + `ndc11_compact.csv` | Product-scope output for 0006-0277. Overlaps with the company-scope file. | Remove one. The company-scope file (0006) is more representative. |
| `Outputs/log-example.md` | Duplicate of `run_log.json` content, formatted as markdown. | Remove. `run_log.json` is the structured version. |
| `Prompts/` (all 5 files) | The exact prompts used to generate each script and analysis. | These are genuinely useful for memory — they encode the design intent and constraints. Keep them. But they should be numbered more clearly. |

### Files that are missing

| Missing File | Why It Matters |
|-------------|---------------|
| **A session bootstrap / context-loading document** | The single biggest gap. When you start a new session and paste files, Claude has no idea what order to read them or what the system state is. You need a short, dense "read this first" file. |
| **The README you just built** | The `readme.md` in the repo is the one I produced last session. It's good for a human reader. But it's 399 lines — too long for a context-loading document. You need a compressed version. |

---

## Problem 3: No Quick-Reload Document

This is the core issue for memory preservation. The repo has the right raw materials but no document optimized for the actual use case: pasting into a new Claude session to restore working context in minimum tokens.

What a future session needs, in priority order:

1. What scripts exist, what each does, what inputs they take
2. What sources are implemented, at what grain, with what status semantics
3. What the output schemas look like (column names)
4. What semantic rules are enforced (grain discipline, forbidden joins)
5. What was evaluated and deferred (so work isn't repeated)

The source-log is 592 lines. The extension doc is 399 lines. The readme is 399 lines. That's ~1,400 lines of context just for orientation — too much for a session bootstrap.

---

## Recommended Repo Structure

```
Files-for-memory-refresh/
  BOOTSTRAP.md                          # NEW: compressed context-loader (~150 lines)
  README.md                             # Full project readme (existing, good)
  
  sh/
    ndc_source_matrix.sh                # Primary script (clean)
    ndc_geo_matrix.sh                   # State-level companion (clean)
    ndc_shortages.sh                    # Shortage enrichment (FIX ENCODING)
    ndc_derived_kpis.sh                 # Derived KPIs (FIX ENCODING)
  
  reference/
    source-log.md                       # Operational source registry (rename, drop "(1)")
    ndc-system-extension.md             # Extension analysis document
  
  evidence/
    ndc11_source_matrix_0006.csv        # One sample output (company scope)
    state_00006027731.csv               # One sample state table
    resolution.json                     # One sample resolution
    run_log.json                        # One sample run log
  
  prompts/
    01-source-matrix.md                 # Prompt that produced ndc_source_matrix.sh
    01a-source-matrix-fix.md            # Follow-up fix prompt
    02-geo-matrix.md                    # Prompt that produced ndc_geo_matrix.sh
    03-extension-analysis.md            # Prompt that produced the extension analysis
    04-implementation.md                # Prompt that produced shortages + derived KPIs
```

What this removes: `data-canon.md` (superseded), the raw cache JSON, the xlsx binary, duplicate CSV outputs, `log-example.md`.

What this adds: `BOOTSTRAP.md`.

---

## What BOOTSTRAP.md Should Contain

A single file, under 150 lines, that a future session reads first. It should contain:

1. One-paragraph project description
2. Script inventory (4 scripts, what each does, input interface)
3. Source inventory table (source, endpoint, grain, NDC-11 native?, classification — one row per source, no prose)
4. Output schema summary (column groups, not every column)
5. Semantic rules (the 5-6 non-negotiable constraints, as bullet points)
6. What was deferred and why (one line each)
7. Pointer to full reference files for deep dives

No architecture explanation. No methodology prose. No SQL schemas. No examples. Just the facts a session needs to resume work.
