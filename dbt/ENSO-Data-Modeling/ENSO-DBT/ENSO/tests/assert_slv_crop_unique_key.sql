select area_code, item_code, element_code, year_num, count(*) as n
from {{ ref('slv_crop_production') }}
group by area_code, item_code, element_code, year_num
having count(*) > 1