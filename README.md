# ENSO — Global Climate & Food Security Analytics

Analysis of the El Niño/La Niña (ENSO) phenomenon's impact on global climate and food security, using official data from NOAA and FAO.

## Name and Concept

**ENSO = El Niño–Southern Oscillation**

A natural climate phenomenon associated with changes in:
- Sea surface temperatures in the tropical Pacific Ocean
- Atmospheric pressure and winds
- Rainfall patterns and temperatures worldwide

### The Three ENSO Phases

| Phase | Description |
|---|---|
| El Niño | Unusual warming of sea surface temperatures |
| La Niña | Unusual cooling of sea surface temperatures |
| Neutral | Neither El Niño nor La Niña conditions present |

## Core Research Question

> How does ENSO influence global temperature, precipitation, and food security, and which regions are most affected?

## Value

- **Real-world relevance**: ENSO affects agriculture, fisheries, energy, and global food commodity prices
- **Real, free data**: Sourced from official organizations (NOAA, FAO)
- **Diverse skills**: Time series analysis, data cleaning, statistical analysis, interactive dashboards
- **Strong storytelling**: Connects a climate phenomenon to a real, tangible economic impact

---

## Data Sources

### 1. Core ENSO Data

| Dataset | Source | Link | Usage |
|---|---|---|---|
| ONI (Oceanic Niño Index) | NOAA CPC | cpc.ncep.noaa.gov/data/indices/oni/v6 | Official classification of El Niño/La Niña/Neutral — the project's foundation |
| ONI (alternate copy) | NOAA PSL | psl.noaa.gov/data/correlation/oni.data | Same data, simplified text format |
| SST Indices (Niño 1+2, 3, 3.4, 4) | NOAA CPC | cpc.ncep.noaa.gov/data/indices/sstoi.indices | Finer detail for each Niño region individually |

**Reliability note:** Minor discrepancies can occur between the PSL copy and the CPC version due to differing update timing. Treat the CPC version as the authoritative reference, and verify the latest values match if using the PSL copy.

### 2. Climate Data (Precipitation and Temperature)

| Dataset | Source | Link | Notes |
|---|---|---|---|
| GPCP Monthly | NOAA/NCEI | ncei.noaa.gov/data/global-precipitation-climatology-project-gpcp-monthly | Global precipitation data, 1979–present, NetCDF (.nc) format, 2.5° resolution |

**Warning:** Use the latest available version (v2.3 or higher). Older versions (v2.2) are officially "superseded" and not recommended.

**Technical challenge:** Files are in NetCDF format and require the `xarray` library. In this dataset the dimensions are named `latitude`/`longitude` (not `lat`/`lon`), and longitude uses a 0–360 system (not -180 to 180), requiring conversion before use.

### 3. Food Security Data

| Dataset | Source | Link | Usage |
|---|---|---|---|
| FAO Food Price Index | FAO | fao.org/worldfoodsituation/foodpricesindex | Monthly/annual prices for 5 food commodity groups (cereals, dairy, meat, oils, sugar) from 1990 |
| FAOSTAT Production Data | FAO | data.fao.org (resource content still needs final confirmation) | Crop production data by country and year |

### Sources Excluded

| Source | Reason |
|---|---|
| GPCC | Redundant alternative to GPCP; no need to use both |
| MEI / SOI (psl.noaa.gov/enso/data.html) | Optional addition only, not essential for the current project scope |
| psl.noaa.gov/data/gridded/tables/surface.html | Needs further clarification before adoption |

---

## Final Dashboards (5 total)

### Dashboard 1 — ENSO Overview
A general view of the phenomenon over time.
- ONI Index timeline (1950–present)
- KPI cards: number of events, average duration, strongest historical event
- Yearly classification chart
- Intensity distribution (weak/moderate/strong)

**Data used:** ONI

---

### Dashboard 2 — Global/Regional Climate Impact
ENSO's effect on temperature and rainfall in selected regions (10–15 countries).
- Interactive map
- Temperature anomaly comparison across El Niño/La Niña/Neutral
- Precipitation anomaly for the same regions

**Data used:** ONI + GPCP

---

### Dashboard 3 — Regional Deep Dive
Detailed analysis for a user-selected region.
- Comparative time series (actual vs. baseline)
- Correlation coefficient between ONI and the climate variable
- Lag analysis (impact delay of 1/3/6 months)

**Data used:** ONI + sstoi.indices + GPCP

---

### Dashboard 4 — ENSO Prediction & Early Warning
Shifting from analyzing the past to reading the future.
- Current ENSO status: latest available classification
- Trend indicator: direction over the last 3–6 months
- Historical analog: the closest matching historical event
- Risk outlook: regions likely to be affected based on the historical pattern

**Data used:** ONI only (simple statistical analysis: trend + pattern matching, no machine learning)

---

### Dashboard 5 — Climate & Food Security Impact
Linking ENSO to food security and crop prices.
- ENSO phase timeline as a reference layer
- Food price response around El Niño/La Niña periods
- Regional food security risk score per country
- Lag correlation between ONI and food prices

**Data used:** ONI + FAO Food Price Index + FAO Production Data

---

## Summary Table

| # | Dashboard | Focus | Data Sources |
|---|---|---|---|
| 1 | ENSO Overview | Phenomenon classification | ONI |
| 2 | Global/Regional Impact | Climate | ONI + GPCP |
| 3 | Regional Deep Dive | Detailed climate | ONI + sstoi.indices + GPCP |
| 4 | Prediction & Early Warning | Forecasting | ONI |
| 5 | Climate & Food Security | Food security | ONI + FAO Food Price Index + FAO Production |

**Architectural note:** ONI is the backbone of all five dashboards — present as a reference layer in each one, giving the project clear logical cohesion.

---

## Proposed Architecture

```
DATA SOURCES (NOAA + FAO)
        ↓
   Data Cleaning
        ↓
Data Transformation (NetCDF → CSV via xarray)
        ↓
  Statistical Analysis
  (Correlation, Lag Analysis, Anomaly Detection)
        ↓
   Analytical Dataset
        ↓
  Power BI / Python Dashboards
```

---

## Key Technical Notes (from hands-on testing)

1. **NetCDF dimension names vary by source** — always confirm the actual names (`lat` vs `latitude`) before writing code.
2. **Longitude system** may be 0–360 or -180 to 180 — conversion is required before selecting coordinates.
3. **Use one source per data type** to avoid redundancy and unnecessary complexity (e.g., GPCP instead of GPCC).
4. **Start with the simplest workable version** before scaling up (5 countries instead of the whole world, one strong dashboard instead of several shallow ones).

---

## Team (6 people) — Proposed Split

| Task | People |
|---|---|
| Data collection + cleaning + ETL | 2 |
| Statistical analysis (correlation, lag analysis) | 1 |
| Dashboard building | 2 |
| Documentation + presentation + QA | 1 |
