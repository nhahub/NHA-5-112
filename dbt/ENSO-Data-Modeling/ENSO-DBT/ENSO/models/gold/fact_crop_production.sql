select area_code, item_code, element_code, year_num, value, flag_code
from {{ ref('slv_crop_production') }}