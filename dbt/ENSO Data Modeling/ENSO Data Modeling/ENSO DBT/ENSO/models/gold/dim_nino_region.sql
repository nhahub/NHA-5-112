select region_id, region_code, region_name, lat_min, lat_max, lon_min_east, lon_max_east
from {{ ref('nino_region_definitions') }}