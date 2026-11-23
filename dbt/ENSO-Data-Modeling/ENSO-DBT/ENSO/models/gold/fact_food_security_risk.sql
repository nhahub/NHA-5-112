with lags as (
    select v.lag_months
    from (values (0), (1), (2), (3), (4), (5), (6)) as v(lag_months)
),
pairs as (
    select
        pa.location_id,
        l.lag_months,
        cast(pa.anomaly_mm_day as float) as y,
        cast(e.anomaly_3m as float)      as x
    from {{ ref('fact_precip_anomaly') }} pa
    join {{ ref('dim_date') }} d on d.date_key = pa.date_key
    cross join lags l
    join {{ ref('dim_date') }} d2 on d2.month_start = dateadd(month, -(l.lag_months + 1), d.month_start)
    join {{ ref('fact_enso_monthly') }} e on e.date_key = d2.date_key
    where e.anomaly_3m is not null
      and pa.anomaly_mm_day is not null
),
sums as (
    select
        location_id, lag_months,
        cast(count(*) as float) as n,
        sum(x) as sx, sum(y) as sy, sum(x * y) as sxy, sum(x * x) as sxx, sum(y * y) as syy
    from pairs
    group by location_id, lag_months
),
corr_by_lag as (
    select
        location_id, lag_months,
        case when (n * sxx - sx * sx) > 0 and (n * syy - sy * sy) > 0
             then (n * sxy - sx * sy) / sqrt((n * sxx - sx * sx) * (n * syy - sy * sy)) end as r_value
    from sums
),
best as (
    select
        location_id, lag_months, r_value,
        row_number() over (partition by location_id order by abs(r_value) desc) as rk
    from corr_by_lag
    where r_value is not null
),
rain as (
    select
        b.location_id,
        l.area_code,
        abs(b.r_value)  as rain_sensitivity,
        b.lag_months    as best_lag
    from best b
    join {{ ref('dim_location') }} l on l.location_id = b.location_id
    where b.rk = 1 and l.area_code is not null
),
yld as (
    select
        s.area_code,
        sum(s.std_anom_pct * s.avg_production_t) / nullif(sum(s.avg_production_t), 0)   as yield_volatility,
        sum(s.official_share * s.avg_production_t) / nullif(sum(s.avg_production_t), 0) as official_share
    from {{ ref('fact_yield_sensitivity') }} s
    where s.std_anom_pct is not null and s.avg_production_t is not null
    group by s.area_code
),
yld_pct as (
    select area_code, yield_volatility, official_share,
           percent_rank() over (order by yield_volatility) as yield_pctl
    from yld
),
rain_pct as (
    select location_id, area_code, rain_sensitivity, best_lag,
           percent_rank() over (order by rain_sensitivity) as rain_pctl
    from rain
)
select
    y.area_code,
    r.location_id,
    r.rain_sensitivity,
    r.best_lag,
    y.yield_volatility,
    100.0 * case when r.rain_pctl is not null then (r.rain_pctl + y.yield_pctl) / 2.0 else y.yield_pctl end as risk_score,
    case when r.rain_pctl is not null then 'rain + yield' else 'yield only' end                         as risk_basis,
    y.official_share
from yld_pct y
left join rain_pct r on r.area_code = y.area_code