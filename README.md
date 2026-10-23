# ENSO Project — Full Data Dump

A single consolidated document covering the project idea, value proposition, dashboard plan, data sources, technical notes, and team structure.

---

## 1. Project Idea

**Project name:** ENSO — Global Climate & Food Security Analytics

**What it is:** A professional data analytics project studying the El Niño–Southern Oscillation (ENSO) phenomenon and its downstream effects on global climate patterns and food security, built as a set of interactive dashboards backed by real NOAA and FAO data.

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

**Core research question:**
> How does ENSO influence global temperature, precipitation, and food security, and which regions are most affected?

**Flow of the project:**
```
ENSO Event → Climate Changes → Regional Impact → Food Security Impact → Insights
```

---

## 2. Value Proposition

- **Real-world relevance**: ENSO affects agriculture, fisheries, energy markets, and global food commodity prices — this isn't an abstract academic exercise.
- **Free, credible data**: Everything comes from official sources (NOAA, FAO), not scraped or unverified data.
- **Broad skill demonstration**: time series analysis, data cleaning (including NetCDF handling), statistical analysis (correlation, lag analysis, anomaly detection), and dashboard/BI design.
- **Strong narrative**: the project can tell a clear, causal-adjacent story — "when ENSO shifts, here's what happens to rainfall, temperature, and eventually food prices, in these specific regions."
- **Forward-looking component**: unlike a purely historical analysis, the Prediction & Early Warning dashboard turns this into a decision-support tool, not just a retrospective report.

---

## 3. Dashboard Plan (5 Dashboards)

### Dashboard 1 — ENSO Overview
General view of the phenomenon over time.
- ONI Index timeline (1950–present)
- KPI cards: number of El Niño/La Niña events, average duration, strongest historical event
- Yearly classification chart (El Niño / La Niña / Neutral)
- Intensity distribution (weak / moderate / strong)

**Data used:** ONI

---

### Dashboard 2 — Global/Regional Climate Impact
ENSO's effect on temperature and rainfall across selected regions (10–15 countries, not the entire globe).
- Map view of selected regions
- Temperature anomaly comparison across El Niño / La Niña / Neutral phases
- Precipitation anomaly for the same regions

**Data used:** ONI + GPCP

---

### Dashboard 3 — Regional Deep Dive
Detailed, user-selectable analysis for a single region.
- Dropdown to pick a country/region
- Comparative time series (actual values vs. baseline)
- Correlation coefficient between ONI and the local climate variable
- Lag analysis chart (does the effect show up after 1, 3, or 6 months?)

**Data used:** ONI + sstoi.indices + GPCP

---

### Dashboard 4 — ENSO Prediction & Early Warning
Shifts the project from "explaining the past" to "reading the near future." No machine learning required — built on trend detection and historical pattern matching.
- Current ENSO status: latest available ONI value and classification
- Trend indicator: is the index moving toward El Niño or La Niña over the last 3–6 months?
- Historical analog: which past event does the current trajectory most resemble?
- Risk outlook: which regions would likely be affected if the trend continues, based on historical patterns

**Data used:** ONI only

---

### Dashboard 5 — Climate & Food Security Impact
Connects ENSO to food security and commodity prices.
- ENSO phase timeline as a reference layer at the top
- Food price response around El Niño / La Niña periods
- Regional food security risk score per country (precipitation anomaly + crop price change)
- Lag correlation between ONI and food prices

**Data used:** ONI + FAO Food Price Index + FAO Production Data

---

## 4. Summary Table

| # | Dashboard | Focus | Data Sources |
|---|---|---|---|
| 1 | ENSO Overview | Phenomenon classification | ONI |
| 2 | Global/Regional Impact | Climate | ONI + GPCP |
| 3 | Regional Deep Dive | Detailed climate | ONI + sstoi.indices + GPCP |
| 4 | Prediction & Early Warning | Forecasting | ONI |
| 5 | Climate & Food Security | Food security | ONI + FAO Food Price Index + FAO Production |

**Architectural note:** ONI is the backbone across all five dashboards — it appears as a reference layer in every one, which gives the project strong internal consistency and makes the final presentation feel cohesive rather than like five unrelated charts.

---

## 5. Data Sources

### 5.1 Core ENSO data

| Dataset | Source | Link | Notes |
|---|---|---|---|
| ONI (Oceanic Niño Index) | NOAA CPC | https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/oni/v6/ | Official source — 3-month running mean SST anomaly in the Niño 3.4 region. This is the project's foundation. |
| ONI (alternate copy) | NOAA PSL | https://psl.noaa.gov/data/correlation/oni.data | Same data, plain text format, easy to parse with pandas |
| SST Indices (Niño 1+2, 3, 3.4, 4) | NOAA CPC | https://www.cpc.ncep.noaa.gov/data/indices/sstoi.indices | Raw monthly SST + anomalies for all four Niño regions |
| CPC Climate Indices index page | NOAA CPC | https://www.cpc.ncep.noaa.gov/data/indices/ | Directory of all CPC climate indices in one place |
| PSL ENSO Data Hub | NOAA PSL | https://www.psl.noaa.gov/enso/data.html | Hub page linking to MEI, SOI, and comparison tools — optional, not core |

**Reliability note:** minor value discrepancies can occur between the PSL copy and the CPC original due to update-timing differences. Treat CPC as authoritative; if using PSL, spot-check the latest values against CPC.

### 5.2 Climate data (precipitation, temperature)

| Dataset | Source | Link | Notes |
|---|---|---|---|
| GPCP Monthly Precipitation | NOAA/NCEI | https://www.ncei.noaa.gov/data/global-precipitation-climatology-project-gpcp-monthly/access/ | Global monthly precipitation, 1979–present, NetCDF format, 2.5° resolution. Use v2.3 or later — v2.2 is officially superseded. |
| GPCC Precipitation (not used) | NOAA PSL | https://psl.noaa.gov/data/gridded/data.gpcc.html | Redundant alternative to GPCP — excluded to avoid duplicate effort |
| PSL Gridded Surface Tables | NOAA PSL | https://psl.noaa.gov/data/gridded/tables/surface.html | General surface data tables — content needs confirmation before use |

**Technical notes (confirmed by hands-on testing):**
- Dimensions in the GPCP files are named `latitude`/`longitude`, not `lat`/`lon`.
- Longitude uses a 0–360 system, not -180 to 180 — negative longitudes must be converted (`lon + 360` if negative) before using `.sel()`.
- Reading requires the `xarray` library; use `.sel(..., method='nearest')` to pull the nearest grid point to a target coordinate.
- Single monthly files can be combined into one time series using `xr.open_mfdataset()`.

### 5.3 Food security data

| Dataset | Source | Link | Notes |
|---|---|---|---|
| FAO Food Price Index | FAO | https://www.fao.org/worldfoodsituation/foodpricesindex | Monthly/annual index for 5 commodity groups (cereals, dairy, meat, oils, sugar), from 1990, downloadable as Excel |
| FAOSTAT Production Data | FAO | https://data.fao.org/catalog/dataset/d24a448b-3b62-4c09-8c1d-4a39bb599876 | Crop production by country/year — exact resource content still needs final confirmation |
| FAO Agriculture data collection | FAO | https://www.fao.org/statistics/data-collection/agriculture/ | General landing page for agricultural statistics |

### 5.4 Sources deliberately excluded

| Source | Reason |
|---|---|
| GPCC | Redundant with GPCP |
| MEI / SOI | Optional only — useful for cross-validating ONI, not essential to the core plan |
| PSL Gridded Surface Tables | Content unclear, needs confirmation before adoption |

---

## 6. Proposed Technical Architecture

```
DATA SOURCES (NOAA + FAO)
        ↓
Data Transformation (NetCDF → CSV via xarray)
        ↓
   Data Cleaning (SQL)
        ↓
   SQL Database
        ↓
  Statistical Analysis (Python, querying the database)
  (Correlation, Lag Analysis, Anomaly Detection)
        ↓
   Analytical Dataset / Views (SQL)
        ↓
  Power BI Dashboards
```

**Toolchain used, end to end:**
1. **Python** — pulls and cleans the raw sources (ONI, sstoi.indices, GPCP NetCDF via `xarray`, FAO Food Price Index, FAOSTAT production), and loads the cleaned tables into the SQL database.
2. **SQL** — the data lives in a proper relational database (schema in `enso_schema.sql`), not scattered CSVs. All five dashboards query this database rather than reading files directly, which keeps the data consistent and makes it easy to add new regions or refresh months without re-touching every dashboard.
3. **Python** (again) — runs the statistical analysis on top of the database (correlation, lag analysis, the trend/analog logic for Dashboard 4, and the risk score calculation for Dashboard 5), and writes results back into the database or into analytical views.
4. **Power BI** — connects directly to the SQL database (or to the analytical views/exports) to build and present the final five dashboards.

**Key lessons carried into this architecture:**
1. NetCDF dimension names differ by source — always inspect the dataset (`print(ds)`) before writing extraction code.
2. Longitude convention (0–360 vs. -180–180) must be checked and normalized per source.
3. Stick to one dataset per data type to avoid redundant cleaning work (e.g., GPCP only, not GPCP + GPCC).
4. Start with the simplest working version — a handful of countries and one solid dashboard — before scaling up to more regions or more dashboards.

---

## 7. Team Structure (6 people)

| Task | People | Description |
|---|---|---|
| Data collection + cleaning + ETL | 2 | Pulling ONI, GPCP, and FAO data; converting NetCDF to CSV; handling missing values and format mismatches |
| Statistical analysis | 1 | Correlation, lag analysis, anomaly detection, trend/analog logic for Dashboard 4 |
| Dashboard building | 2 | Building the 5 dashboards in Power BI or Python (Streamlit/Plotly) |
| Documentation + presentation + QA | 1 | README, final report, slide deck, testing dashboard accuracy against source data |

---

## 8. Tools & Libraries

| Tool | Purpose |
|---|---|
| `xarray` | Reading and processing NetCDF climate files |
| `netCDF4` | Low-level NetCDF support (used internally by xarray) |
| `pandas` | Tabular data cleaning, merging, and analysis |
| `scipy.stats` | Correlation coefficients and lag analysis |
| SQL database (PostgreSQL or similar) | Central storage for all cleaned data — schema defined in `enso_schema.sql` |
| `SQLAlchemy` / `psycopg2` | Loading cleaned pandas DataFrames into the SQL database from Python |
| Power BI | Final dashboard building, connected directly to the SQL database |

**Final toolchain: Python (collection + cleaning + analysis) → SQL database (storage) → Power BI (dashboards).**

---

## 9. Open Items / Still To Confirm

- Exact contents of the `data.fao.org` production dataset resource (crop type coverage, country coverage, years).
- Final list of 10–15 regions/countries to use consistently across Dashboards 2, 3, and 5.
- Whether MEI/SOI get added as an optional cross-validation layer on Dashboard 1, time permitting.
