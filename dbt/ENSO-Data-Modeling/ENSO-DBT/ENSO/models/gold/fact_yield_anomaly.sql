with p as (
    select
        max(case when param_name = 'analysis_start_year' then param_value end) as start_year,
        max(case when param_name = 'analysis_end_year'   then param_value end) as end_year
    from {{ ref('analysis_parameters') }}
),
y as (
    select
        c.area_code, c.item_code, c.year_num, c.flag_code,
        cast(c.value as float)                  as yield_kg_ha,
        cast(c.year_num - p.start_year as float) as x
    from {{ ref('fact_crop_production') }} c
    join {{ ref('dim_item') }} i on i.item_code = c.item_code and i.is_primary_crop = 1
    join {{ ref('dim_area') }} a on a.area_code = c.area_code and a.is_aggregate = 0
    join {{ ref('slv_series_quality') }} q
      on q.area_code = c.area_code and q.item_code = c.item_code and q.passes_quality = 1
    cross join p
    where c.element_code = 5412
      and c.value is not null
      and c.year_num between p.start_year and p.end_year
),
reg as (
    select
        area_code, item_code,
        cast(count(*) as float)    as n,
        sum(x)                     as sx,
        sum(yield_kg_ha)           as sy,
        sum(x * yield_kg_ha)       as sxy,
        sum(x * x)                 as sxx
    from y
    group by area_code, item_code
),
fit as (
    select
        area_code, item_code,
        (n * sxy - sx * sy) / nullif(n * sxx - sx * sx, 0)  as slope,
        sy / n - ((n * sxy - sx * sy) / nullif(n * sxx - sx * sx, 0)) * (sx / n) as intercept
    from reg
),
ap as (
    select
        area_code, item_code, year_num,
        max(case when element_code = 5312 then value end) as area_ha,
        max(case when element_code = 5510 then value end) as production_t
    from {{ ref('fact_crop_production') }}
    where element_code in (5312, 5510)
    group by area_code, item_code, year_num
),
t as (
    select
        y.area_code, y.item_code, y.year_num, y.flag_code, y.yield_kg_ha,
        f.intercept + f.slope * y.x as trend_kg_ha
    from y
    join fit f on f.area_code = y.area_code and f.item_code = y.item_code
)
select
    t.area_code,
    t.item_code,
    t.year_num,
    cast(t.yield_kg_ha as decimal(18, 4))                                          as yield_kg_ha,
    cast(t.trend_kg_ha as decimal(18, 4))                                          as trend_kg_ha,
    cast(case when t.trend_kg_ha > 0
              then (t.yield_kg_ha - t.trend_kg_ha) / t.trend_kg_ha * 100 end as decimal(18, 4)) as anomaly_pct,
    ap.area_ha,
    ap.production_t,
    t.flag_code
from t
left join ap on ap.area_code = t.area_code and ap.item_code = t.item_code and ap.year_num = t.year_num