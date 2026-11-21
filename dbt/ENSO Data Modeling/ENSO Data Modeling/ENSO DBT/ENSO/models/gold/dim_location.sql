with pts as (
    select
        location_id,
        max(original_lat) as original_lat,
        max(original_lon) as original_lon,
        max(grid_lat)     as grid_lat,
        max(grid_lon)     as grid_lon
    from {{ ref('slv_precipitation') }}
    group by location_id
)
select
    l.location_id,
    l.location_name,
    p.original_lat,
    p.original_lon,
    p.grid_lat,
    p.grid_lon,
    l.area_code
from {{ ref('gpcp_locations') }} l
left join pts p on p.location_id = l.location_id