select 'nino_region_sst' as tbl, s.n as silver_rows, 4 * b.n as expected_rows
from (select count(*) as n from {{ ref('slv_nino_region_sst') }}) s
cross join (select count(*) as n from {{ ref('brz_nino_regions') }} where yr is not null and mon between 1 and 12) b
where s.n <> 4 * b.n
union all
select 'food_price_monthly', s.n, 6 * b.n
from (select count(*) as n from {{ ref('slv_food_price_monthly') }}) s
cross join (select count(*) as n from {{ ref('brz_ffpi_monthly') }} where month_date is not null) b
where s.n <> 6 * b.n