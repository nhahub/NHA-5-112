select s.date_key, r.region_id, s.sst, s.sst_anomaly
from {{ ref('slv_nino_region_sst') }} s
join {{ ref('dim_nino_region') }} r on r.region_code = s.region_code