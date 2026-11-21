select
    month_start,
    date_key,
    lag(anomaly_3m, 1)     over (order by month_start)  as oni_centered,
    lag(phase_3m_code, 1)  over (order by month_start)  as phase_centered_code
from {{ ref('slv_enso_monthly') }}