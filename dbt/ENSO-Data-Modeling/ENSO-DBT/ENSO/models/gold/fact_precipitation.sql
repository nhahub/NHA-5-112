select
    date_key,
    location_id,
    precipitation_mm_per_day as precip_mm_per_day
from {{ ref('slv_precipitation') }}