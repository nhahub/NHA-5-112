select
    m.date_key,
    m.sst_total,
    m.sst_climatology,
    m.anomaly,
    m.anomaly_3m,
    m.anomaly_3m_rounded,
    p3.phase_id        as phase_3m_id,
    pe.phase_id        as phase_event_id,
    it.intensity_id,
    ev.event_id
from {{ ref('slv_enso_monthly') }} m
join {{ ref('dim_enso_phase') }} p3 on p3.phase_code = m.phase_3m_code
join {{ ref('dim_enso_phase') }} pe on pe.phase_code = m.phase_event_code
left join {{ ref('dim_intensity') }} it
       on abs(m.anomaly_3m) >= it.min_abs_anom
      and (abs(m.anomaly_3m) < it.max_abs_anom or it.max_abs_anom is null)
left join {{ ref('dim_enso_event') }} ev
       on m.date_key between ev.start_date_key and ev.end_date_key