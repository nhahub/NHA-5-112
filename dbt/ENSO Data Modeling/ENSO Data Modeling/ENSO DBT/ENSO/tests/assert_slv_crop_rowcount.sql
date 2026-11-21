select s.n as silver_rows, b.n as expected_rows
from (select count(*) as n from {{ ref('slv_crop_production') }}) s
cross join (
    select count(*) as n
    from {{ ref('brz_fao_production') }}
    where area_code is not null and item_code is not null and element_code is not null
      and year is not null and element_code in (5312, 5412, 5510)
) b
where s.n <> b.n