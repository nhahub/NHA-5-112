{# ------------------------------- macros --------------------------------- #}

{# Pearson r from sums. x and y must be float columns without NULLs. #}
{% macro pearson(x, y) -%}
case when count(*) > 2
      and (count(*) * sum({{ x }} * {{ x }}) - sum({{ x }}) * sum({{ x }})) > 0
      and (count(*) * sum({{ y }} * {{ y }}) - sum({{ y }}) * sum({{ y }})) > 0
     then (count(*) * sum({{ x }} * {{ y }}) - sum({{ x }}) * sum({{ y }}))
          / sqrt((count(*) * sum({{ x }} * {{ x }}) - sum({{ x }}) * sum({{ x }}))
               * (count(*) * sum({{ y }} * {{ y }}) - sum({{ y }}) * sum({{ y }})))
end
{%- endmacro %}

{# Seed parameters as one row (alias p). #}
{% macro params_cte() -%}
p as (
    select
        max(case when param_name = 'analysis_start_year'     then param_value end) as start_year,
        max(case when param_name = 'analysis_end_year'       then param_value end) as end_year,
        max(case when param_name = 'min_years_per_group'     then param_value end) as min_years,
        max(case when param_name = 'sensitive_threshold_pct' then param_value end) as sens_pct,
        max(case when param_name = 'max_missing_share'       then param_value end) as max_missing_share,
        max(case when param_name = 'max_zero_share'          then param_value end) as max_zero_share,
        max(case when param_name = 'max_gap_years'           then param_value end) as max_gap_years
    from {{ ref('analysis_parameters') }}
)
{%- endmacro %}

{# lags 0..max_lag as a one-column table. #}
{% macro lags_cte(max_lag) -%}
lags as (
    select v.lag_months
    from (values {% for i in range(0, max_lag + 1) %}({{ i }}){{ "," if not loop.last }}{% endfor %}) as v(lag_months)
)
{%- endmacro %}

{# rain anomaly (t) against centred ONI (t - lag); needs the `lags` CTE. #}
{% macro rain_oni_pairs() -%}
rain_pairs as (
    select pa.location_id, l.lag_months,
           cast(pa.anomaly_mm_day as float) as y,
           cast(o.oni_centered as float)    as x
    from {{ ref('fact_precip_anomaly') }} pa
    join {{ ref('dim_date') }} d on d.date_key = pa.date_key
    cross join lags l
    join {{ ref('slv_oni_centered') }} o
      on o.month_start = dateadd(month, -l.lag_months, d.month_start)
    where pa.anomaly_mm_day is not null
      and o.oni_centered is not null
)
{%- endmacro %}

{# price YoY (t) against centred ONI (t - lag); needs the `lags` CTE. #}
{% macro price_oni_pairs(name, yoy_col) -%}
{{ name }} as (
    select fy.food_index_id, l.lag_months,
           cast(fy.{{ yoy_col }} as float) as y,
           cast(o.oni_centered as float)   as x
    from {{ ref('fact_food_price_yoy') }} fy
    join {{ ref('dim_date') }} d on d.date_key = fy.date_key
    cross join lags l
    join {{ ref('slv_oni_centered') }} o
      on o.month_start = dateadd(month, -l.lag_months, d.month_start)
    where fy.{{ yoy_col }} is not null
      and o.oni_centered is not null
)
{%- endmacro %}

{# From a pairs CTE (key columns, lag_months, x, y): r per key and lag, plus the best lag per key. #}
{% macro corr_best(tag, source, key) -%}
corr_{{ tag }} as (
    select {{ key }}, lag_months, count(*) as n_months, {{ pearson('x', 'y') }} as r_value
    from {{ source }}
    group by {{ key }}, lag_months
),
best_{{ tag }} as (
    select {{ key }}, lag_months, n_months, r_value,
           row_number() over (partition by {{ key }} order by abs(r_value) desc) as rk
    from corr_{{ tag }}
    where r_value is not null
)
{%- endmacro %}

{# Niño 3.4 monthly anomaly by year / month (Niño file, 1982 onward). #}
{% macro n34_cte() -%}
n34 as (
    select d.year_num, d.month_num, d.month_name, cast(s.sst_anomaly as float) as anom
    from {{ ref('fact_nino_region_sst') }} s
    join {{ ref('dim_nino_region') }} r on r.region_id = s.region_id and r.region_code = 'NINO3.4'
    join {{ ref('dim_date') }} d on d.date_key = s.date_key
)
{%- endmacro %}

{# Analog years from the EVENTS file (monthly anomaly, 1950 onward). #}
{% macro analogs_events(cur_year, n_months) -%}
cur_path as (
    select d.month_num, cast(f.anomaly as float) as a
    from {{ ref('fact_enso_monthly') }} f
    join {{ ref('dim_date') }} d on d.date_key = f.date_key
    where d.year_num = {{ cur_year }} and d.month_num <= {{ n_months }} and f.anomaly is not null
),
hist_path as (
    select d.year_num, d.month_num, cast(f.anomaly as float) as b
    from {{ ref('fact_enso_monthly') }} f
    join {{ ref('dim_date') }} d on d.date_key = f.date_key
    where d.year_num < {{ cur_year }} and d.month_num <= {{ n_months }} and f.anomaly is not null
),
analogs as (
    select h.year_num, sqrt(avg(power(c.a - h.b, 2))) as rmse, count(*) as n_months
    from cur_path c
    join hist_path h on h.month_num = c.month_num
    group by h.year_num
    having count(*) = (select count(*) from cur_path)
)
{%- endmacro %}

{# Analog years from the NIÑO file (Niño 3.4 anomaly, 1982 onward). Never mix with the events file. #}
{% macro analogs_nino(cur_year, n_months, max_year) -%}
{{ n34_cte() }},
analogs as (
    select h.year_num, sqrt(avg(power(c.anom - h.anom, 2))) as rmse, count(*) as n_months
    from n34 c
    join n34 h on h.month_num = c.month_num and h.year_num < c.year_num
    where c.year_num = {{ cur_year }}
      and c.month_num <= {{ n_months }}
      and h.month_num <= {{ n_months }}
      and h.year_num <= {{ max_year }}
    group by h.year_num
    having count(*) = (select count(*) from n34 where year_num = {{ cur_year }} and month_num <= {{ n_months }})
)
{%- endmacro %}

{# Yield anomaly (year t) against ONI of the same year and of the previous year. #}
{% macro yield_lag_ctes(min_years) -%}
yield_pairs as (
    select ya.area_code, ya.item_code, ya.year_num,
           cast(ya.anomaly_pct as float) as yld,
           cast(e0.oni_ond as float)     as oni_same,
           cast(e1.oni_ond as float)     as oni_prev
    from {{ ref('fact_yield_anomaly') }} ya
    join {{ ref('fact_enso_year') }} e0 on e0.year_num = ya.year_num
    left join {{ ref('fact_enso_year') }} e1 on e1.year_num = ya.year_num - 1
    where ya.anomaly_pct is not null
),
r_same as (
    select area_code, item_code, count(*) as n_years, {{ pearson('oni_same', 'yld') }} as r_same_year
    from yield_pairs
    where oni_same is not null
    group by area_code, item_code
),
r_next as (
    select area_code, item_code, count(*) as n_years_next, {{ pearson('oni_prev', 'yld') }} as r_next_year
    from yield_pairs
    where oni_prev is not null
    group by area_code, item_code
),
pair_lag as (
    select s.area_code, s.item_code, s.n_years, s.r_same_year, n.r_next_year,
           case when abs(n.r_next_year) > abs(s.r_same_year)
                then 'next year (ONI of year t-1 -> yield of year t)'
                else 'same year (ONI of year t -> yield of year t)' end as stronger_link
    from r_same s
    join r_next n on n.area_code = s.area_code and n.item_code = s.item_code
    where s.n_years >= {{ min_years }}
      and s.r_same_year is not null and n.r_next_year is not null
)
{%- endmacro %}

{# El Nino events since 1990 and the biggest price rise within N months of the event start. #}
{% macro event_rise_ctes(window_months) -%}
ev as (
    select e.event_id, e.start_date_key, e.months, e.peak_anom_3m,
           it.label as intensity, it.intensity_id, ds.month_start as start_month
    from {{ ref('dim_enso_event') }} e
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_id and ph.phase_code = 'elnino'
    join {{ ref('dim_intensity') }} it on it.intensity_id = e.intensity_id
    join {{ ref('dim_date') }} ds on ds.date_key = e.start_date_key
    where e.start_date_key >= 19900101
),
price_path as (
    select ev.event_id, p0.food_index_id,
           datediff(month, ev.start_month, dw.month_start) as months_after_start,
           (pw.real_index / nullif(p0.real_index, 0) - 1) * 100 as rise_pct
    from ev
    join {{ ref('fact_food_price_monthly') }} p0 on p0.date_key = ev.start_date_key
    join {{ ref('dim_date') }} dw
      on dw.month_start between ev.start_month and dateadd(month, {{ window_months }}, ev.start_month)
    join {{ ref('fact_food_price_monthly') }} pw
      on pw.date_key = dw.date_key and pw.food_index_id = p0.food_index_id
),
price_peak as (
    select pp.event_id, pp.food_index_id, pp.months_after_start, pp.rise_pct,
           row_number() over (partition by pp.event_id, pp.food_index_id order by pp.rise_pct desc) as rk,
           count(*)     over (partition by pp.event_id, pp.food_index_id) as months_observed
    from price_path pp
)
{%- endmacro %}

{# Per year: how many crop-country pairs fell below -k SD (Q27). #}
{% macro fail_ctes(k) -%}
fail as (
    select ya.year_num, cast(ya.production_t as float) as prod_t,
           case when ya.anomaly_pct <= -{{ k }} * s.std_anom_pct then 1 else 0 end as failed
    from {{ ref('fact_yield_anomaly') }} ya
    join {{ ref('fact_yield_sensitivity') }} s
      on s.area_code = ya.area_code and s.item_code = ya.item_code
    where ya.anomaly_pct is not null and s.std_anom_pct > 0
),
yearly as (
    select f.year_num, ph.phase_name,
           count(*)       as n_pairs,
           sum(f.failed)  as n_failed,
           100.0 * sum(f.failed) / count(*) as pct_pairs_failed,
           100.0 * sum(case when f.failed = 1 then coalesce(f.prod_t, 0) else 0 end)
                 / nullif(sum(coalesce(f.prod_t, 0)), 0) as pct_production_failed
    from fail f
    join {{ ref('fact_enso_year') }} e on e.year_num = f.year_num
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.year_phase_id
    group by f.year_num, ph.phase_name
)
{%- endmacro %}

{# Series completeness for primary-crop yields (Q30); needs the `p` CTE. #}
{% macro quality_ctes(min_years) -%}
rows_in_window as (
    select c.area_code, c.item_code, c.year_num, c.value, c.flag_code
    from {{ ref('fact_crop_production') }} c
    join {{ ref('dim_item') }} i on i.item_code = c.item_code and i.is_primary_crop = 1
    join {{ ref('dim_area') }} a on a.area_code = c.area_code and a.is_aggregate = 0
    cross join p
    where c.element_code = 5412
      and c.year_num between p.start_year and p.end_year
),
valid as (
    select r.area_code, r.item_code, r.year_num, r.value, r.flag_code,
           lag(r.year_num) over (partition by r.area_code, r.item_code order by r.year_num) as prev_year
    from rows_in_window r
    where r.value is not null
),
agg_valid as (
    select area_code, item_code,
           count(*)                                       as n_valid,
           min(year_num)                                  as first_year,
           max(year_num)                                  as last_year,
           sum(case when value = 0 then 1 else 0 end)     as n_zero,
           sum(case when flag_code = 'A' then 1 else 0 end) as n_official,
           max(coalesce(year_num - prev_year - 1, 0))     as max_gap_years
    from valid
    group by area_code, item_code
),
agg_all as (
    select area_code, item_code,
           count(*)                                       as n_rows,
           sum(case when value is null then 1 else 0 end) as n_null_rows
    from rows_in_window
    group by area_code, item_code
),
quality as (
    select a.area_name, i.item_name, v.area_code, v.item_code,
           v.first_year, v.last_year, v.n_valid,
           cast(p.end_year - p.start_year + 1 as int)                         as expected_years,
           al.n_null_rows                                                     as n_rows_with_missing_value,
           v.n_zero,
           v.max_gap_years,
           cast(v.n_official as float) / v.n_valid                            as official_share,
           cast(v.n_zero as float) / v.n_valid                                as zero_share,
           case when v.n_valid >= {{ min_years }}
                 and v.max_gap_years <= p.max_gap_years
                 and cast(v.n_zero as float) / v.n_valid <= p.max_zero_share
                then 1 else 0 end                                             as passes_basic,
           q.passes_quality                                                   as passes_strict_silver
    from agg_valid v
    join agg_all al on al.area_code = v.area_code and al.item_code = v.item_code
    join {{ ref('dim_area') }} a on a.area_code = v.area_code
    join {{ ref('dim_item') }} i on i.item_code = v.item_code
    cross join p
    left join {{ ref('slv_series_quality') }} q on q.area_code = v.area_code and q.item_code = v.item_code
)
{%- endmacro %}
