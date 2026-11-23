select
    area_code,
    item_code,
    element_code,
    year                                                       as year_num,
    case when upper(flag) = 'M' then null else value end       as value,
    upper(flag)                                                as flag_code
from {{ ref('brz_fao_production') }}
where area_code is not null
  and item_code is not null
  and element_code is not null
  and year is not null
  and element_code in (5312, 5412, 5510)