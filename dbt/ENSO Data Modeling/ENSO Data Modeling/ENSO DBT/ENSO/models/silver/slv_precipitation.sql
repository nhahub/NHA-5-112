select
    datefromparts(year(p.month_date), month(p.month_date), 1)                as month_start,
    year(p.month_date) * 10000 + month(p.month_date) * 100 + 1               as date_key,
    l.location_id,
    p.gpcp_region                                                            as location_name,
    l.area_code,
    p.original_lat, p.original_lon, p.grid_lat, p.grid_lon,
    p.precipitation_mm_per_day
from {{ ref('brz_gpcp_precipitation') }} p
left join {{ ref('gpcp_locations') }} l on l.location_name = p.gpcp_region
where p.month_date is not null