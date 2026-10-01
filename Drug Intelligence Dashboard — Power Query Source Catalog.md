# Drug Intelligence Dashboard — Power Query Source Catalog

Oct 1, 2026 · @Antonis

Every free public U.S. drug data API worth connecting, what each answers, the key it joins on, and a Power Query (M) query you can paste. Nothing here needs a sign-in.

## How it fits together

The user picks a brand, ingredient or package code; an identity master resolves it to every key the sources use, and each source joins on its own key.

&#91;embedded content: dashboard architecture · selector, identity master, 5 join keys\]

Two rules decide whether this works in Power Query:

1. **Select by brand or ingredient, drill down by package code.** Spending files are brand-level and price and volume files are package-level, so a package-code selector misses half the sources.
2. **Power Query runs at refresh, not on a slicer click.** Preload every drug for the small sources (spending files, NADAC latest, rebate file, master table) and filter with slicers. Pull the large ones (SDUD, prescriber files, FAERS) for a watchlist of brands, or through an Excel parameter cell and Refresh.

## Shared functions

Five reusable functions cover every source below; create each as a blank query, paste the code, and name it as shown. They are written to the published API docs but not run from here (this environment has no network), so test each on one small call first.

All use `Web.Contents(base, [RelativePath, Query])`, which keeps scheduled refresh working in the Power BI Service.

### fnCmsData — data.cms.gov, any dataset, all pages

```m
// fnCmsData("7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b", [#"filter[Brnd_Name]" = "Biktarvy"])
// pass null as filters to load the whole dataset
(datasetId as text, optional filters as nullable record) as table =>
let
    PageSize = 5000,
    Filt = if filters = null then [] else filters,
    GetPage = (offset as number) as list =>
        Json.Document(Web.Contents("https://data.cms.gov", [
            RelativePath = "data-api/v1/dataset/" & datasetId & "/data",
            Query = Filt & [size = Text.From(PageSize), offset = Text.From(offset)]
        ])),
    Pages = List.Generate(
        () => [o = 0, d = GetPage(0)],
        each List.Count([d]) > 0,
        each [o = [o] + PageSize,
              d = if List.Count([d]) < PageSize then {} else GetPage([o] + PageSize)],
        each [d]),
    Out = Table.FromRecords(List.Combine(Pages), null, MissingField.UseNull)
in
    Out
```

### fnMedicaidQuery — data.medicaid.gov (DKAN), filtered, all pages

```m
// fnMedicaidQuery("0ad65fe5-3ad3-5d79-a3f9-7893ded7963a",
//   {[property = "ndc", value = "61958250", operator = "starts with"]})
// operators: = <> < > in "not in" like contains "starts with" between
(datasetId as text, conditions as list) as table =>
let
    PageSize = 500,
    GetPage = (offset as number) as list =>
        Json.Document(Web.Contents("https://data.medicaid.gov", [
            RelativePath = "api/1/datastore/query/" & datasetId & "/0",
            Headers = [#"Content-Type" = "application/json"],
            Content = Json.FromValue([conditions = conditions, limit = PageSize,
                offset = offset, count = false, schema = false, keys = true])
        ]))[results],
    Pages = List.Generate(
        () => [o = 0, d = GetPage(0)],
        each List.Count([d]) > 0,
        each [o = [o] + PageSize,
              d = if List.Count([d]) < PageSize then {} else GetPage([o] + PageSize)],
        each [d]),
    Out = Table.FromRecords(List.Combine(Pages), null, MissingField.UseNull)
in
    Out
```

### fnMedicaidCatalog — find this year's dataset IDs

SDUD and NADAC get a new dataset ID every year. Resolve them by title instead of hardcoding.

```m
// fnMedicaidCatalog("State Drug Utilization Data")  -> identifier, title, modified
(titleStartsWith as text) as table =>
let
    Items = Json.Document(Web.Contents("https://data.medicaid.gov",
        [RelativePath = "api/1/metastore/schemas/dataset/items"])),
    T = Table.FromRecords(List.Transform(Items, each
        [identifier = [identifier], title = [title], modified = Record.FieldOrDefault(_, "modified", null)])),
    Out = Table.SelectRows(T, each Text.StartsWith([title], titleStartsWith, Comparer.OrdinalIgnoreCase))
in
    Out
```

### fnOpenFda — api.fda.gov, any drug endpoint

```m
// fnOpenFda("ndc", "brand_name:""Biktarvy""")   endpoints: ndc label drugsfda event enforcement shortages
// openFDA caps skip at 25,000; for whole-directory loads use the bulk zip instead
(endpoint as text, search as text) as table =>
let
    PageSize = 1000,
    GetPage = (skip as number) as list =>
        try Json.Document(Web.Contents("https://api.fda.gov", [
            RelativePath = "drug/" & endpoint & ".json",
            Query = [search = search, limit = Text.From(PageSize), skip = Text.From(skip)],
            ManualStatusHandling = {404}
        ]))[results] otherwise {},
    Pages = List.Generate(
        () => [s = 0, d = GetPage(0)],
        each List.Count([d]) > 0,
        each [s = [s] + PageSize,
              d = if List.Count([d]) < PageSize or [s] + PageSize >= 25000 then {} else GetPage([s] + PageSize)],
        each [d]),
    Out = Table.FromRecords(List.Combine(Pages), null, MissingField.UseNull)
in
    Out
```

openFDA returns 404 when nothing matches; the function turns that into an empty table. An optional free key (`api_key` in `Query`) raises the limit from 1,000 to 120,000 calls a day.

### fnUnzip — open zip files (Orange Book, ASP, openFDA bulk)

```m
// fnUnzip(Web.Contents("https://download.open.fda.gov", [RelativePath = "drug/ndc/drug-ndc-0001-of-0001.json.zip"]))
// returns Name + Content (binary) per file; then Json.Document / Csv.Document / Excel.Workbook on Content
(zip as binary) as table =>
let
    U16 = BinaryFormat.ByteOrder(BinaryFormat.UnsignedInteger16, ByteOrder.LittleEndian),
    U32 = BinaryFormat.ByteOrder(BinaryFormat.UnsignedInteger32, ByteOrder.LittleEndian),
    Header = BinaryFormat.Record([Signature = U32, Version = U16, Flags = U16, Method = U16,
        Time = U16, Date = U16, Crc = U32, CompSize = U32, Size = U32, NameLen = U16, ExtraLen = U16]),
    Entry = BinaryFormat.Choice(Header, (h) =>
        if h[Signature] <> 0x04034B50 then BinaryFormat.Null
        else BinaryFormat.Record([
            Name = BinaryFormat.Text(h[NameLen]),
            Extra = BinaryFormat.Binary(h[ExtraLen]),
            Content = BinaryFormat.Transform(BinaryFormat.Binary(h[CompSize]), (x) =>
                if h[Method] = 0 then x
                else try Binary.Buffer(Binary.Decompress(x, Compression.Deflate)) otherwise null)
        ]), type binary),
    Files = BinaryFormat.List(Entry, each _ <> null)(Binary.Buffer(zip)),
    Out = Table.FromRecords(List.Transform(List.RemoveNulls(Files), each [Name = [Name], Content = [Content]]))
in
    Out
```

This reads standard zips. A zip written in streaming mode stores sizes after the data, and this function returns nothing for it; for those, drop the unzipped files in a folder and use `Folder.Files`.

## Identity and classification

These build the master table every other source joins to: one row per package code (NDC-11) with brand, ingredient, labeler, RxCUI and class.

| Source | Base URL | Answers | Join key | Refresh |
| --- | --- | --- | --- | --- |
| [openFDA NDC](https://open.fda.gov/apis/drug/ndc/) | `api.fda.gov/drug/ndc.json` | Products and packages, labeler, brand and generic name, form, route, application number, pharmacologic class, SPL ID, RxCUI | NDC-11, application number | Bulk zip daily; API live |
| [FDA NDC Directory files](https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory) | `accessdata.fda.gov/cder/ndctext.zip` | Same directory as text files, plus unfinished and excluded products in separate zips | NDC-11 | Daily |
| [RxNav (RxNorm)](https://lhncbc.nlm.nih.gov/RxNav/APIs/) | `rxnav.nlm.nih.gov/REST/` | Name to products, RxCUI to package codes, package code to RxCUI and status (active or obsolete), ingredient and brand concepts | RxCUI, NDC-11 | Monthly |
| [RxClass](https://lhncbc.nlm.nih.gov/RxNav/APIs/RxClassAPIs.html) | `rxnav.nlm.nih.gov/REST/rxclass/` | Therapeutic class (ATC, VA, FDA established class) and every drug in a class, which gives you competitors | RxCUI | Monthly |
| [Drugs@FDA](https://open.fda.gov/apis/drug/drugsfda/) | `api.fda.gov/drug/drugsfda.json` | Approval history, sponsor, application type (NDA, ANDA, BLA), submissions | Application number | Weekly |
| [DailyMed](https://dailymed.nlm.nih.gov/dailymed/app-support-web-services.cfm) | `dailymed.nlm.nih.gov/dailymed/services/v2/` | Label versions and dates, package codes per label | SPL set ID | Daily |
| [openFDA drug label](https://open.fda.gov/apis/drug/label/) | `api.fda.gov/drug/label.json` | Indications, boxed warnings, dosing text | SPL set ID, brand | Weekly |
| [Orange Book](https://www.fda.gov/drugs/drug-approvals-and-databases/orange-book-data-files) / [Purple Book](https://purplebooksearch.fda.gov/) | FDA download pages (zip) | Patents, exclusivity, equivalence ratings: when generics or biosimilars can launch | Application number | Monthly |

RxNav needs no key and allows 20 calls per second per IP.

### Master table from the openFDA bulk file

Loads every marketed package in the U.S. in one refresh. File names are listed at `api.fda.gov/download.json` if this one changes.

```m
let
    Zip = fnUnzip(Web.Contents("https://download.open.fda.gov",
        [RelativePath = "drug/ndc/drug-ndc-0001-of-0001.json.zip"])),
    Raw = Json.Document(Zip{0}[Content])[results],
    Products = Table.FromRecords(Raw, null, MissingField.UseNull),
    Keep = Table.SelectColumns(Products, {"product_ndc", "brand_name", "generic_name", "labeler_name",
        "dosage_form", "route", "marketing_category", "application_number", "pharm_class",
        "packaging", "openfda"}, MissingField.UseNull),
    Packages = Table.ExpandRecordColumn(Table.ExpandListColumn(Keep, "packaging"), "packaging",
        {"package_ndc", "description", "marketing_start_date"}),
    Ndc11 = Table.AddColumn(Packages, "ndc11", each
        let p = Text.Split([package_ndc], "-") in
        Text.PadStart(p{0}, 5, "0") & Text.PadStart(p{1}, 4, "0") & Text.PadStart(p{2}, 2, "0"), type text),
    Lists = Table.TransformColumns(Ndc11, {{"route", each try Text.Combine(_, "|") otherwise null},
        {"pharm_class", each try Text.Combine(_, "|") otherwise null}}),
    Rx = Table.AddColumn(Lists, "rxcui", each try Text.Combine([openfda][rxcui], "|") otherwise null, type text),
    Spl = Table.AddColumn(Rx, "spl_set_id", each try [openfda][spl_set_id]{0} otherwise null, type text),
    Out = Table.RemoveColumns(Spl, {"openfda"})
in
    Out
```

Package codes come hyphenated in three layouts (4-4-2, 5-3-2, 5-4-1). Padding each segment, as above, gives the 11-digit billing code every Medicaid and CMS file uses.

### Selector search: name to products (RxNav)

```m
// pName = text parameter, e.g. "biktarvy" or "emtricitabine"
let
    J = Json.Document(Web.Contents("https://rxnav.nlm.nih.gov",
        [RelativePath = "REST/drugs.json", Query = [name = pName]])),
    Groups = List.Select(J[drugGroup][conceptGroup], each Record.HasFields(_, "conceptProperties")),
    Rows = List.Combine(List.Transform(Groups, each [conceptProperties])),
    Out = Table.SelectColumns(Table.FromRecords(Rows), {"rxcui", "name", "tty"})
in
    Out
```

`tty` tells you the level: `SBD` is a branded product, `SCD` the generic equivalent, `BN` the brand name.

### RxCUI to package codes, and package code to RxCUI

```m
// all package codes for one product RxCUI
let
    J = Json.Document(Web.Contents("https://rxnav.nlm.nih.gov",
        [RelativePath = "REST/rxcui/" & pRxcui & "/ndcs.json"])),
    Out = Table.FromList(try J[ndcGroup][ndcList][ndc] otherwise {}, Splitter.SplitByNothing(), {"ndc11"})
in
    Out

// status and RxCUI for one package code (works for obsolete codes too)
(ndc11 as text) as record =>
    Json.Document(Web.Contents("https://rxnav.nlm.nih.gov",
        [RelativePath = "REST/ndcstatus.json", Query = [ndc = ndc11]]))[ndcStatus]
```

### Therapeutic class and competitors (RxClass)

```m
// classes for one ingredient RxCUI; relaSource: ATC, VA, FDASPL (established class)
let
    J = Json.Document(Web.Contents("https://rxnav.nlm.nih.gov",
        [RelativePath = "REST/rxclass/class/byRxcui.json", Query = [rxcui = pRxcui, relaSource = "ATC"]])),
    Items = List.Transform(J[rxclassDrugInfoList][rxclassDrugInfo], each [rxclassMinConceptItem]),
    Out = Table.Distinct(Table.FromRecords(Items))
in
    Out

// every drug in one class, e.g. ATC J05AR (HIV antiviral combinations)
let
    J = Json.Document(Web.Contents("https://rxnav.nlm.nih.gov",
        [RelativePath = "REST/rxclass/classMembers.json", Query = [classId = pClassId, relaSource = "ATC"]])),
    Out = Table.FromRecords(List.Transform(J[drugMemberGroup][drugMember], each [minConcept]))
in
    Out
```

### Approvals and labels

```m
// approval history
fnOpenFda("drugsfda", "openfda.brand_name:""" & pBrand & """")

// label versions (DailyMed)
let
    J = Json.Document(Web.Contents("https://dailymed.nlm.nih.gov",
        [RelativePath = "dailymed/services/v2/spls.json", Query = [drug_name = pBrand, pagesize = "100"]])),
    Out = Table.FromRecords(J[data])
in
    Out
```

## Prices

Four public price points exist per drug: list price (WAC), pharmacy acquisition cost (NADAC), Medicaid ceiling (FUL, generics only) and Medicare Part B payment (ASP + 6%). Net price is not public.

| Source | Where | Answers | Join key | Refresh |
| --- | --- | --- | --- | --- |
| [NADAC](https://www.medicaid.gov/medicaid/prescription-drugs/pharmacy-pricing) | data.medicaid.gov, one dataset per year | Retail pharmacy acquisition cost per unit, weekly | NDC-11 | Weekly |
| [Federal Upper Limits](https://www.medicaid.gov/medicaid/prescription-drugs/federal-upper-limits/index.html) | data.medicaid.gov | Medicaid reimbursement ceiling for multi-source drugs | NDC-11 | Monthly |
| [Medicaid Drug Rebate Program product file](https://data.medicaid.gov/dataset/0ad65fe5-3ad3-5d79-a3f9-7893ded7963a) | data.medicaid.gov `0ad65fe5-3ad3-5d79-a3f9-7893ded7963a` | Every covered package code, drug category (single source, innovator, generic: sets the rebate formula), market and termination dates, units per package | NDC-11 | Quarterly + weekly additions |
| [ASP pricing files](https://www.cms.gov/medicare/payment/part-b-drugs/asp-pricing-files) | cms.gov, quarterly zip | Part B payment limit per HCPCS code; the same page carries the package-code-to-HCPCS crosswalk | HCPCS, NDC-11 | Quarterly |
| [California WAC increases](https://data.chhs.ca.gov/dataset/prescription-drug-wholesale-acquisition-cost-wac-increases) and [new drugs](https://data.chhs.ca.gov/dataset/prescription-drugs-introduced-to-market) | `data.chhs.ca.gov/api/3/action/` (CKAN) | List price increases above the reporting threshold, launch list price | NDC-11 | Monthly |
| Part D formulary and pricing files | data.cms.gov, quarterly zip (several GB) | Plan tier, prior auth, step therapy; plan-level unit cost | RxCUI, NDC-11 | Quarterly |
| [Negotiated prices (MFP)](https://www.cms.gov/priorities/medicare-prescription-drug-affordability/overview/medicare-drug-price-negotiation-program) | cms.gov, PDF and CSV | Medicare negotiated price for selected drugs | Brand | Per cycle |

The rebate program file carries no rebate amounts; those are confidential by statute.

### NADAC, every year, for a set of package codes

```m
// pNdcList = list of NDC-11 text values, e.g. from the master table filtered by the selector
let
    Years = fnMedicaidCatalog("NADAC (National Average Drug Acquisition Cost)"),
    Cond = {[property = "ndc", value = pNdcList, operator = "in"]},
    PerYear = Table.AddColumn(Years, "rows", each fnMedicaidQuery([identifier], Cond)),
    Out = Table.Combine(PerYear[rows]),
    Typed = Table.TransformColumnTypes(Out, {{"nadac_per_unit", type number},
        {"effective_date", type date}, {"as_of_date", type date}})
in
    Typed
```

Each weekly file repeats every NDC, so keep the latest `as_of_date` per `ndc` and `effective_date` before charting.

### Whole dataset as CSV (no filter)

For a dashboard that preloads every drug, download the full table instead of paging the API.

```m
// pDatasetId = e.g. the latest NADAC year from fnMedicaidCatalog
let
    Raw = Web.Contents("https://data.medicaid.gov",
        [RelativePath = "api/1/datastore/query/" & pDatasetId & "/0/download", Query = [format = "csv"]]),
    Out = Table.PromoteHeaders(Csv.Document(Raw, [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]))
in
    Out
```

### Rebate program product file, one labeler or product

```m
// package codes starting 61958250 = one product family; 61958 = the whole labeler
fnMedicaidQuery("0ad65fe5-3ad3-5d79-a3f9-7893ded7963a",
    {[property = "ndc", value = pNdcPrefix, operator = "starts with"]})
```

### California WAC (CKAN): find the resource, then query it

```m
let
    Pkg = Json.Document(Web.Contents("https://data.chhs.ca.gov", [RelativePath = "api/3/action/package_show",
        Query = [id = "prescription-drug-wholesale-acquisition-cost-wac-increases"]]))[result],
    Resources = Table.FromRecords(Pkg[resources], {"id", "name", "format", "datastore_active"}, MissingField.UseNull),
    Data = Table.SelectRows(Resources, each [datastore_active] = true){0}[id],
    J = Json.Document(Web.Contents("https://data.chhs.ca.gov", [RelativePath = "api/3/action/datastore_search",
        Query = [resource_id = Data, q = pBrand, limit = "32000"]])),
    Out = Table.FromRecords(J[result][records])
in
    Out
```

Resolving the resource at refresh avoids pointing at the data dictionary by mistake, which the old repo did.

### ASP payment limit for one HCPCS code

```m
// pAspZipUrl = this quarter's zip from the CMS ASP page (file names change each quarter)
let
    Files = fnUnzip(Web.Contents(pAspZipUrl)),
    Xl = Table.SelectRows(Files, each Text.EndsWith(Text.Lower([Name]), ".xlsx")){0}[Content],
    Sheet = Excel.Workbook(Xl, false){0}[Data],
    HeaderRow = List.PositionOf(Table.Column(Sheet, "Column1"), "HCPCS Code", Occurrence.First,
        (a, b) => Text.Trim(Text.From(a ?? "")) = b),
    Body = Table.PromoteHeaders(Table.Skip(Sheet, HeaderRow)),
    Out = Table.SelectRows(Body, each [HCPCS Code] = pHcpcs)
in
    Out
```

`Web.Contents` on a full URL from a parameter will not refresh in the Power BI Service; there, split it into base and `RelativePath`, or refresh the ASP query in Desktop only.

## Spending and use

Medicare and Medicaid spending files are small enough to preload for every drug; only the prescriber and SDUD files need filtering.

| Dataset | Dataset ID | Grain | Rows (approx.) | Join key |
| --- | --- | --- | --- | --- |
| [Medicare Part D Spending by Drug](https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-part-d-spending-by-drug) | `7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b` | Brand × manufacturer, 5 years wide | Thousands | Brand |
| [Medicare Quarterly Part D Spending by Drug](https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-quarterly-part-d-spending-by-drug) | `4ff7c618-4e40-483a-b390-c8a58c94fa15` | Brand × period label (preliminary) | Thousands | Brand |
| [Medicare Part B Spending by Drug](https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-part-b-spending-by-drug) | `76a714ad-3a2c-43ac-b76d-9dadf8f7d890` | HCPCS, 5 years wide | Hundreds | HCPCS |
| [Medicare Quarterly Part B Spending by Drug](https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicare-quarterly-part-b-spending-by-drug) | `bf6a5b3b-31ee-4abb-b1ad-2607a1e7510a` | HCPCS × period label | Hundreds | HCPCS |
| [Medicaid Spending by Drug](https://data.cms.gov/summary-statistics-on-use-and-payments/medicare-medicaid-spending-by-drug/medicaid-spending-by-drug) | `be64fce3-e835-4589-b46b-024198e524a6` | Brand × manufacturer, 5 years wide | Thousands | Brand |
| Medicare Part D Prescribers – by Geography and Drug | resolve with fnCmsCatalog | State × brand | Hundreds of thousands | Brand, state |
| Medicare Part D Prescribers – by Provider and Drug | resolve with fnCmsCatalog | Prescriber (NPI) × brand | About 25 million | Brand, NPI |
| Medicare Physician & Other Practitioners – by Provider and Service | resolve with fnCmsCatalog | Clinician (NPI) × HCPCS: clinic-administered drugs | About 10 million | HCPCS, NPI |
| [State Drug Utilization Data](https://www.medicaid.gov/medicaid/prescription-drugs/state-drug-utilization-data/index.html) | one per year, resolve with fnMedicaidCatalog | NDC-11 × state × quarter × fee-for-service or managed care | About 5 million a year | NDC-11, state |

The five IDs above are stable series IDs that roll to each new release; they were live on 30 Sep 2026.

### fnCmsCatalog — find any data.cms.gov dataset by title

```m
// fnCmsCatalog("Part D Prescribers - by Geography and Drug") -> title, modified, datasetId
(titleContains as text) as table =>
let
    Cat = Json.Document(Web.Contents("https://data.cms.gov", [RelativePath = "v1-1-data.json"]))[dataset],
    T = Table.FromRecords(List.Transform(Cat, each [title = [title],
        modified = Record.FieldOrDefault(_, "modified", null), dist = [distribution]])),
    Sel = Table.SelectRows(T, each Text.Contains([title], titleContains, Comparer.OrdinalIgnoreCase)),
    Id = Table.AddColumn(Sel, "datasetId", each
        let d = List.Select([dist], each
                Text.Contains(Record.FieldOrDefault(_, "accessURL", ""), "/data-api/v1/dataset/")
                and Record.FieldOrDefault(_, "description", "") = "latest")
        in if List.IsEmpty(d) then null
           else Text.BetweenDelimiters(d{0}[accessURL], "/dataset/", "/data"), type text),
    Out = Table.RemoveColumns(Id, {"dist"})
in
    Out
```

Use `v1-1-data.json`, not `data.json`: the latter switched to DCAT-US v3, with one entry per release.

### Part D spending, all drugs, long format for charts

```m
let
    Raw = fnCmsData("7e0b4365-fd63-4a29-8f5e-e0ac9f66a81b", null),
    Overall = Table.SelectRows(Raw, each [Mftr_Name] = "Overall"),
    Ids = {"Brnd_Name", "Gnrc_Name", "Tot_Mftr", "Mftr_Name"},
    Long = Table.UnpivotOtherColumns(Overall, Ids, "col", "value"),
    Yearly = Table.SelectRows(Long, each Text.Length([col]) > 5
        and Value.Is(Value.FromText(Text.End([col], 4)), type number)
        and Text.At([col], Text.Length([col]) - 5) = "_"),
    Split = Table.AddColumn(Table.AddColumn(Yearly, "metric", each Text.Start([col], Text.Length([col]) - 5)),
        "year", each Text.End([col], 4)),
    Out = Table.TransformColumnTypes(Table.RemoveColumns(Split, {"col"}), {{"value", type number}})
in
    Out
```

- Keep only `Mftr_Name = "Overall"`: every brand also appears once per manufacturer, and summing both doubles spend.
- The year filter drops change columns such as `Chg_Avg_Spnd_Per_Dsg_Unt_23_24`. Recompute changes yourself; the Medicaid file's Overall-row change fields disagree with its own yearly values.
- The same query works for Medicaid Spending (`be64fce3…`) and Part B (`76a714ad…`; its ID columns are `HCPCS_Cd`, `HCPCS_Desc`, `Brnd_Name`, `Gnrc_Name`).
- Quarterly files carry one `Year` label per row (`2025 (Q1-Q4)`, `2026 (Q1)`); filter to one label and never add labels together.

### Prescribers for the selected brand

```m
let
    Id = fnCmsCatalog("Part D Prescribers - by Provider and Drug"){0}[datasetId],
    Out = fnCmsData(Id, [#"filter[Brnd_Name]" = pBrand])
in
    Out
```

Swap the title for `by Geography and Drug` to get state rows; keep `Prscrbr_Geo_Lvl = "State"` and drop the `National` row.

### SDUD for a set of package codes, every year

```m
let
    Years = Table.SelectRows(fnMedicaidCatalog("State Drug Utilization Data"),
        each Text.Length([title]) = Text.Length("State Drug Utilization Data 2024")),
    Cond = {[property = "ndc", value = pNdcList, operator = "in"]},
    PerYear = Table.AddColumn(Years, "rows", each fnMedicaidQuery([identifier], Cond)),
    Out = Table.Combine(PerYear[rows]),
    States = Table.SelectRows(Out, each [state] <> "XX")
in
    States
```

- `XX` rows are national totals; adding them to state rows double-counts.
- `suppression_used = true` means CMS blanked a cell under 11 prescriptions; totals are minimums.
- For a whole year of every drug, use the CSV download pattern under Prices instead of paging.

## Safety, market, providers and policy

These turn a spending dashboard into an investigation tool: supply risk, adverse events, pipeline, who prescribes, who gets paid to promote, and coverage rules.

| Source | Base URL | Answers | Join key |
| --- | --- | --- | --- |
| [FDA drug shortages](https://open.fda.gov/apis/drug/drugshortages/) | `api.fda.gov/drug/shortages.json` | Current and resolved shortages, reason, availability | NDC, generic name |
| [Recalls (enforcement)](https://open.fda.gov/apis/drug/enforcement/) | `api.fda.gov/drug/enforcement.json` | Recall class, reason, dates, affected lots | Brand, NDC |
| [FAERS adverse events](https://open.fda.gov/apis/drug/event/) | `api.fda.gov/drug/event.json` | Report counts by reaction, outcome or year | Brand, generic |
| [ClinicalTrials.gov](https://clinicaltrials.gov/data-api/api) | `clinicaltrials.gov/api/v2/studies` | Trials by drug: phase, status, sponsor, start date | Drug name |
| [NPPES NPI Registry](https://npiregistry.cms.hhs.gov/api-page) | `npiregistry.cms.hhs.gov/api/` | Prescriber or clinic name, specialty, address | NPI |
| [Open Payments](https://openpaymentsdata.cms.gov/about/api) | `openpaymentsdata.cms.gov/api/1/` (DKAN) | Manufacturer payments to doctors and teaching hospitals, by drug | NPI, drug name |
| [CMS Provider Data Catalog](https://data.cms.gov/provider-data/) | `data.cms.gov/provider-data/api/1/` (DKAN) | Hospitals, dialysis centers, other facilities; no drug spending | Facility ID |
| [HRSA 340B OPAIS](https://340bopais.hrsa.gov/) | `340bopais.hrsa.gov` | 340B covered entities and contract pharmacies | Entity, address |
| [CMS Coverage API](https://api.coverage.cms.gov/) | `api.coverage.cms.gov` | National and local Medicare coverage policies, self-administered drug exclusions | HCPCS, drug name |
| [Federal Register](https://www.federalregister.gov/developers/documentation/api/v1) | `federalregister.gov/api/v1/` | Rules and notices that mention a drug or program | Text |
| [SEC EDGAR](https://www.sec.gov/search-filings/edgar-application-programming-interfaces) | `data.sec.gov/api/xbrl/` | Manufacturer revenue and financials (product sales usually only in 10-K text) | Company CIK |

No key needed for any of them. EDGAR requires a `User-Agent` header with a name and email. Local coverage endpoints in the CMS Coverage API need a free token from its license-agreement endpoint. I could not confirm a stable public API for 340B OPAIS; plan on its export files.

### Shortages and recalls

```m
fnOpenFda("shortages", "generic_name:""" & pGeneric & """")
fnOpenFda("enforcement", "openfda.brand_name:""" & pBrand & """")
```

### Adverse event counts (FAERS)

Ask for counts, not raw reports; raw reports hit the 25,000-record skip limit fast.

```m
// top reactions; use count = "receivedate" for a daily time series instead
let
    J = Json.Document(Web.Contents("https://api.fda.gov", [RelativePath = "drug/event.json",
        Query = [search = "patient.drug.openfda.brand_name:""" & pBrand & """",
                 count = "patient.reaction.reactionmeddrapt.exact", limit = "100"],
        ManualStatusHandling = {404}])),
    Out = try Table.FromRecords(J[results]) otherwise #table({"term", "count"}, {})
in
    Out
```

FAERS counts reports, not patients or incidence; label it that way.

### Clinical trials (ClinicalTrials.gov v2)

```m
let
    Get = (token as nullable text) => Json.Document(Web.Contents("https://clinicaltrials.gov",
        [RelativePath = "api/v2/studies",
         Query = [#"query.intr" = pDrug, pageSize = "1000"] & (if token = null then [] else [pageToken = token])])),
    Pages = List.Generate(() => Get(null), each _ <> null,
        each if Record.HasFields(_, "nextPageToken") then Get([nextPageToken]) else null,
        each [studies]),
    Rows = List.Transform(List.Combine(Pages), each let p = [protocolSection] in [
        nct = p[identificationModule][nctId],
        title = p[identificationModule][briefTitle],
        status = p[statusModule][overallStatus],
        phase = try Text.Combine(p[designModule][phases], "|") otherwise null,
        sponsor = try p[sponsorCollaboratorsModule][leadSponsor][name] otherwise null,
        start = try p[statusModule][startDateStruct][date] otherwise null]),
    Out = Table.FromRecords(Rows)
in
    Out
```

### Prescriber details (NPPES), one NPI

```m
(npi as text) as record =>
let
    J = Json.Document(Web.Contents("https://npiregistry.cms.hhs.gov",
        [RelativePath = "api/", Query = [version = "2.1", number = npi]])),
    R = J[results]{0},
    Out = [npi = npi,
           name = try R[basic][organization_name] otherwise R[basic][first_name] & " " & R[basic][last_name],
           specialty = try List.First(List.Select(R[taxonomies], each [primary]))[desc] otherwise null,
           state = try R[addresses]{0}[state] otherwise null]
in
    Out
```

Call it only on the top prescribers from the Part D provider file; for thousands of NPIs, load the monthly NPPES bulk file instead.

### Manufacturer payments (Open Payments)

Open Payments runs the same DKAN software as data.medicaid.gov. Duplicate `fnMedicaidQuery` as `fnOpenPaymentsQuery`, change the host to `https://openpaymentsdata.cms.gov`, and find each program year's General Payments dataset through its `api/1/metastore/schemas/dataset/items`. Filter on the drug name column (`name_of_drug_or_biological_or_device_or_medical_supply_1` in recent years; confirm against that year's data dictionary).

### Manufacturer financials (EDGAR)

```m
// pCik = 10-digit CIK with leading zeros
let
    J = Json.Document(Web.Contents("https://data.sec.gov",
        [RelativePath = "api/xbrl/companyfacts/CIK" & pCik & ".json",
         Headers = [#"User-Agent" = "Your Name your@email.com"]])),
    Rev = J[facts][#"us-gaap"][RevenueFromContractWithCustomerExcludingAssessedTax][units][USD],
    Out = Table.SelectRows(Table.FromRecords(Rev, null, MissingField.UseNull), each [form] = "10-K")
in
    Out
```

## Limits, gaps and refresh

Show the gaps on the dashboard itself: a view that says "not public" is more credible than one that implies completeness.

### Not in any public source

| Missing | Closest public stand-in |
| --- | --- |
| Net price after rebates | Medicaid statutory minimum: 23.1% of AMP for brand drugs, plus an inflation penalty |
| Actual Medicaid and Part D rebates | None; Medicare publishes only program-wide totals |
| AMP (average manufacturer price) | NADAC, close to retail AMP |
| 340B ceiling prices and volume | OPAIS lists entities only |
| Commercial and cash claims | None |
| Ryan White ADAP purchasing | None |

### API limits

| Host | Page size | Other limits |
| --- | --- | --- |
| data.cms.gov | 5,000 rows | No key |
| data.medicaid.gov | 500 rows | No key; returns 503 under heavy load, retry later |
| api.fda.gov | 1,000 rows | Skip at most 25,000; 1,000 calls a day without a key, 120,000 with a free key |
| rxnav.nlm.nih.gov | n/a | 20 calls a second per IP |
| clinicaltrials.gov | 1,000 studies | Page with `nextPageToken` |
| npiregistry.cms.hhs.gov | 200 results | Use the bulk file for large NPI lists |
| data.sec.gov | n/a | 10 calls a second; `User-Agent` header required |

### Refresh rules

- **Power Query runs at refresh, not on slicer click.** In Excel, put the brand or package code in a parameter cell and refresh. In Power BI, preload all drugs for the small sources and filter with slicers; pull the big ones (SDUD, prescriber files, FAERS) for a watchlist of brands.
- **Keep URLs static in the Power BI Service.** Build every call as `Web.Contents("https://host", [RelativePath = …, Query = …])`. A URL assembled by concatenation is a dynamic data source, and scheduled refresh refuses it.
- **Set privacy levels to Public** for all of these hosts, or Power Query blocks queries that combine them.
- **Resolve yearly dataset IDs at refresh** with `fnMedicaidCatalog` and `fnCmsCatalog`; never hardcode SDUD or NADAC years.
- **Normalize brand names before joining:** uppercase, trim, and strip CMS's trailing `*` (as in `Abilify*`).
- **Label preliminary data.** Quarterly CMS files and the latest SDUD quarter revise with each release.
- **Check releases with `modified`, not `temporal`,** in both catalogs.

## Sources

Dataset IDs and catalog behavior were checked against live CMS responses and an uploaded copy of the data.cms.gov v1.1 catalog on 30 Sep 2026. Endpoint paths follow each provider's API documentation; the M code has not been run from this environment.

- [openFDA APIs](https://open.fda.gov/apis/) and [download list](https://api.fda.gov/download.json)
- [RxNav / RxNorm APIs](https://lhncbc.nlm.nih.gov/RxNav/APIs/) and [RxClass API](https://lhncbc.nlm.nih.gov/RxNav/APIs/RxClassAPIs.html)
- [DailyMed web services](https://dailymed.nlm.nih.gov/dailymed/app-support-web-services.cfm)
- [data.cms.gov API docs](https://data.cms.gov/api-docs) and [v1.1 catalog](https://data.cms.gov/v1-1-data.json)
- [data.medicaid.gov](https://data.medicaid.gov/) and [Medicaid pharmacy pricing](https://www.medicaid.gov/medicaid/prescription-drugs/pharmacy-pricing)
- [Medicaid Drug Rebate Program data](https://www.medicaid.gov/medicaid/prescription-drugs/medicaid-drug-rebate-program/medicaid-drug-rebate-program-data)
- [CMS ASP pricing files](https://www.cms.gov/medicare/payment/part-b-drugs/asp-pricing-files)
- [California HCAI drug price transparency](https://data.chhs.ca.gov/dataset/prescription-drug-wholesale-acquisition-cost-wac-increases)
- [ClinicalTrials.gov API](https://clinicaltrials.gov/data-api/api)
- [NPPES NPI Registry API](https://npiregistry.cms.hhs.gov/api-page)
- [Open Payments API](https://openpaymentsdata.cms.gov/about/api)
- [CMS Coverage API](https://api.coverage.cms.gov/)
- [Federal Register API](https://www.federalregister.gov/developers/documentation/api/v1)
- [SEC EDGAR APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
