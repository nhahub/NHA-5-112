with base as (
    select
        datefromparts(yr, mon, 1) as month_start,
        nino12, nino12_anom, nino3, nino3_anom, nino4, nino4_anom, nino34, nino34_anom
    from {{ ref('brz_nino_regions') }}
    where yr is not null and mon between 1 and 12
)
select
    b.month_start,
    year(b.month_start) * 10000 + month(b.month_start) * 100 + 1  as date_key,
    v.region_code,
    v.sst,
    v.sst_anomaly
from base b
cross apply (values
    ('NINO1+2', b.nino12, b.nino12_anom),
    ('NINO3',   b.nino3,  b.nino3_anom),
    ('NINO4',   b.nino4,  b.nino4_anom),
    ('NINO3.4', b.nino34, b.nino34_anom)
) as v(region_code, sst, sst_anomaly)