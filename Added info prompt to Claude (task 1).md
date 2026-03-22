# Added info prompt to Claude (task 1)  
  
Your design direction was good. The delivered script file is not acceptable yet.  
What is wrong with the current artifact:  
	∙	it is not runnable as delivered  
	∙	it contains smart quotes instead of normal ASCII quotes  
	∙	it contains markdown/code-fence leakage inside the script  
	∙	the heredoc structure is malformed  
	∙	Python indentation is broken in places  
	∙	there are still unsafe string-handling patterns that can fail on booleans  
	∙	output path behavior is not cleanly standalone/reusable  
	∙	the summary and the actual file do not match  
I do NOT want a repo change.  
I do NOT want app/dashboard work.  
I want only the standalone script fixed and delivered properly.  
Your task now:  
Rebuild the script as a clean standalone artifact from scratch, using the same intended architecture, but make the actual file production-runnable.  
Hard requirements:  
	1.	Fully standalone  
	∙	no repo imports  
	∙	no internal app/db/runtime dependencies  
	∙	terminal runnable only  
	2.	One user input near the top:  
	∙	company/labeler scope: 0006 / 00006 / 000060  
	∙	product scope: 0006-0277 / 000060277 / 50090-4084  
	∙	package scope: 0006-0277-02 / 00006027702 / 50090-4084-0  
	3.	Final row grain:  
	∙	exactly one row per unique normalized ndc11  
	4.	Keep explicit source status semantics:  
	∙	hit  
	∙	no_match  
	∙	not_applicable  
	∙	bad_filter  
	∙	query_error  
	∙	no_exact_match where appropriate  
	5.	NADAC / SDUD / WAC must use exact ndc11 validation  
	∙	if returned rows do not exactly match queried ndc11, do not mark hit  
	6.	Mixed source grains must remain honest  
	∙	Part D and Medicaid Spending are family/brand-level projections  
	∙	Part B is HCPCS-level, not package-native  
	∙	do not fake package precision  
	7.	Use only plain ASCII in the delivered file  
	∙	no smart quotes  
	∙	no markdown fences inside the script  
	∙	no malformed heredocs  
	8.	Safe string handling everywhere  
	∙	no .strip() on booleans or non-strings  
	9.	Strong execution behavior  
	∙	bounded concurrency  
	∙	local filesystem HTTP cache  
	∙	retry/backoff  
	∙	dedupe  
	∙	deterministic output ordering  
	10.	Clean output  
	∙	full matrix CSV  
	∙	compact CSV  
	∙	resolution JSON  
	∙	clear console summary  
Deliver exactly these things:  
	1.	The corrected full script as a single clean code block  
	2.	A short explanation of what you fixed versus the broken artifact  
	3.	Exact commands to run for:  
	∙	company input  
	∙	product input  
	∙	package input  
	4.	A self-check section:  
	∙	show the exact command(s) I can run to validate that the script is syntactically clean before execution  
	∙	shell check + python parse check if applicable  
	5.	A short expected output example description  
Before finishing, you must internally verify:  
	∙	the shell wrapper is syntactically valid  
	∙	the heredoc is valid  
	∙	the embedded Python is syntactically valid  
	∙	the script can be copy-pasted as-is into a file and executed  
Important:  
Do not give me another architecture memo with a broken file attached.  
Give me the final runnable standalone script.  
I reattached  the earlier attached semantic/source docs as well as your rejected deliverable in case  they are no longer available in session,  
