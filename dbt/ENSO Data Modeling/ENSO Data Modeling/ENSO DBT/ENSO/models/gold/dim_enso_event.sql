with m as (
    select
        date_key, month_start, phase_event_code, anomaly_3m,
        row_number() over (order by month_start) as rn
    from {{ ref('slv_enso_monthly') }}
),
runs as (
    select
        date_key, phase_event_code, anomaly_3m,
        rn - row_number() over (partition by phase_event_code order by month_start) as grp
    from m
    where phase_event_code in ('elnino', 'lanina')
),
ev as (
    select
        phase_event_code,
        min(date_key)  as start_date_key,
        max(date_key)  as end_date_key,
        count(*)       as months,
        case when phase_event_code = 'elnino' then max(anomaly_3m) else min(anomaly_3m) end as peak_anom_3m
    from runs
    group by phase_event_code, grp
)
select
    row_number() over (order by e.start_date_key)  as event_id,
    ph.phase_id,
    e.start_date_key,
    e.end_date_key,
    e.months,
    e.peak_anom_3m,
    it.intensity_id
from ev e
join {{ ref('dim_enso_phase') }} ph on ph.phase_code = e.phase_event_code
join {{ ref('dim_intensity') }} it
  on abs(e.peak_anom_3m) >= it.min_abs_anom
 and (abs(e.peak_anom_3m) < it.max_abs_anom or it.max_abs_anom is null)