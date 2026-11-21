select 'fao_production' as tbl, s.n as staging_rows, b.n as bronze_rows
from (select count(*) as n from {{ source('staging', 'fao_production') }}) s
cross join (select count(*) as n from {{ ref('brz_fao_production') }}) b where s.n <> b.n
union all
select 'fao_areas', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_areas') }}) s
cross join (select count(*) as n from {{ ref('brz_fao_areas') }}) b where s.n <> b.n
union all
select 'fao_items', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_items') }} where try_cast(nullif(ltrim(rtrim(item_code)), '') as int) is not null) s
cross join (select count(*) as n from {{ ref('brz_fao_items') }}) b where s.n <> b.n
union all
select 'fao_elements', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_elements') }}) s
cross join (select count(*) as n from {{ ref('brz_fao_elements') }}) b where s.n <> b.n
union all
select 'fao_flags', s.n, b.n
from (select count(*) as n from {{ source('staging', 'fao_flags') }}) s
cross join (select count(*) as n from {{ ref('brz_fao_flags') }}) b where s.n <> b.n
union all
select 'enso_events', s.n, b.n
from (select count(*) as n from {{ source('staging', 'enso_events') }}) s
cross join (select count(*) as n from {{ ref('brz_enso_events') }}) b where s.n <> b.n
union all
select 'nino_regions', s.n, b.n
from (select count(*) as n from {{ source('staging', 'nino_regions') }}) s
cross join (select count(*) as n from {{ ref('brz_nino_regions') }}) b where s.n <> b.n
union all
select 'gpcp_precipitation', s.n, b.n
from (select count(*) as n from {{ source('staging', 'gpcp_precipitation') }}) s
cross join (select count(*) as n from {{ ref('brz_gpcp_precipitation') }}) b where s.n <> b.n
union all
select 'ffpi_monthly', s.n, b.n
from (select count(*) as n from {{ source('staging', 'ffpi_monthly') }}) s
cross join (select count(*) as n from {{ ref('brz_ffpi_monthly') }}) b where s.n <> b.n