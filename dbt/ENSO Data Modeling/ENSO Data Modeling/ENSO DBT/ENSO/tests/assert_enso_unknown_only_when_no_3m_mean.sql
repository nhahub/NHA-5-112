select month_start, phase_event_code, phase_3m_code, anomaly_3m
from {{ ref('slv_enso_monthly') }}
where anomaly_3m is not null
  and (phase_event_code = 'unknown' or phase_3m_code = 'unknown')