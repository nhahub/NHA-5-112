/* ============================================================
   02 - Create staging layer
   ============================================================ */
USE ENSO_DB;
GO
-- ---------- FAO lookups ----------
CREATE TABLE staging.fao_areas (
    area_code    NVARCHAR(400),
    m49_code     NVARCHAR(400),
    area_name    NVARCHAR(400),
    _loaded_at   NVARCHAR(400),
    _source_file NVARCHAR(400)
);

CREATE TABLE staging.fao_items (
    item_code    NVARCHAR(400),
    cpc_code     NVARCHAR(400),
    item_name    NVARCHAR(400),
    _loaded_at   NVARCHAR(400),
    _source_file NVARCHAR(400)
);

CREATE TABLE staging.fao_elements (
    element_code NVARCHAR(400),
    element_name NVARCHAR(400),
    _loaded_at   NVARCHAR(400),
    _source_file NVARCHAR(400)
);

CREATE TABLE staging.fao_flags (
    [flag]        NVARCHAR(400),
    [description] NVARCHAR(400),
    _loaded_at    NVARCHAR(400),
    _source_file  NVARCHAR(400)
);

-- ---------- FAO production ----------
CREATE TABLE staging.fao_production (
    area_code     NVARCHAR(400),
    area_code_m49 NVARCHAR(400),
    area_name     NVARCHAR(400),
    item_code     NVARCHAR(400),
    item_code_cpc NVARCHAR(400),
    item_name     NVARCHAR(400),
    element_code  NVARCHAR(400),
    element_name  NVARCHAR(400),
    year_code     NVARCHAR(400),
    [year]        NVARCHAR(400),
    unit          NVARCHAR(400),
    [value]       NVARCHAR(400),
    flag          NVARCHAR(400),
    note          NVARCHAR(400),
    _loaded_at    NVARCHAR(400),
    _source_file  NVARCHAR(400)
);

-- ---------- ENSO / climate / prices ----------
CREATE TABLE staging.enso_events (
    month_date           NVARCHAR(400),
    total_sst            NVARCHAR(400),
    clim_adjust          NVARCHAR(400),
    anom                 NVARCHAR(400),
    anom_trimester       NVARCHAR(400),
    anom_trimester_round NVARCHAR(400),
    phase_trimester      NVARCHAR(400),
    phase_event          NVARCHAR(400),
    _loaded_at           NVARCHAR(400),
    _source_file         NVARCHAR(400)
);

CREATE TABLE staging.nino_regions (
    yr           NVARCHAR(400),
    mon          NVARCHAR(400),
    nino12       NVARCHAR(400),
    nino12_anom  NVARCHAR(400),
    nino3        NVARCHAR(400),
    nino3_anom   NVARCHAR(400),
    nino4        NVARCHAR(400),
    nino4_anom   NVARCHAR(400),
    nino34       NVARCHAR(400),
    nino34_anom  NVARCHAR(400),
    _loaded_at   NVARCHAR(400),
    _source_file NVARCHAR(400)
);

CREATE TABLE staging.gpcp_precipitation (
    month_date               NVARCHAR(400),
    country                  NVARCHAR(400),
    original_lat             NVARCHAR(400),
    original_lon             NVARCHAR(400),
    grid_lat                 NVARCHAR(400),
    grid_lon                 NVARCHAR(400),
    precipitation_mm_per_day NVARCHAR(400),
    _loaded_at               NVARCHAR(400),
    _source_file             NVARCHAR(400)
);

CREATE TABLE staging.ffpi_monthly (
    month_date   NVARCHAR(400),
    ffpi         NVARCHAR(400),
    meat         NVARCHAR(400),
    dairy        NVARCHAR(400),
    cereals      NVARCHAR(400),
    oils         NVARCHAR(400),
    sugar        NVARCHAR(400),
    ffpi_real    NVARCHAR(400),
    meat_real    NVARCHAR(400),
    dairy_real   NVARCHAR(400),
    cereals_real NVARCHAR(400),
    oils_real    NVARCHAR(400),
    sugar_real   NVARCHAR(400),
    _loaded_at   NVARCHAR(400),
    _source_file NVARCHAR(400)
);
GO

-- Check: should list 9 tables
SELECT s.name AS [schema], t.name AS [table]
FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE s.name = 'staging'
ORDER BY t.name;
GO