# ENSO Project — Global Climate & Food Security Analytics

A single consolidated document covering the project idea, value proposition, dashboard plan, repository structure, how to run the data collection, data sources (with their actual coverage), the FAOSTAT specification, technical notes, and team structure.

> **Revision note:** this version reflects the datasets already collected (ONI/Niño 3.4 events file, Niño indices, FAO Food Price Index, GPCP precipitation extract, FAOSTAT bulk files) and the decisions taken on countries, crops and method. All of them except the HDX events file (downloaded by hand from HDX) can be re-created automatically with `data/collect_data.py` (Section 4.2).

---

## 1. Project Idea

**Project name:** ENSO — Global Climate & Food Security Analytics

**What it is:** A professional data analytics project studying the El Niño–Southern Oscillation (ENSO) phenomenon and its downstream effects on regional rainfall, crop yields and global food commodity prices, built as a set of interactive dashboards backed by real NOAA and FAO data.

**ENSO = El Niño–Southern Oscillation**, a natural climate cycle driven by:
- Sea surface temperature changes in the tropical Pacific
- Atmospheric pressure shifts (the "Southern Oscillation")
- Resulting changes in wind, rainfall, and temperature patterns worldwide

**Three phases:**
| Phase | Description |
|---|---|
| El Niño | Unusual warming of Pacific sea surface temperatures |
| La Niña | Unusual cooling of Pacific sea surface temperatures |
| Neutral | Neither phase is active |

**Classification rule (used everywhere in the project):**
- ONI ≥ +0.5 for 5 consecutive overlapping 3-month seasons → El Niño
- ONI ≤ −0.5 for 5 consecutive overlapping 3-month seasons → La Niña
- Otherwise → Neutral
- Intensity (peak ONI of the event): Weak 0.5–0.9 · Moderate 1.0–1.4 · Strong 1.5–1.9 · Very strong ≥ 2.0

**Core research question:**
> How does ENSO influence regional rainfall, crop yields and global food prices, and which countries and crops are most exposed?

**Flow of the project:**
```
ENSO Event → Rainfall Anomaly → Crop Yield Anomaly → Food Price Response → Insights
```

---

## 2. Value Proposition

- **Real-world relevance**: ENSO affects agriculture, fisheries, energy markets, and global food commodity prices — this isn't an abstract academic exercise.
- **Free, credible data**: Everything comes from official sources (NOAA, FAO), not scraped or unverified data.
- **Broad skill demonstration**: time series analysis, data cleaning (wide-to-long reshaping, NetCDF handling), statistical analysis (correlation, lag analysis, anomaly detection, detrending), and dashboard/BI design.
- **Strong narrative**: "when ENSO shifts, here's what happens to rainfall, then yields, then prices, in these specific countries."
- **A live case study**: the data currently shows a strong El Niño developing in 2026 (ONI = +1.8 for JJA 2026; Niño 3.4 anomaly +2.52 °C and Niño 1+2 anomaly +4.08 °C in Aug 2026). The Early Warning dashboard is therefore not purely historical — it tracks an event in progress.
- **Honest statistics**: the project reports weak or mixed relationships as such (see Section 7), instead of forcing a causal story.

---

## 3. Dashboard Plan (5 Dashboards)

### Dashboard 1 — ENSO Overview
General view of the phenomenon over time.
- ONI timeline (1950–present)
- KPI cards: number of El Niño/La Niña events, average duration, strongest historical event
- Yearly classification chart (El Niño / La Niña / Neutral)
- Intensity distribution (weak / moderate / strong / very strong)

**Data used:** ONI

---

### Dashboard 2 — Regional Climate Impact
ENSO's effect on **rainfall** across the 14 selected countries.
- Map view of the selected countries (agricultural-region reference points, see Section 5.2)
- Precipitation anomaly comparison across El Niño / La Niña / Neutral phases
- Sea-surface-temperature context from the four Niño regions

**Data used:** ONI + Niño indices + GPCP

> Temperature anomalies were removed from the original plan because no temperature dataset is part of the project. If time allows, a country-level temperature source (e.g. Berkeley Earth or ERA5) can be added as an optional extension.

---

### Dashboard 3 — Regional Deep Dive
Detailed, user-selectable analysis for a single country.
- Dropdown to pick a country
- Comparative time series (monthly precipitation vs. its monthly climatology)
- Correlation coefficient between ONI and local precipitation anomaly
- Lag analysis chart (does the effect show up after 0, 1, 3, or 6 months?) — **monthly data only**

**Data used:** ONI + Niño indices + GPCP

---

### Dashboard 4 — ENSO Trend & Early Warning
Shifts the project from "explaining the past" to "reading the near future." No machine learning — built on trend detection and historical pattern matching. It is a **trend + analog view, not a forecast**.
- Current ENSO status: latest ONI value and classification (JJA 2026: +1.8, strong El Niño conditions)
- Trend indicator: direction of ONI over the last 3–6 months; Niño 1+2 / 3 / 3.4 / 4 anomalies for the latest month
- Historical analog: the past year whose Jan–Aug ONI trajectory is closest (RMSE) to 2026 — currently **1997**, followed by 1957, 1965, 1972 and 2023
- Risk outlook: which countries/crops were historically hit in comparable events (e.g. 1997, 2015, 2023) and would be watched if the trend continues

**Data used:** ONI + Niño indices (+ yields from FAOSTAT for the risk outlook)

---

### Dashboard 5 — Climate & Food Security Impact
Connects ENSO to crop yields and food prices.
- ENSO phase timeline as a reference layer at the top
- Global food price response (FAO sub-indices) around El Niño / La Niña periods
- Yield anomaly (detrended) by country and crop in El Niño vs. La Niña vs. Neutral years
- Country food-security risk score = precipitation anomaly + yield anomaly (+ optional import exposure for Egypt)
- Lag correlation between ONI and FAO price sub-indices (monthly)

**Data used:** ONI + GPCP + FAO Food Price Index + FAOSTAT QCL (crop production)

> FAO price indices are **global**, not per country. The country-level risk score therefore uses rainfall and yield, and price enters as a global layer.

---

## 4. Summary Table

| # | Dashboard | Focus | Data Sources |
|---|---|---|---|
| 1 | ENSO Overview | Phenomenon classification | ONI |
| 2 | Regional Climate Impact | Rainfall | ONI + Niño indices + GPCP |
| 3 | Regional Deep Dive | Detailed rainfall response | ONI + Niño indices + GPCP |
| 4 | Trend & Early Warning | Current event, analogs | ONI + Niño indices |
| 5 | Climate & Food Security | Yields and prices | ONI + GPCP + FFPI + FAOSTAT QCL |

**Architectural note:** ONI is the backbone across all five dashboards — it appears as a reference layer in every one, which gives the project strong internal consistency.

### 4.1 Repository Structure

```
NHA-5-112/
├── README.md
├── requirements.txt
├── .gitignore
├── dashboards/                       # Power BI files
├── data/
│   ├── collect_data.py               # re-creates the data files below, except the HDX file (Section 4.2)
│   ├── el-nino-southern-oscillation-enso-el-nino-and-la-nina-events(HDX).csv   # downloaded by hand from HDX
│   ├── ENSO_NINO_data.xlsx           # sheet NINO_Data
│   ├── ffpi-data-YYYY-MM.xlsx        # YYYY-MM = month of download
│   ├── gpcp_monthly_precipitation.csv
│   └── Production_Crops_Livestock_E_All_Data_(Normalized)/   # git-ignored, ~515 MB
│       ├── Production_Crops_Livestock_E_All_Data_(Normalized).csv
│       ├── Production_Crops_Livestock_E_AreaCodes.csv
│       ├── Production_Crops_Livestock_E_Elements.csv
│       ├── Production_Crops_Livestock_E_Flags.csv
│       └── Production_Crops_Livestock_E_ItemCodes.csv
├── docs/
│   └── Gemini_Generated_Image_gb5f4cgb5f4cgb5f.jpeg
├── notebooks/                        # statistical analysis (detrending, lags, analogs)
└── sql/                              # database schema and views (enso_schema.sql to be added)
```

The FAOSTAT folder is listed in `.gitignore`: the main file is far above GitHub's 100 MB limit, so it is downloaded by the script on each machine instead of being committed.

### 4.2 Running the Data Collection

Create a virtual environment once (Python 3.12 recommended; the versions in `requirements.txt` were tested on it):

```powershell
# Windows PowerShell, from the repository root
python -m venv .venv
.venv\Scripts\Activate.ps1        # if blocked: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
python -m pip install --upgrade pip
pip install -r requirements.txt
```

```bash
# macOS / Linux
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

The prompt shows `(.venv)` while the environment is active; leave it with `deactivate`. Then run:

```bash
python data/collect_data.py                     # everything
python data/collect_data.py --only nino gpcp    # selected sources: nino, ffpi, gpcp, faostat
python data/collect_data.py --force             # ignore the freshness checks
python data/collect_data.py --only ffpi --ffpi-file path/to/file.xlsx   # use a file you downloaded by hand
```

The script writes the files into the `data/` folder, with the names shown in 4.1 (it can be started from any folder). A failure in one source does not stop the others; a summary is printed at the end.

| Source | File written | Downloaded from | Refreshed |
|---|---|---|---|
| `nino` | `ENSO_NINO_data.xlsx` | NOAA CPC `sstoi.indices` | every run |
| `ffpi` | `ffpi-data-YYYY-MM.xlsx` | FAO Food Price Index page (link is found automatically) | if older than 1 day |
| `gpcp` | `gpcp_monthly_precipitation.csv` | NOAA PSL GPCP v2.3 NetCDF | every run |
| `faostat` | `Production_Crops_Livestock_E_All_Data_(Normalized)/` | FAOSTAT bulk zip, unpacked as is | if older than 90 days |

Notes:
- The HDX events file is **not** produced by the script; download it from HDX when it needs updating (link in Section 5.1).
- The GPCP file keeps the current layout: 10 countries, 2000-01 onward, the same reference points and country names (`USA_Midwest`, `South_Africa`, `Vietnam`). To change the points or the start date, edit `GPCP_POINTS` and `GPCP_START` at the top of the script.
- The FFPI file name uses the download month. Files from earlier months stay in the folder; delete old copies by hand.
- NOAA revises recent values, so a new run can differ slightly from the committed files in the latest months.

---

## 5. Data Sources

### 5.1 Datasets collected so far (actual coverage)

| Dataset | File | Coverage | Frequency | Notes |
|---|---|---|---|---|
| ONI / Niño 3.4 events | `el-nino-southern-oscillation-enso-el-nino-and-la-nina-events(HDX).csv` | 1950-01 → 2026-06 | Monthly | Long format: Niño 3.4 SST, climatology and anomaly, plus a 3-month mean, rounded value and two phase columns (`phase_trimester`, `phase_event`). The 3-month mean is **forward-looking**: a month's row holds the mean of that month and the next two (the January row is JFM). The last two months have no 3-month mean and are labelled `neutral`. |
| Niño indices (1+2, 3, 4, 3.4) | `ENSO_NINO_data.xlsx` | 1982-01 → 2026-08 | Monthly | SST and anomaly for each region; no missing values. |
| FAO Food Price Index | `ffpi-data-YYYY-MM.xlsx` (e.g. `ffpi-data-2026-09.xlsx`) | 1990-01 → 2026-08 | Monthly + annual | Sub-indices: Meat, Dairy, Cereals, Oils, Sugar (2014–2016 = 100). Nominal and **Real** sheets. |
| GPCP precipitation | `gpcp_monthly_precipitation.csv` | 2000-01 → 2026-06 | Monthly | 10 countries × 318 months, mm/day, nearest 2.5° grid point. |
| FAOSTAT QCL | `Production_Crops_Livestock_E_All_Data_(Normalized)/` (5 CSVs) | 1961 → latest year in the file; the project uses 1982 → | **Annual** | Full bulk file, not filtered. See Section 6. |

**Common analysis windows**
- Monthly analysis (rainfall, prices, lags): **2000-01 → 2026-06**
- Annual analysis (yields): **1982 → latest QCL year**; rainfall-linked annual analysis from 2000 (or from 1982 if GPCP is extended — see 5.2)

**Original source links**

| Dataset | Source | Link |
|---|---|---|
| ONI | NOAA CPC | https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/oni/v6/ |
| ONI (alternate copy) | NOAA PSL | https://psl.noaa.gov/data/correlation/oni.data |
| ONI / Niño 3.4 events file (the committed copy, downloaded by hand) | HDX | https://data.humdata.org/dataset/el-nino-southern-oscillation-enso-el-nino-and-la-nina-events |
| Niño indices | NOAA CPC | https://www.cpc.ncep.noaa.gov/data/indices/sstoi.indices |
| GPCP Monthly Precipitation | NOAA/NCEI | https://www.ncei.noaa.gov/data/global-precipitation-climatology-project-gpcp-monthly/access/ |
| GPCP v2.3 as one NetCDF file (the script downloads this) | NOAA PSL | https://psl.noaa.gov/thredds/fileServer/Datasets/gpcp/precip.mon.mean.nc |
| FAO Food Price Index | FAO | https://www.fao.org/worldfoodsituation/foodpricesindex |
| FAOSTAT Crops & Livestock (QCL) | FAO | https://www.fao.org/faostat/en/#data/QCL |
| FAOSTAT QCL bulk file (the script downloads this) | FAO | https://bulks-faostat.fao.org/production/Production_Crops_Livestock_E_All_Data_(Normalized).zip |

**Reliability note:** treat CPC as authoritative for ONI; if the PSL copy is used, spot-check the latest values against CPC.

**ONI vs RONI:** NOAA CPC has introduced the Relative ONI (RONI) as its operational index in 2026. This project keeps the traditional ONI-style classification because the rule in Section 1 is defined on it and it matches the literature. RONI can differ materially from ONI when the whole tropical ocean is warming, so the two must never be mixed in one analysis. Mention RONI in the final report as a limitation.

### 5.2 Precipitation (GPCP) — decisions and technical notes

- The extract currently covers 10 countries, one grid point each, located at the **country centroid**. Centroids are often not where crops grow, so reference points are revised as follows:

| Country | Current point | Issue | Recommended reference |
|---|---|---|---|
| Egypt | 26.8, 30.8 | Desert, mean 0.026 mm/day — no usable ENSO rainfall signal | Treat Egypt as an **import-exposure** case; use Blue Nile / Ethiopian highlands rainfall (~11°N, 37°E) as its climate driver |
| Australia | −25.3, 133.8 | Interior desert | Wheat belt: SW (~−32, 117) and SE (~−34, 147), averaged |
| Brazil | −14.2, −51.9 | Not the main crop zone | Average of southern (~−28, −53) and central-west soy/maize belt (~−15, −55) |
| South Africa | −30.6, 22.9 | Karoo, not the maize belt | Free State / Mpumalanga (~−28, 27) |
| USA_Midwest | 41.9, −87.6 | Chicago | Corn belt, Iowa (~42, −93) |
| India, Indonesia, Kenya, Peru, Vietnam | centroid | Acceptable; Peru additionally sensitive to coastal Niño 1+2 | Keep; optionally average a small box |

- New countries (Argentina, Thailand, Malaysia, Philippines) still need to be added to the GPCP extract (**not done yet**; the script currently re-creates the existing 10-country file).
- **Extend GPCP back to 1982** (the dataset starts in 1979) so rainfall and yields share the same 1982→ window (**not done yet**; change `GPCP_START` in `data/collect_data.py`).
- GPCP grids use 0–360 longitudes. Convert negative longitudes with `lon + 360` before `.sel(..., method='nearest')`. The script reads one NetCDF file from NOAA PSL and detects the dimension names itself (`lat`/`lon` or `latitude`/`longitude`); with the monthly NCEI files, combine them with `xr.open_mfdataset()`. Always `print(ds)` first.
- Use **v2.3 or later**; v2.2 is superseded.

### 5.3 Food data

| Dataset | Used for | Notes |
|---|---|---|
| FAO Food Price Index (monthly, **Real** sheet preferred) | Global price response, lag correlation with ONI | Global, not per country. Use the Real (inflation-adjusted) sheet for cross-period comparison. |
| FAOSTAT QCL | Yield, area harvested, production by country and crop | **Annual** only — see Section 6. |

### 5.4 Sources deliberately excluded

| Source | Reason |
|---|---|
| GPCC | Redundant with GPCP |
| MEI / SOI | Optional only — cross-validation of ONI |
| PSL Gridded Surface Tables | Content unclear |
| Coffee, cocoa, cotton (QCL) | No matching price series in the FFPI; add later only with another price source (e.g. World Bank Pink Sheet) |
| Fish / fishmeal (Peru) | Not covered by QCL |

---

## 6. FAOSTAT QCL Download Specification (one file)

`data/collect_data.py` downloads the full QCL bulk file and unpacks it into `data/Production_Crops_Livestock_E_All_Data_(Normalized)/`; filter it to the selections below in pandas or SQL. To get a pre-filtered CSV instead, download **one** CSV from https://www.fao.org/faostat/en/#data/QCL with the same selections.

**Countries (14):**
Argentina, Australia, Brazil, Egypt, India, Indonesia, Kenya, Malaysia, Peru, Philippines, South Africa, Thailand, United States of America, Viet Nam

(The first 10 match the GPCP extract — USA appears as the whole country in FAOSTAT and is analysed through the Midwest/corn-belt rainfall point. Argentina, Malaysia, Thailand and the Philippines are the additions.)

**Items (crops):**

| FFPI group | Item | Approx. item code* | Main countries |
|---|---|---|---|
| Cereals | Wheat | 15 | Australia, India, USA, Argentina, Egypt |
| Cereals | Rice | 27 | India, Indonesia, Vietnam, Thailand, Philippines, Egypt |
| Cereals | Maize (corn) | 56 | USA, Brazil, Argentina, South Africa, Kenya |
| Oils | Soya beans | 236 | Brazil, USA, Argentina |
| Oils | Oil palm fruit (and/or Palm oil) | 254 / 257 | Indonesia, Malaysia |
| Sugar | Sugar cane | 156 | Brazil, India, Thailand, Australia |
| Meat / Dairy (optional) | Meat of cattle (867), Raw milk of cattle (882) | 867 / 882 | Australia, Brazil, USA, India |

\*Codes are from memory of the FAOSTAT scheme — verify them in the item selector before downloading.

**Elements:** Production, Area harvested, Yield

**Years:** 1982 → latest available (select all)

**Output:** CSV, long format, with codes and flags included.

**Method notes for this dataset**
1. Analyse **Yield**, not raw Production (production is confounded by area changes and technology).
2. **Detrend** each country-crop yield series (e.g. linear or LOESS trend) and work with the anomaly (% deviation from trend).
3. Map ENSO to the crop's growing season (e.g. OND–JFM mean ONI for southern-hemisphere summer crops) rather than to the calendar year.
4. With ~40 annual points per series, compare yield anomalies across **El Niño / La Niña / Neutral years** instead of relying on correlation alone.
5. QCL is annual: **no monthly lag analysis on yields.** Monthly lags are for rainfall and FAO price indices only.

---

## 7. Known Statistical Expectations

A first pass on the collected data (monthly, 1990–2026, year-over-year change of the Real FAO sub-indices vs. ONI lagged 0–12 months) shows **weak relationships** — absolute correlations below ~0.4:

| Sub-index | Strongest pattern |
|---|---|
| Oils | Rises with ONI lag: r ≈ +0.03 (0 m) → +0.18 (6 m) → **+0.38 (12 m)** — consistent with El Niño-driven palm yield losses appearing after ~1 year |
| Cereals | Slightly negative at short lags (≈ −0.29 at 0 m) |
| Sugar, Meat, Dairy | Weak or inconsistent |

The project should present these as "partial, lagged, commodity-specific" effects, not as ENSO driving all food prices.

---

## 8. Proposed Technical Architecture

```
DATA SOURCES (NOAA + FAO)
        ↓
   Data Cleaning (Python)
        ↓
Data Transformation (wide→long, NetCDF → CSV via xarray)
        ↓
   SQL Database
   (dim_date, dim_region, dim_crop, fact_enso_index, fact_sst_indices,
    fact_climate, fact_food_price, fact_food_production,
    fact_food_security_risk — see enso_schema.sql)
        ↓
  Statistical Analysis (Python, querying the database)
  (Correlation, Lag Analysis, Anomaly Detection, Detrending, Analog matching)
        ↓
   Analytical Dataset / Views
        ↓
  Power BI Dashboards
```

**Toolchain, end to end:**
1. **Python** — pulls and cleans the raw sources and loads cleaned tables into the SQL database.
2. **SQL** — all five dashboards query the database rather than reading files directly.
3. **Python** (again) — statistical analysis on top of the database; writes results back as tables/views.
4. **Power BI** — connects to the SQL database (or analytical views/exports).

**Cleaning checklist**
- **ONI file:** already long and monthly. The 3-month mean is labelled with the season's **first** month, so shift `date` by one month (or label it with the centre month) before joining with monthly rainfall or prices. Treat the last two rows (no 3-month mean) as unknown, not as `neutral`.
- **FFPI:** headers start at row 5 of the sheets (title rows + blank row); drop trailing empty rows if any (the current file has values up to 2026-08); use `Indices_Monthly_Real` for comparisons over time.
- **Niño:** combine `YR` + `MON` into a date; keep both raw SST and anomaly.
- **GPCP:** unify country names with FAOSTAT (e.g. "Viet Nam" vs "Vietnam", "United States of America" vs "USA_Midwest").
- **QCL:** keep only element codes for Production/Area/Yield; drop flagged-as-imputed rows only if sensitivity tests show they matter.

**Key lessons carried into this architecture:**
1. NetCDF dimension names differ by source — always inspect the dataset before writing extraction code.
2. Longitude convention (0–360 vs. −180–180) must be normalised per source.
3. One dataset per data type to avoid redundant cleaning (GPCP only, not GPCP + GPCC).
4. Start with the simplest working version — a handful of countries and one solid dashboard — before scaling.
5. Never commit raw files above GitHub's 100 MB limit (the FAOSTAT main file is ~515 MB). Keep them in `.gitignore` and re-create them with `data/collect_data.py`; a push that contains such a file in any earlier commit is rejected.

---

## 9. Team Structure (6 people)

| Task | People | Description |
|---|---|---|
| Data collection + cleaning + ETL | 2 | ONI, Niño, GPCP (extended to 1982 + new countries), FFPI and QCL; reshaping; missing values and format mismatches |
| Statistical analysis | 1 | Detrending, anomalies, correlation, lag analysis, analog logic for Dashboard 4, risk score |
| Dashboard building | 2 | Building the 5 dashboards in Power BI |
| Documentation + presentation + QA | 1 | README, final report, slide deck, testing dashboard numbers against source data |

---

## 10. Tools & Libraries

| Tool | Purpose |
|---|---|
| `xarray` | Reading and processing NetCDF climate files |
| `netCDF4` | Low-level NetCDF support (used internally by xarray) |
| `pandas` | Tabular data cleaning, merging, and analysis |
| `requests`, `openpyxl`, `netCDF4` | Downloading the sources, reading/writing Excel files, reading NetCDF |
| `scipy.stats` | Correlation coefficients and lag analysis |
| `statsmodels` | Detrending (LOESS / linear) and regression checks |
| SQL database (PostgreSQL or similar) | Central storage for all cleaned data — schema in `enso_schema.sql` |
| `SQLAlchemy` / `psycopg2` | Loading cleaned DataFrames into the SQL database |
| Power BI | Final dashboards, connected to the SQL database |

**Final toolchain: Python (collection + cleaning + analysis) → SQL database (storage) → Power BI (dashboards).**

---

## 11. Open Items / Still To Confirm

- Run `data/collect_data.py` once against the live sources and fix anything that breaks (it was tested on local data and synthetic files, not on the live sites).
- Verify FAOSTAT item codes and the last available year in QCL (likely 2024).
- Add `sql/enso_schema.sql` to the repository (referenced in Section 8 but not yet committed).
- Add Argentina, Thailand, Malaysia, Philippines (and the revised reference points) to the GPCP extract; extend GPCP to 1982.
- Decide whether to add a temperature source (Berkeley Earth / ERA5) or leave Dashboard 2 rainfall-only.
- Decide whether the optional Meat/Dairy items (cattle meat, raw milk) are included.
- Whether MEI/SOI get added as an optional cross-validation layer on Dashboard 1, time permitting.