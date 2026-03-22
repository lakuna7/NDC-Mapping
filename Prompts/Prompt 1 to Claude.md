# Prompt 1 to Claude   
  
You are a senior healthcare data architect, API integration engineer, and production-grade data tooling reviewer.  
I am attaching these materials:  
	1.	data-canon.md  
	∙	Canonical semantic model  
	∙	Defines the correct grains and entity meanings across concept, product, package, regulatory, label, pricing, and utilization  
	∙	Important rule: the final table must anchor rows at normalized ndc11 package grain  
	2.	source-log (1).md  
	∙	Source registry / operational source map  
	∙	Describes the relevant public sources, their semantic roles, likely keys, and grain expectations  
	∙	Includes sources such as:  
	∙	openFDA NDC  
	∙	openFDA Drugs@FDA  
	∙	RxNav  
	∙	DailyMed  
	∙	CMS Medicare Part D  
	∙	CMS Medicare Part B  
	∙	CMS Medicaid Spending by Drug  
	∙	NADAC  
	∙	SDUD  
	∙	CHHS WAC  
	∙	Treat this as the authoritative source inventory for the standalone extractor  
	3.	ndc_source_matrix_full_command.sh  
	∙	Current standalone prototype  
	∙	This is the only script you should treat as the current implementation baseline  
	∙	Review it critically and improve it  
Objective  
Build the fastest, cleanest, most reliable standalone command/script so a user can type a single NDC input near the top and get back a final table with all relevant results.  
This must remain fully standalone.  
Hard constraint:  
	∙	Do not use, assume, import, depend on, or integrate with any repo, app runtime, dashboard, database, API route, internal service, branch, or background task  
	∙	Everything must run directly from the standalone script plus public source/API logic  
	∙	Do not redesign this into a web app or repo feature  
	∙	Do not propose repo integration  
	∙	Do not add unnecessary architecture  
User behavior required  
The user types one input only, at the start of the command/script.  
Supported inputs:  
	∙	Company / labeler scope:  
	∙	0006  
	∙	00006  
	∙	000060  
	∙	Product scope:  
	∙	0006-0277  
	∙	000060277  
	∙	50090-4084  
	∙	Package scope:  
	∙	0006-0277-02  
	∙	00006027702  
	∙	50090-4084-0  
Expected behavior:  
	∙	If input is package scope (ndc11), return exactly one row  
	∙	If input is product scope (ndc9 / product NDC), return all unique normalized ndc11 rows under that product  
	∙	If input is company / labeler scope (ndc6 or raw labeler-style prefix), return all unique normalized ndc11 rows across all matching products under that scope  
Final output requirements  
Return one final table with:  
	∙	one row per unique normalized ndc11  
	∙	stable ordering  
	∙	no duplicate rows  
	∙	all relevant columns present, even if empty  
Required identity columns:  
	∙	ndc11  
	∙	ndc11 display form  
	∙	source package NDC string  
	∙	product_ndc  
	∙	ndc9  
	∙	ndc6  
	∙	brand_name  
	∙	generic_name  
	∙	labeler_name  
	∙	dosage_form  
	∙	route  
	∙	package_description  
	∙	application_number  
	∙	spl_setid  
	∙	rxcui  
Required source handling  
The script must preserve source grain honestly.  
Package-native facts:  
	∙	openFDA package/listing details  
	∙	NADAC  
	∙	SDUD  
	∙	package-specific WAC if actually matched  
Brand/program-level facts:  
	∙	Medicare Part D  
	∙	Medicaid Spending by Drug  
HCPCS/program-level facts:  
	∙	Medicare Part B  
Regulatory/label facts:  
	∙	Drugs@FDA  
	∙	DailyMed  
	∙	SPL-related metadata  
Do not fake package-native precision for sources that are not package-native.  
If a source is family-level or HCPCS-level, it may be projected onto all applicable ndc11 rows, but must remain semantically honest.  
Problems already observed in the current prototype  
You must explicitly fix these:  
	1.	Binary source flags are too coarse  
	∙	0/1 alone is not enough  
	∙	We need explicit source status semantics  
	2.	NADAC and SDUD must be exact-package validated  
	∙	If a query returns rows but the returned source-native NDC does not exactly match the queried normalized ndc11, that is not a hit  
	∙	That must be marked as bad_filter, not hit  
	3.	Different source outcomes are being collapsed incorrectly  
	∙	Need to distinguish:  
	∙	hit  
	∙	no_match  
	∙	not_applicable  
	∙	bad_filter  
	∙	query_error  
	∙	no_exact_match where appropriate  
	4.	Legacy / dead endpoint noise must not pollute interpretation  
	∙	Do not rely on outdated endpoint assumptions  
	∙	Do not treat dead legacy probe results as authoritative evidence of source absence  
	5.	Input normalization must be robust  
	∙	exact  
	∙	hyphenated  
	∙	normalized  
	∙	labeler/company prefix forms  
	6.	Performance must be strong  
	∙	bounded concurrency  
	∙	local HTTP cache  
	∙	retries  
	∙	dedupe  
	∙	no redundant calls  
	∙	efficient family expansion  
	∙	deterministic output  
What I want you to deliver  
	1.	A revised standalone script  
	∙	production-usable  
	∙	shell-first / terminal-friendly  
	∙	no repo dependencies  
	2.	A concise explanation of architecture  
	∙	how the script resolves family scope  
	∙	how it fetches and validates source data  
	∙	how it builds the final matrix  
	3.	Explicit source columns in the final output  
For each relevant source, include:  
	∙	binary flag column, e.g. src_nadac  
	∙	explicit status column, e.g. src_nadac_status  
	4.	Honest KPI columns  
Include the most relevant fields per source, while preserving grain honesty  
	5.	Exact improvements over the current ndc_source_matrix_full_command.sh  
	∙	short but concrete  
	∙	no vague claims  
	6.	Example commands for:  
	∙	company input  
	∙	product input  
	∙	package input  
Acceptance criteria  
The result is acceptable only if all of the following are true:  
	∙	one user input at the top  
	∙	standalone execution only  
	∙	one row per unique normalized ndc11  
	∙	exact package/product/company expansion behavior works  
	∙	NADAC and SDUD exact-match validation is enforced  
	∙	source statuses are explicit and trustworthy  
	∙	mixed source grains are handled honestly  
	∙	no repo usage whatsoever  
	∙	no app/database assumptions whatsoever  
	∙	fast enough for practical repeated terminal use  
	∙	output is clear, stable, and audit-friendly  
Working style  
Be ruthless about:  
	∙	correctness  
	∙	speed  
	∙	explicit semantics  
	∙	reproducibility  
	∙	source-grain honesty  
Do not over-engineer.  
Do not build a framework.  
Do not propose migrating this into a service.  
Do not drift into dashboard logic.  
Keep it standalone, precise, and immediately runnable.  
