with x as (
    select
        f.date_key,
        f.location_id,
        f.precip_mm_per_day,
        avg(f.precip_mm_per_day)   over (partition by f.location_id, d.month_num) as normal_mm_day,
        stdev(f.precip_mm_per_day) over (partition by f.location_id, d.month_num) as sd_mm_day
    from {{ ref('fact_precipitation') }} f
    join {{ ref('dim_date') }} d on d.date_key = f.date_key
)
select
    date_key,
    location_id,
    normal_mm_day,
    precip_mm_per_day - normal_mm_day                          as anomaly_mm_day,
    (precip_mm_per_day - normal_mm_day) / nullif(sd_mm_day, 0) as anomaly_z
from x