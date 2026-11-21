select area_code, area_name, m49_code, is_aggregate
from {{ ref('slv_area') }}