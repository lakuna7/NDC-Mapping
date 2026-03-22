# Prompt 2 to Claude   
  
You are continuing the same codebase and design logic used to build ndc_source_matrix.sh.  
I need a SECONDARY SCRIPT focused on U.S. GEOGRAPHICAL / STATE-LEVEL ANALYSIS.  
This is not a rewrite of the original script.  
This is a companion script.  
==================================================  
PRIMARY GOAL  
Build a new script that, for the user-selected NDC scope, returns state-level tables for every unique NDC11 included in that scope.  
The script must behave similarly to the original script in how it is initiated:  
Company scope  
INPUT=“0006” bash ndc_geo_matrix.sh  
Product scope  
INPUT=“0006-0277” bash ndc_geo_matrix.sh  
Package scope  
INPUT=“0006-0277-02” bash ndc_geo_matrix.sh  
The script must:  
	∙	resolve the selection scope exactly like the original script  
	∙	identify all unique NDC11s in the selected scope  
	∙	create a separate state table for each unique NDC11  
	∙	use only genuinely state-grained data where state attribution is real  
	∙	never fabricate state-level values by spreading national or brand-level data across all states  
==================================================  
CORE OUTPUT REQUIREMENT  
For every unique NDC11 in scope:  
	∙	create one unique table  
	∙	rows = U.S. states in alphabetical order  
	∙	columns = state-level data measures  
	∙	values = only data that truly exists at state level for that NDC11  
Required output formats:  
	1.	one workbook file with one sheet per NDC11  
	2.	one CSV per NDC11  
	3.	one run log summarizing:  
	∙	input  
	∙	scope type  
	∙	number of brands  
	∙	number of products  
	∙	number of NDC11 packages  
	∙	number of per-state tables generated  
	∙	sources used  
	∙	sources skipped due to non-state grain  
	∙	runtime  
	∙	warnings / partial failures  
If workbook generation is too heavy, still generate:  
	∙	one CSV per NDC11  
	∙	one manifest/index CSV  
	∙	one run log  
==================================================  
STRICT SEMANTIC RULES  
These rules are non-negotiable.  
	1.	Do NOT project national, drug-level, brand-level, HCPCS-level, or program-summary data onto states.  
	2.	Do NOT duplicate Part D / Part B / Medicaid summary values across all states.  
	3.	Do NOT infer per-state values from national totals.  
	4.	Do NOT mix row-native state facts with inherited context without labeling them clearly.  
	5.	The script must distinguish:  
	∙	true state-native fields  
	∙	optional national reference fields (if included at all)  
==================================================  
WHAT COUNTS AS REAL STATE-LEVEL DATA  
Primary state-native source:  
	∙	SDUD / Medicaid State Drug Utilization Data  
Use SDUD as the primary per-state source.  
Native SDUD grain is effectively:  
	∙	record_id (FFSU or MCOU)  
	∙	state  
	∙	ndc_11  
	∙	period / year-quarter  
The script must preserve this discipline.  
If you include rolled state summaries, do so explicitly and transparently.  
For each NDC11 + state, produce measures such as:  
	∙	total_units_reimbursed  
	∙	total_prescriptions  
	∙	total_amount_reimbursed  
	∙	medicaid_amount_reimbursed  
	∙	non_medicaid_amount_reimbursed  
	∙	latest_period  
	∙	period_count  
	∙	ffsu_units  
	∙	ffsu_prescriptions  
	∙	ffsu_total_amount  
	∙	mcou_units  
	∙	mcou_prescriptions  
	∙	mcou_total_amount  
	∙	suppression_flag_present  
	∙	source_hit_sdud  
	∙	source_status_sdud  
If the source schema uses different field names internally, normalize them in the output.  
==================================================  
OPTIONAL / SECONDARY SOURCE RULES  
Only include a source if state attribution is real and defensible.  
Examples:  
	∙	If a source is California-only or state-specific but not national-by-state, include it only if clearly labeled.  
	∙	If a source is national summary only, do NOT include it as state-level data.  
	∙	If a source is package-native but not state-native, it may be included only in a separate package reference section, not in the state rows as if it varied by state.  
If you include non-state reference columns, isolate them clearly, for example:  
	∙	ndc11  
	∙	brand_name  
	∙	product_ndc  
	∙	product_display_name  
	∙	package_display_name  
	∙	nadac_latest  
	∙	nadac_effective_date  
	∙	pricing_unit  
But do NOT repeat such national/package reference values as if they are state facts.  
==================================================  
STATE TABLE DESIGN  
For each NDC11 table:  
	∙	rows = all 50 states + DC  
	∙	sorted alphabetically by state code or state name  
	∙	choose one convention and keep it consistent  
	∙	include missing states even if there is no data  
	∙	for missing values, leave blank or null, not zero unless source explicitly reports zero  
	∙	include source coverage/status columns  
Recommended columns:  
	∙	state_code  
	∙	state_name  
	∙	ndc11  
	∙	brand_name  
	∙	product_ndc  
	∙	product_display_name  
	∙	package_display_name  
	∙	latest_period  
	∙	period_count  
	∙	total_units_reimbursed  
	∙	total_prescriptions  
	∙	total_amount_reimbursed  
	∙	medicaid_amount_reimbursed  
	∙	non_medicaid_amount_reimbursed  
	∙	ffsu_units  
	∙	ffsu_prescriptions  
	∙	ffsu_total_amount  
	∙	mcou_units  
	∙	mcou_prescriptions  
	∙	mcou_total_amount  
	∙	suppression_flag_present  
	∙	source_hit_sdud  
	∙	source_status_sdud  
	∙	notes  
If better normalized names are needed, improve them, but preserve clarity.  
==================================================  
DISPLAY NAME RULES  
Use the same semantic hierarchy we established:  
Brand level:  
	∙	BRAND  
	∙	example: JANUVIA  
Product / NDC9 level:  
	∙	BRAND + STRENGTH + DOSAGE_FORM  
	∙	example: JANUVIA 100MG TABLET  
Package / NDC11 level:  
	∙	BRAND + STRENGTH + DOSAGE_FORM + PACKAGING  
	∙	example: JANUVIA 100MG TABLET × 30  
The per-state tables must use human-readable product/package display names, not raw source package text as the primary label.  
==================================================  
IMPLEMENTATION EXPECTATIONS  
Reuse as much as practical from ndc_source_matrix.sh:  
	∙	input parsing  
	∙	company/product/package scope resolution  
	∙	caching  
	∙	concurrency  
	∙	normalization helpers  
	∙	logging style  
	∙	source hit/status structure  
But this new script must be independent and purpose-built for state analysis.  
Suggested filename:  
	∙	ndc_geo_matrix.sh  
If Python is embedded inside the shell wrapper, keep the same pattern as the original script.  
==================================================  
SOURCE DISCIPLINE  
You must explicitly classify every source touched by the script as one of:  
	∙	package-native  
	∙	state-native  
	∙	program-summary  
	∙	hcpcs-native  
	∙	regulatory  
	∙	label-document  
Only state-native sources may populate the state rows as real row-native measures.  
==================================================  
DELIVERABLES  
Return:  
	1.	exact new files created  
	2.	exact modified files  
	3.	the full script  
	4.	output file naming convention  
	5.	exact columns produced  
	6.	exact sources used  
	7.	exact sources intentionally excluded and why  
	8.	exact assumptions  
	9.	one sample run command for:  
	∙	company scope  
	∙	product scope  
	∙	package scope  
	10.	one small preview of expected output  
==================================================  
SUCCESS CRITERIA  
The script is successful only if:  
	∙	it resolves INPUT exactly like the original script  
	∙	it produces one state table per unique NDC11  
	∙	it uses only real state-level data for state rows  
	∙	it never projects national summary data onto states  
	∙	it is auditable and reproducible  
	∙	it is clean enough to serve as the basis for a future geography/state dashboard  
