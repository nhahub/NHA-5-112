select a.location_id, d.month_num, avg(a.anomaly_mm_day) as mean_anomaly
from {{ ref('fact_precip_anomaly') }} a
join {{ ref('dim_date') }} d on d.date_key = a.date_key
group by a.location_id, d.month_num
having abs(avg(a.anomaly_mm_day)) > 0.000001