with p as (
    select
        max(case when param_name = 'analysis_start_year' then param_value end) as start_year,
        max(case when param_name = 'analysis_end_year'   then param_value end) as end_year
    from {{ ref('analysis_parameters') }}
),
ya as (
    select
        a.area_code, a.item_code, a.year_num,
        cast(a.anomaly_pct as float) as anomaly_pct,
        a.production_t,
        a.flag_code,
        ph.phase_code                as year_phase_code,
        cast(y.oni_ond as float)     as oni_ond
    from {{ ref('fact_yield_anomaly') }} a
    left join {{ ref('fact_enso_year') }} y  on y.year_num = a.year_num
    left join {{ ref('dim_enso_phase') }} ph on ph.phase_id = y.year_phase_id
    where a.anomaly_pct is not null
),
agg as (
    select
        area_code, item_code,
        sum(case when year_phase_code = 'elnino'  then 1 else 0 end)   as n_el_nino,
        sum(case when year_phase_code = 'lanina'  then 1 else 0 end)   as n_la_nina,
        sum(case when year_phase_code = 'neutral' then 1 else 0 end)   as n_neutral,
        avg(case when year_phase_code = 'elnino'  then anomaly_pct end) as mean_anom_el_nino_pct,
        avg(case when year_phase_code = 'lanina'  then anomaly_pct end) as mean_anom_la_nina_pct,
        avg(case when year_phase_code = 'neutral' then anomaly_pct end) as mean_anom_neutral_pct,
        stdev(anomaly_pct)                                             as std_anom_pct,
        avg(production_t)                                              as avg_production_t,
        avg(case when flag_code = 'A' then 1.0 else 0.0 end)           as official_share,
        cast(sum(case when oni_ond is not null then 1 else 0 end) as float)                  as n_c,
        sum(case when oni_ond is not null then oni_ond end)                                  as sx,
        sum(case when oni_ond is not null then anomaly_pct end)                              as sy,
        sum(case when oni_ond is not null then oni_ond * anomaly_pct end)                    as sxy,
        sum(case when oni_ond is not null then oni_ond * oni_ond end)                        as sxx,
        sum(case when oni_ond is not null then anomaly_pct * anomaly_pct end)                as syy
    from ya
    group by area_code, item_code
),
world as (
    select c.item_code, avg(c.value) as world_avg_production_t
    from {{ ref('fact_crop_production') }} c
    join {{ ref('dim_area') }} a on a.area_code = c.area_code and a.area_name = 'World'
    cross join p
    where c.element_code = 5510
      and c.value is not null
      and c.year_num between p.start_year and p.end_year
    group by c.item_code
)
select
    g.area_code,
    g.item_code,
    g.n_el_nino,
    g.n_la_nina,
    g.n_neutral,
    g.mean_anom_el_nino_pct,
    g.mean_anom_la_nina_pct,
    g.mean_anom_neutral_pct,
    g.std_anom_pct,
    case when (g.n_c * g.sxx - g.sx * g.sx) > 0 and (g.n_c * g.syy - g.sy * g.sy) > 0
         then (g.n_c * g.sxy - g.sx * g.sy)
              / sqrt((g.n_c * g.sxx - g.sx * g.sx) * (g.n_c * g.syy - g.sy * g.sy)) end  as corr_oni_ond,
    g.avg_production_t,
    g.avg_production_t / nullif(w.world_avg_production_t, 0)                            as world_share,
    g.official_share
from agg g
left join world w on w.item_code = g.item_code