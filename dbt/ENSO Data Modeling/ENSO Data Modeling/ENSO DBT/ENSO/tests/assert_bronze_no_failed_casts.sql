select 'fao_production.value' as column_checked, s.n as text_values, b.n as typed_values
from (select count(*) as n from {{ source('staging', 'fao_production') }} where nullif(ltrim(rtrim([value])), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_fao_production') }} where [value] is not null) b where s.n <> b.n
union all
select 'fao_production.year', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_production') }} where nullif(ltrim(rtrim([year])), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_fao_production') }} where [year] is not null) b where s.n <> b.n
union all
select 'fao_production.area_code', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_production') }} where nullif(ltrim(rtrim(area_code)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_fao_production') }} where area_code is not null) b where s.n <> b.n
union all
select 'fao_production.item_code', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_production') }} where nullif(ltrim(rtrim(item_code)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_fao_production') }} where item_code is not null) b where s.n <> b.n
union all
select 'fao_production.element_code', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_production') }} where nullif(ltrim(rtrim(element_code)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_fao_production') }} where element_code is not null) b where s.n <> b.n
union all
select 'fao_areas.area_code', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_areas') }} where nullif(ltrim(rtrim(area_code)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_fao_areas') }} where area_code is not null) b where s.n <> b.n
union all
select 'enso_events.month_date', s.n, b.n
from (select count(*) as n from {{ source('staging', 'enso_events') }} where nullif(ltrim(rtrim(month_date)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_enso_events') }} where month_date is not null) b where s.n <> b.n
union all
select 'enso_events.anom', s.n, b.n
from (select count(*) as n from {{ source('staging', 'enso_events') }} where nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(anom, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') is not null) s
cross join (select count(*) as n from {{ ref('brz_enso_events') }} where anom is not null) b where s.n <> b.n
union all
select 'enso_events.anom_trimester', s.n, b.n
from (select count(*) as n from {{ source('staging', 'enso_events') }} where try_cast(anom_trimester as float) is not null) s
cross join (select count(*) as n from {{ ref('brz_enso_events') }} where anom_trimester is not null) b where s.n <> b.n
union all
select 'nino_regions.nino34_anom', s.n, b.n
from (select count(*) as n from {{ source('staging', 'nino_regions') }} where nullif(ltrim(rtrim(nino34_anom)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_nino_regions') }} where nino34_anom is not null) b where s.n <> b.n
union all
select 'gpcp.month_date', s.n, b.n
from (select count(*) as n from {{ source('staging', 'gpcp_precipitation') }} where nullif(ltrim(rtrim(month_date)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_gpcp_precipitation') }} where month_date is not null) b where s.n <> b.n
union all
select 'gpcp.precipitation', s.n, b.n
from (select count(*) as n from {{ source('staging', 'gpcp_precipitation') }} where nullif(ltrim(rtrim(precipitation_mm_per_day)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_gpcp_precipitation') }} where precipitation_mm_per_day is not null) b where s.n <> b.n
union all
select 'ffpi.month_date', s.n, b.n
from (select count(*) as n from {{ source('staging', 'ffpi_monthly') }} where nullif(ltrim(rtrim(month_date)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_ffpi_monthly') }} where month_date is not null) b where s.n <> b.n
union all
select 'ffpi.ffpi', s.n, b.n
from (select count(*) as n from {{ source('staging', 'ffpi_monthly') }} where nullif(ltrim(rtrim(ffpi)), '') is not null) s
cross join (select count(*) as n from {{ ref('brz_ffpi_monthly') }} where ffpi is not null) b where s.n <> b.n