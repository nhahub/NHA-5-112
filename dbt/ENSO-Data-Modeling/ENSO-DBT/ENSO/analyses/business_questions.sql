{#-
  ENSO BUSINESS QUESTIONS  -  ANSWER QUERIES (T-SQL, dbt analysis)
  ===========================================================================
  Source of the questions : ENSO_Business_Questions_v3.docx (Q1 - Q30)
  Reads from              : the gold layer (dim_* / fact_*) plus slv_oni_centered,
                            slv_enso_monthly, slv_series_quality and the
                            analysis_parameters seed.  Nothing is changed in the DB.

  HOW TO RUN
    1. From the dbt project folder (venv active, `dbt debug` OK):
           dbt compile --select business_questions
       -> target/compiled/ENSO/analyses/business_questions.sql  (plain T-SQL)
    2. Open that compiled file in SSMS / Azure Data Studio and run ONE query
       at a time (select the block between two "Qxx" banners, press Execute).
       Every query ends with a semicolon, so a whole-file run also works and
       returns 40-ish result sets in order.

  TUNABLE SETTINGS : the `set` lines directly below.  The thresholds were fixed
  BEFORE looking at results (as the questions guide asks): change them only on
  purpose and write the change down.

  CONVENTIONS USED EVERYWHERE
    * ONI month t  = slv_oni_centered.oni_centered  (the 3-month mean is
      forward-looking in the source file, so it is shifted one month: the value
      labelled with month t-1 is centred on month t).
    * Correlation  = Pearson r computed from SUM / COUNT (T-SQL has no corr()).
    * Lag k        = ONI of month (t - k) against the target of month t.
    * Yield data   = fact_yield_anomaly (primary crops, series that pass the
      quality filter, linear trend 1982-2024 removed).
    * Year phase   = fact_enso_year.year_phase_id (event phase of November).
    * Small samples: ~40 yearly points per series, 11 El Nino events since 1990,
      10 rainfall points.  Read every result as an INDICATION, not a proof.
-#}

{# ------------------------------- settings ------------------------------- #}
{% set top_n = 10 %}
{% set min_production_t = 100000 %}             {# Q7: ignore tiny producers #}
{% set min_pair_years = 20 %}                   {# Q9, Q10, Q30: min usable years #}
{% set sens_thresholds = [-2, -3, -5] %}        {# Q3: "sensitive" cut-offs (%) #}
{% set compare_years = [1982, 1997, 2015, 2023] %}  {# Q22 strongest past events #}
{% set current_year = 2026 %}                   {# Q16, Q17, Q22, Q29 #}
{% set analog_months_events = 6 %}              {# Q16a: events file stops at 2026-06 #}
{% set analog_months_nino = 10 %}               {# Q16b, Q17: Nino file reaches 2026-10 #}
{% set analog_top_n = 5 %}
{% set analog_max_yield_year = 2024 %}          {# last year with yield data #}
{% set rain_signal_t = 2 %}                     {# Q24: |t| needed to call wetter/drier #}
{% set price_window_months = 24 %}              {# Q14 #}
{% set fail_sd_multiple = 1 %}                  {# Q27: failure = anomaly <= -1 SD #}
{% set spike_sd = 1.5 %}                        {# Q26 #}
{% set spike_window = 60 %}                     {# Q26: trailing months for mean/SD #}
{% set spike_min_history = 36 %}                {# Q26 #}
{% set band_months = 2 %}                       {# Q29: +/- months around the best lag #}
{% set manual_onset = none %}                   {# Q29: e.g. '2026-03-01' to override #}
{% set w_risk = 1 %}                            {# Q17 weights #}
{% set w_analog = 1 %}
{% set w_share = 1 %}
{% set egypt_items = '15, 27, 56, 156' %}       {# wheat, rice, maize, sugar cane #}
{% set drop_from_year = 2023 %}                 {# Q20: "without 2023-2024" #}

-- =====================================================================
-- A. EXPOSURE AND RISK
-- =====================================================================

-- =====================================================================
-- Q1  Which countries are most exposed to ENSO-driven rainfall swings?
--     Best |r| between rainfall anomaly and ONI over lags 0-6 months, plus the
--     mean rainfall anomaly in El Nino / La Nina months. 10 GPCP points only.
-- =====================================================================
with {{ lags_cte(6) }},
{{ rain_oni_pairs() }},
{{ corr_best('rain', 'rain_pairs', 'location_id') }},
phase_means as (
    select pa.location_id,
           avg(case when ph.phase_code = 'elnino' then pa.anomaly_mm_day end) as mean_anom_el_nino,
           avg(case when ph.phase_code = 'lanina' then pa.anomaly_mm_day end) as mean_anom_la_nina
    from {{ ref('fact_precip_anomaly') }} pa
    join {{ ref('fact_enso_monthly') }} e on e.date_key = pa.date_key
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_event_id
    group by pa.location_id
)
select
    rank() over (order by abs(b.r_value) desc)                       as exposure_rank,
    loc.location_name,
    b.lag_months                                                     as best_lag_months,
    round(b.r_value, 3)                                              as r_best,
    round(100.0 * b.r_value * b.r_value, 1)                          as variance_explained_pct,
    case when b.r_value > 0 then 'wetter when ONI rises'
         else 'drier when ONI rises' end                             as direction,
    round(pm.mean_anom_el_nino, 3)                                   as mean_anom_el_nino_mm_day,
    round(pm.mean_anom_la_nina, 3)                                   as mean_anom_la_nina_mm_day,
    b.n_months
from best_rain b
join {{ ref('dim_location') }} loc on loc.location_id = b.location_id
join phase_means pm on pm.location_id = b.location_id
where b.rk = 1
order by exposure_rank;


-- =====================================================================
-- Q2  Which crops in which countries lose the most yield during El Nino,
--     and which during La Nina?   (a: El Nino, b: La Nina, c: full heat-map table)
--     Mean detrended yield anomaly by year phase; groups with fewer than
--     min_years_per_group years are dropped.  n is shown next to every number.
-- =====================================================================

-- Q2a  Top losers in El Nino years
with {{ params_cte() }}
select top ({{ top_n }})
    a.area_name, i.item_name,
    round(s.mean_anom_el_nino_pct, 2) as mean_anom_el_nino_pct,
    s.n_el_nino,
    round(s.mean_anom_neutral_pct, 2) as mean_anom_neutral_pct,
    round(s.mean_anom_el_nino_pct - s.mean_anom_neutral_pct, 2) as gap_vs_neutral_pct_points,
    round(s.avg_production_t, 0) as avg_production_t
from {{ ref('fact_yield_sensitivity') }} s
join {{ ref('dim_area') }} a on a.area_code = s.area_code and a.is_aggregate = 0
join {{ ref('dim_item') }} i on i.item_code = s.item_code
cross join p
where s.n_el_nino >= p.min_years and s.mean_anom_el_nino_pct is not null
order by s.mean_anom_el_nino_pct asc;

-- Q2b  Top losers in La Nina years
with {{ params_cte() }}
select top ({{ top_n }})
    a.area_name, i.item_name,
    round(s.mean_anom_la_nina_pct, 2) as mean_anom_la_nina_pct,
    s.n_la_nina,
    round(s.mean_anom_neutral_pct, 2) as mean_anom_neutral_pct,
    round(s.mean_anom_la_nina_pct - s.mean_anom_neutral_pct, 2) as gap_vs_neutral_pct_points,
    round(s.avg_production_t, 0) as avg_production_t
from {{ ref('fact_yield_sensitivity') }} s
join {{ ref('dim_area') }} a on a.area_code = s.area_code and a.is_aggregate = 0
join {{ ref('dim_item') }} i on i.item_code = s.item_code
cross join p
where s.n_la_nina >= p.min_years and s.mean_anom_la_nina_pct is not null
order by s.mean_anom_la_nina_pct asc;

-- Q2c  Every crop x country pair (heat-map source)
select
    a.area_name, i.item_name,
    round(s.mean_anom_el_nino_pct, 2) as mean_anom_el_nino_pct, s.n_el_nino,
    round(s.mean_anom_la_nina_pct, 2) as mean_anom_la_nina_pct, s.n_la_nina,
    round(s.mean_anom_neutral_pct, 2) as mean_anom_neutral_pct, s.n_neutral
from {{ ref('fact_yield_sensitivity') }} s
join {{ ref('dim_area') }} a on a.area_code = s.area_code and a.is_aggregate = 0
join {{ ref('dim_item') }} i on i.item_code = s.item_code
order by i.item_name, a.area_name;


-- =====================================================================
-- Q3  How much of world wheat, rice, maize, soya and sugar production comes
--     from countries whose yields respond most to ENSO?
--     "Sensitive" = mean anomaly <= threshold in El Nino (or La Nina) years with at
--     least min_years_per_group years.  Thresholds -2 / -3 / -5 % shown side by side.
--     The share is a PRODUCTION share (not trade) of the pairs that passed the
--     quality filter; covered_share shows how much of the world those pairs cover.
-- =====================================================================
with {{ params_cte() }},
thr as (
    select v.threshold_pct
    from (values {% for t in sens_thresholds %}({{ t }}){{ "," if not loop.last }}{% endfor %}) as v(threshold_pct)
),
pairs as (
    select s.area_code, s.item_code, i.item_name,
           s.n_el_nino, s.n_la_nina, s.mean_anom_el_nino_pct, s.mean_anom_la_nina_pct, s.world_share
    from {{ ref('fact_yield_sensitivity') }} s
    join {{ ref('dim_item') }} i on i.item_code = s.item_code
    join {{ ref('dim_area') }} a on a.area_code = s.area_code and a.is_aggregate = 0
    where s.item_code in (15, 27, 56, 236, 156)
),
flagged as (
    select pr.item_name, pr.world_share, t.threshold_pct,
           case when pr.n_el_nino >= p.min_years and pr.mean_anom_el_nino_pct <= t.threshold_pct then 1 else 0 end as sens_el,
           case when pr.n_la_nina >= p.min_years and pr.mean_anom_la_nina_pct <= t.threshold_pct then 1 else 0 end as sens_la
    from pairs pr
    cross join thr t
    cross join p
)
select
    item_name, threshold_pct,
    count(*)                                                                                  as n_pairs,
    sum(case when sens_el = 1 or sens_la = 1 then 1 else 0 end)                               as n_sensitive_pairs,
    round(100.0 * sum(case when sens_el = 1 or sens_la = 1 then world_share end), 1)          as sensitive_share_of_world_pct,
    round(100.0 * sum(case when sens_el = 1 then world_share end), 1)                         as el_nino_sensitive_share_pct,
    round(100.0 * sum(case when sens_la = 1 then world_share end), 1)                         as la_nina_sensitive_share_pct,
    round(100.0 * sum(world_share), 1)                                                        as covered_share_of_world_pct
from flagged
group by item_name, threshold_pct
order by item_name, threshold_pct desc;


-- =====================================================================
-- Q4  Which countries combine high rainfall sensitivity and high yield volatility?
--     Reads the ready-made risk score and adds the quadrant (median split).
--     Countries without a GPCP point are scored on yield only (risk_basis).
-- =====================================================================
with r as (
    select a.area_name, loc.location_name, k.rain_sensitivity, k.best_lag,
           k.yield_volatility, k.risk_score, k.risk_basis, k.official_share
    from {{ ref('fact_food_security_risk') }} k
    join {{ ref('dim_area') }} a on a.area_code = k.area_code
    left join {{ ref('dim_location') }} loc on loc.location_id = k.location_id
),
med as (
    select r.*,
           percentile_cont(0.5) within group (order by r.rain_sensitivity) over () as median_rain,
           percentile_cont(0.5) within group (order by r.yield_volatility) over () as median_yield
    from r
)
select
    rank() over (order by risk_score desc)  as risk_rank,
    area_name, location_name, risk_basis,
    round(risk_score, 1)                    as risk_score,
    round(rain_sensitivity, 3)              as rain_sensitivity_abs_r,
    best_lag                                as best_lag_months,
    round(yield_volatility, 2)              as yield_volatility_pct,
    round(official_share, 3)                as official_share,
    case when rain_sensitivity is null                                       then 'yield only (no GPCP point)'
         when rain_sensitivity >= median_rain and yield_volatility >= median_yield then 'high rain sensitivity + high yield volatility'
         when rain_sensitivity >= median_rain                                 then 'high rain sensitivity only'
         when yield_volatility >= median_yield                                then 'high yield volatility only'
         else 'low / low' end               as quadrant
from med
order by risk_score desc;


-- =====================================================================
-- Q5  Are strong events much more damaging than weak ones?
--     Each production year is linked to the event that contains its November;
--     events are classed by their PEAK ONI (Weak / Moderate / Strong / Very strong).
--     Very strong events are few: read this as an indication, not a proof.
-- =====================================================================
with year_event as (
    select d.year_num,
           coalesce(ph.phase_name, 'Neutral (no event)') as phase_name,
           coalesce(ph.phase_id, 3)                      as phase_order,
           coalesce(it.label, 'n/a')                     as intensity,
           coalesce(it.intensity_id, 0)                  as intensity_order
    from {{ ref('fact_enso_monthly') }} e
    join {{ ref('dim_date') }} d on d.date_key = e.date_key and d.month_num = 11
    left join {{ ref('dim_enso_event') }} ev on ev.event_id = e.event_id
    left join {{ ref('dim_enso_phase') }} ph on ph.phase_id = ev.phase_id
    left join {{ ref('dim_intensity') }} it on it.intensity_id = ev.intensity_id
)
select
    ye.phase_name, ye.intensity,
    count(distinct ya.year_num)                                         as n_years,
    count(*)                                                            as n_pair_years,
    round(avg(ya.anomaly_pct), 2)                                       as mean_yield_anomaly_pct,
    round(sum(ya.anomaly_pct * ya.production_t)
          / nullif(sum(case when ya.production_t is not null then ya.production_t end), 0), 2)
                                                                        as production_weighted_anomaly_pct,
    round(avg(case when ya.anomaly_pct < 0 then 1.0 else 0.0 end), 3)   as share_of_pair_years_below_trend
from {{ ref('fact_yield_anomaly') }} ya
join year_event ye on ye.year_num = ya.year_num
where ya.anomaly_pct is not null
group by ye.phase_name, ye.phase_order, ye.intensity, ye.intensity_order
order by ye.phase_order, ye.intensity_order;


-- =====================================================================
-- B. AGRICULTURE AND PRODUCTION
-- =====================================================================

-- =====================================================================
-- Q6  Is rainfall the real channel behind yield changes?
--     Per country with a GPCP point, YEARLY (rain exists from 2000, ~25 years):
--       r(ONI, rain)  r(rain, yield)  r(ONI, yield)  and the partial r(ONI, yield | rain).
--     ONI = November-centred ONI (oni_ond); rain = mean of the 12 monthly anomalies;
--     yield = production-weighted mean yield anomaly of the country's primary crops.
--     Egypt's rain is ~0, so its rain correlations carry no meaning.
-- =====================================================================
with {{ params_cte() }},
rain_year as (
    select loc.area_code, d.year_num, avg(cast(pa.anomaly_mm_day as float)) as rain_anom
    from {{ ref('fact_precip_anomaly') }} pa
    join {{ ref('dim_date') }} d on d.date_key = pa.date_key
    join {{ ref('dim_location') }} loc on loc.location_id = pa.location_id
    where loc.area_code is not null and pa.anomaly_mm_day is not null
    group by loc.area_code, d.year_num
    having count(*) = 12
),
yield_year as (
    select ya.area_code, ya.year_num,
           sum(cast(ya.anomaly_pct as float) * cast(ya.production_t as float))
             / nullif(sum(case when ya.production_t > 0 then cast(ya.production_t as float) end), 0) as yield_anom
    from {{ ref('fact_yield_anomaly') }} ya
    where ya.anomaly_pct is not null and ya.production_t > 0
    group by ya.area_code, ya.year_num
),
joined as (
    select a.area_name, r.year_num,
           cast(e.oni_ond as float) as oni, r.rain_anom as rain, y.yield_anom as yld
    from rain_year r
    join yield_year y on y.area_code = r.area_code and y.year_num = r.year_num
    join {{ ref('fact_enso_year') }} e on e.year_num = r.year_num
    join {{ ref('dim_area') }} a on a.area_code = r.area_code
    cross join p
    where e.oni_ond is not null and y.yield_anom is not null
      and r.year_num between p.start_year and p.end_year
),
r3 as (
    select area_name, count(*) as n_years,
           {{ pearson('oni', 'rain') }} as r_oni_rain,
           {{ pearson('rain', 'yld') }} as r_rain_yield,
           {{ pearson('oni', 'yld') }}  as r_oni_yield
    from joined
    group by area_name
),
r4 as (
    select r3.*,
           (r_oni_yield - r_oni_rain * r_rain_yield)
             / nullif(sqrt((1 - r_oni_rain * r_oni_rain) * (1 - r_rain_yield * r_rain_yield)), 0) as partial_r_oni_yield_given_rain
    from r3
)
select
    area_name, n_years,
    round(r_oni_rain, 3)                     as r_oni_rain,
    round(r_rain_yield, 3)                   as r_rain_yield,
    round(r_oni_yield, 3)                    as r_oni_yield,
    round(partial_r_oni_yield_given_rain, 3) as partial_r_oni_yield_given_rain,
    case when n_years < 15 then 'too few years'
         when abs(r_oni_rain) >= 0.3 and abs(r_rain_yield) >= 0.3
              and abs(partial_r_oni_yield_given_rain) < abs(r_oni_yield) then 'rain looks like a channel'
         when abs(r_oni_yield) >= 0.3 and abs(r_oni_rain) < 0.3 then 'ONI-yield link without a rain link (other channel?)'
         else 'no clear link' end            as reading
from r4
order by area_name;


-- =====================================================================
-- Q7  Which crop-country pairs have the most stable yields?
--     a: top stable overall   b: top 3 per crop.  Pairs below min_production_t are ignored.
--     Official_share is shown because "stable" can just mean "estimated" (see Q19).
-- =====================================================================

-- Q7a
select top ({{ top_n }})
    a.area_name, i.item_name,
    round(s.std_anom_pct, 2) as std_anom_pct,
    round(s.avg_production_t, 0) as avg_production_t,
    round(s.official_share, 3) as official_share
from {{ ref('fact_yield_sensitivity') }} s
join {{ ref('dim_area') }} a on a.area_code = s.area_code and a.is_aggregate = 0
join {{ ref('dim_item') }} i on i.item_code = s.item_code
where s.std_anom_pct is not null and s.avg_production_t >= {{ min_production_t }}
order by s.std_anom_pct asc;

-- Q7b
with ranked as (
    select a.area_name, i.item_name, s.std_anom_pct, s.avg_production_t, s.official_share,
           row_number() over (partition by i.item_name order by s.std_anom_pct asc) as rk
    from {{ ref('fact_yield_sensitivity') }} s
    join {{ ref('dim_area') }} a on a.area_code = s.area_code and a.is_aggregate = 0
    join {{ ref('dim_item') }} i on i.item_code = s.item_code
    where s.std_anom_pct is not null and s.avg_production_t >= {{ min_production_t }}
)
select item_name, rk as stability_rank, area_name,
       round(std_anom_pct, 2) as std_anom_pct,
       round(avg_production_t, 0) as avg_production_t,
       round(official_share, 3) as official_share
from ranked
where rk <= 3
order by item_name, rk;


-- =====================================================================
-- Q8  Which crops benefit from La Nina, and can those gains offset El Nino losses?
--     Tonnes gained/lost per pair-year = production - production / (1 + anomaly).
--     Summed per crop and year, then averaged over El Nino / La Nina / Neutral years.
--     Partial estimate: only pairs that passed the quality filter.
-- =====================================================================
with pair_delta as (
    select ya.area_code, ya.item_code, ya.year_num,
           cast(ya.production_t as float) * (cast(ya.anomaly_pct as float) / 100.0)
             / nullif(1 + cast(ya.anomaly_pct as float) / 100.0, 0) as delta_t
    from {{ ref('fact_yield_anomaly') }} ya
    where ya.production_t is not null and ya.anomaly_pct is not null
),
crop_year as (
    select item_code, year_num,
           sum(delta_t)                                    as net_t,
           sum(case when delta_t > 0 then delta_t else 0 end) as gain_t,
           sum(case when delta_t < 0 then delta_t else 0 end) as loss_t
    from pair_delta
    group by item_code, year_num
),
by_phase as (
    select cy.item_code,
           sum(case when ph.phase_code = 'elnino' then 1 else 0 end) as n_el_nino_years,
           sum(case when ph.phase_code = 'lanina' then 1 else 0 end) as n_la_nina_years,
           avg(case when ph.phase_code = 'elnino' then cy.net_t  end) as net_el,
           avg(case when ph.phase_code = 'elnino' then cy.loss_t end) as loss_el,
           avg(case when ph.phase_code = 'lanina' then cy.net_t  end) as net_la,
           avg(case when ph.phase_code = 'lanina' then cy.gain_t end) as gain_la,
           avg(case when ph.phase_code = 'neutral' then cy.net_t end) as net_neutral
    from crop_year cy
    join {{ ref('fact_enso_year') }} ey on ey.year_num = cy.year_num
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = ey.year_phase_id
    group by cy.item_code
)
select
    i.item_name, b.n_el_nino_years, b.n_la_nina_years,
    round(b.net_el / 1000000.0, 3)      as el_nino_avg_net_mt,
    round(b.loss_el / 1000000.0, 3)     as el_nino_avg_losses_mt,
    round(b.net_la / 1000000.0, 3)      as la_nina_avg_net_mt,
    round(b.gain_la / 1000000.0, 3)     as la_nina_avg_gains_mt,
    round(b.net_neutral / 1000000.0, 3) as neutral_avg_net_mt,
    case when b.net_el < 0 and b.net_la > 0
         then round(100.0 * b.net_la / abs(b.net_el), 1) end as la_nina_net_gain_as_pct_of_el_nino_net_loss
from by_phase b
join {{ ref('dim_item') }} i on i.item_code = b.item_code
order by i.item_name;


-- =====================================================================
-- Q9  How long after an ENSO shift does the effect on rainfall and then yield appear?
--     a: rainfall lag curve (lags 0-12, one line per country, best lag flagged)
--     b: yield, per pair: ONI of the same year vs of the previous year
--     c: yield, per crop summary (yield is yearly: no monthly lag exists)
-- =====================================================================

-- Q9a
with {{ lags_cte(12) }},
{{ rain_oni_pairs() }},
{{ corr_best('rain', 'rain_pairs', 'location_id') }}
select
    loc.location_name, c.lag_months, c.n_months,
    round(c.r_value, 3) as r_value,
    case when b.lag_months = c.lag_months then 1 else 0 end as is_best_lag
from corr_rain c
join best_rain b on b.location_id = c.location_id and b.rk = 1
join {{ ref('dim_location') }} loc on loc.location_id = c.location_id
order by loc.location_name, c.lag_months;

-- Q9b
with {{ yield_lag_ctes(min_pair_years) }}
select
    a.area_name, i.item_name, pl.n_years,
    round(pl.r_same_year, 3) as r_same_year,
    round(pl.r_next_year, 3) as r_prev_year_oni,
    pl.stronger_link
from pair_lag pl
join {{ ref('dim_area') }} a on a.area_code = pl.area_code
join {{ ref('dim_item') }} i on i.item_code = pl.item_code
order by i.item_name, a.area_name;

-- Q9c
with {{ yield_lag_ctes(min_pair_years) }}
select
    i.item_name,
    count(*)                                                                as n_pairs,
    round(avg(abs(pl.r_same_year)), 3)                                      as mean_abs_r_same_year,
    round(avg(abs(pl.r_next_year)), 3)                                      as mean_abs_r_prev_year_oni,
    round(100.0 * avg(case when abs(pl.r_next_year) > abs(pl.r_same_year) then 1.0 else 0 end), 0)
                                                                            as pct_pairs_where_previous_year_is_stronger
from pair_lag pl
join {{ ref('dim_item') }} i on i.item_code = pl.item_code
group by i.item_name
order by i.item_name;


-- =====================================================================
-- Q10  Which ONI season (JFM / AMJ / JAS / OND) best explains each crop's yield
--      anomaly, and is it the same across countries?
--      anomaly_3m of months 1, 4, 7, 10 = JFM, AMJ, JAS, OND (the source labels a 3-month
--      mean with its first month).  We test 4 seasons, so trust a season only if it is the
--      best one in several countries (n_countries_where_best).  No crop calendar: this is
--      "best-correlated ONI season", not "growing season".
-- =====================================================================
with season_pairs as (
    select ya.area_code, ya.item_code, ya.year_num,
           case d.month_num when 1 then 'JFM' when 4 then 'AMJ' when 7 then 'JAS' when 10 then 'OND' end as oni_season,
           cast(f.anomaly_3m as float)   as x,
           cast(ya.anomaly_pct as float) as y
    from {{ ref('fact_yield_anomaly') }} ya
    join {{ ref('dim_date') }} d on d.year_num = ya.year_num and d.month_num in (1, 4, 7, 10)
    join {{ ref('fact_enso_monthly') }} f on f.date_key = d.date_key
    where ya.anomaly_pct is not null and f.anomaly_3m is not null
),
season_corr as (
    select area_code, item_code, oni_season, count(*) as n_years, {{ pearson('x', 'y') }} as r_value
    from season_pairs
    group by area_code, item_code, oni_season
),
ranked as (
    select sc.*, row_number() over (partition by area_code, item_code order by abs(r_value) desc) as rk
    from season_corr sc
    where r_value is not null and n_years >= {{ min_pair_years }}
)
select
    i.item_name, r.oni_season,
    count(*)                                         as n_countries,
    sum(case when r.rk = 1 then 1 else 0 end)        as n_countries_where_best,
    round(avg(r.r_value), 3)                         as mean_r,
    round(avg(abs(r.r_value)), 3)                    as mean_abs_r,
    row_number() over (partition by i.item_name
                       order by sum(case when r.rk = 1 then 1 else 0 end) desc, avg(abs(r.r_value)) desc) as season_rank_for_crop
from ranked r
join {{ ref('dim_item') }} i on i.item_code = r.item_code
group by i.item_name, r.oni_season
order by i.item_name, season_rank_for_crop;


-- =====================================================================
-- C. PRICES AND MARKETS
-- =====================================================================

-- =====================================================================
-- Q11  Do global food prices rise after El Nino starts, and which sub-index reacts most?
--      Event study on the REAL indices: % change from the first month of each El Nino
--      event (since 1990) to +6 / +12 / +24 months, against the same change measured
--      from every Neutral month.  Few events (see n_events): partial, lagged effect.
-- =====================================================================
with horizons as (
    select v.h as horizon_months from (values (6), (12), (24)) as v(h)
),
first_months as (
    select e.start_date_key
    from {{ ref('dim_enso_event') }} e
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_id and ph.phase_code = 'elnino'
    where e.start_date_key >= 19900101
),
fwd as (
    select p0.date_key, p0.food_index_id, h.horizon_months,
           (p1.real_index / nullif(p0.real_index, 0) - 1) * 100 as chg_pct
    from {{ ref('fact_food_price_monthly') }} p0
    join {{ ref('dim_date') }} d0 on d0.date_key = p0.date_key
    cross join horizons h
    join {{ ref('dim_date') }} d1 on d1.month_start = dateadd(month, h.horizon_months, d0.month_start)
    join {{ ref('fact_food_price_monthly') }} p1
      on p1.date_key = d1.date_key and p1.food_index_id = p0.food_index_id
),
after_el_nino as (
    select f.food_index_id, f.horizon_months, avg(f.chg_pct) as avg_chg_pct, count(*) as n_events
    from fwd f
    join first_months fm on fm.start_date_key = f.date_key
    group by f.food_index_id, f.horizon_months
),
neutral_base as (
    select f.food_index_id, f.horizon_months, avg(f.chg_pct) as avg_chg_pct, count(*) as n_months
    from fwd f
    join {{ ref('fact_enso_monthly') }} e on e.date_key = f.date_key
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_event_id and ph.phase_code = 'neutral'
    group by f.food_index_id, f.horizon_months
)
select
    a.horizon_months, fi.index_code, fi.is_headline, a.n_events,
    round(a.avg_chg_pct, 2)                  as avg_change_after_el_nino_start_pct,
    round(n.avg_chg_pct, 2)                  as avg_change_from_neutral_months_pct,
    round(a.avg_chg_pct - n.avg_chg_pct, 2)  as excess_vs_neutral_pct_points,
    rank() over (partition by a.horizon_months order by a.avg_chg_pct - n.avg_chg_pct desc) as reaction_rank
from after_el_nino a
join neutral_base n on n.food_index_id = a.food_index_id and n.horizon_months = a.horizon_months
join {{ ref('dim_food_index') }} fi on fi.food_index_id = a.food_index_id
order by a.horizon_months, reaction_rank;


-- =====================================================================
-- Q12  How many months does it take for price changes to follow an ENSO event?
--      r between real YoY % of each index and ONI lagged 0-12 months (best lag flagged).
--      13 lags are tested, so the "best" one can be chance: compare r with the noise band
--      (2 / sqrt(n); months overlap, so the real band is wider).
-- =====================================================================
with {{ lags_cte(12) }},
{{ price_oni_pairs('price_pairs', 'yoy_real_pct') }},
{{ corr_best('price', 'price_pairs', 'food_index_id') }}
select
    fi.index_code, c.lag_months, c.n_months,
    round(c.r_value, 3)                    as r_value,
    round(2.0 / sqrt(c.n_months), 3)       as approx_noise_band,
    case when b.lag_months = c.lag_months then 1 else 0 end as is_best_lag
from corr_price c
join best_price b on b.food_index_id = c.food_index_id and b.rk = 1
join {{ ref('dim_food_index') }} fi on fi.food_index_id = c.food_index_id
order by fi.food_index_id, c.lag_months;


-- =====================================================================
-- Q13  Do oil prices rise about a year after El Nino, and is palm-oil yield in
--      Indonesia and Malaysia part of the explanation?  Three separate links:
--        1: ONI (Nov) -> oil palm fruit yield anomaly, same year        (per country)
--        2: palm yield anomaly (year t) -> Oils real YoY (year t+1)     (per country)
--        3: ONI -> Oils real YoY, ONI lagged 12 months                  (monthly)
--      Malaysia has no rainfall point, so link 1 uses yield only.  Biodiesel and other
--      drivers of oil prices are not measured here.
-- =====================================================================
with palm as (
    select a.area_name, ya.year_num,
           cast(ya.anomaly_pct as float) as yld,
           cast(e.oni_ond as float)      as oni_ond
    from {{ ref('fact_yield_anomaly') }} ya
    join {{ ref('dim_area') }} a on a.area_code = ya.area_code and a.area_name in ('Indonesia', 'Malaysia')
    join {{ ref('fact_enso_year') }} e on e.year_num = ya.year_num
    where ya.item_code = 254 and ya.anomaly_pct is not null and e.oni_ond is not null
),
oils_year as (
    select d.year_num, avg(cast(fy.yoy_real_pct as float)) as oils_yoy_real
    from {{ ref('fact_food_price_yoy') }} fy
    join {{ ref('dim_date') }} d on d.date_key = fy.date_key
    join {{ ref('dim_food_index') }} fi on fi.food_index_id = fy.food_index_id and fi.index_code = 'OILS'
    where fy.yoy_real_pct is not null
    group by d.year_num
    having count(*) = 12
),
oils_lag12 as (
    select cast(o.oni_centered as float) as x, cast(fy.yoy_real_pct as float) as y
    from {{ ref('fact_food_price_yoy') }} fy
    join {{ ref('dim_date') }} d on d.date_key = fy.date_key
    join {{ ref('dim_food_index') }} fi on fi.food_index_id = fy.food_index_id and fi.index_code = 'OILS'
    join {{ ref('slv_oni_centered') }} o on o.month_start = dateadd(month, -12, d.month_start)
    where fy.yoy_real_pct is not null and o.oni_centered is not null
),
links as (
    select 1 as link_no, 'ONI (Nov) -> palm yield anomaly, same year' as link, area_name,
           count(*) as n, {{ pearson('oni_ond', 'yld') }} as r_value
    from palm
    group by area_name
    union all
    select 2, 'Palm yield anomaly (t) -> Oils real YoY (t+1)', pm.area_name,
           count(*), {{ pearson('yld', 'oils_yoy_real') }}
    from palm pm
    join oils_year oy on oy.year_num = pm.year_num + 1
    group by pm.area_name
    union all
    select 3, 'ONI -> Oils real YoY, ONI lagged 12 months', 'World (FFPI)',
           count(*), {{ pearson('x', 'y') }}
    from oils_lag12
)
select link_no, link, area_name, n, round(r_value, 3) as r_value
from links
order by link_no, area_name;


-- =====================================================================
-- Q14  Do strong El Nino events lead to bigger price spikes than weak ones?
--      Biggest % rise of each REAL index within {{ price_window_months }} months of the event start (events since 1990).
--      a: one row per event and index (scatter source)   b: summary by intensity.
--      is_complete_window = 0 for an event whose window is not over yet.
-- =====================================================================

-- Q14a
with {{ event_rise_ctes(price_window_months) }}
select
    ev.event_id, ev.start_month, ev.months as event_months,
    round(ev.peak_anom_3m, 2) as peak_oni, ev.intensity,
    fi.index_code,
    round(pk.rise_pct, 1)     as max_rise_pct,
    pk.months_after_start     as month_of_max_rise,
    pk.months_observed,
    case when pk.months_observed = {{ price_window_months }} + 1 then 1 else 0 end as is_complete_window
from price_peak pk
join ev on ev.event_id = pk.event_id
join {{ ref('dim_food_index') }} fi on fi.food_index_id = pk.food_index_id
where pk.rk = 1
order by fi.food_index_id, ev.start_month;

-- Q14b
with {{ event_rise_ctes(price_window_months) }}
select
    ev.intensity, fi.index_code,
    count(*)                    as n_events,
    round(avg(pk.rise_pct), 1)  as avg_max_rise_pct,
    round(min(pk.rise_pct), 1)  as min_max_rise_pct,
    round(max(pk.rise_pct), 1)  as max_max_rise_pct
from price_peak pk
join ev on ev.event_id = pk.event_id
join {{ ref('dim_food_index') }} fi on fi.food_index_id = pk.food_index_id
where pk.rk = 1
group by ev.intensity, ev.intensity_id, fi.index_code, fi.food_index_id
order by fi.food_index_id, ev.intensity_id;


-- =====================================================================
-- Q15  How much of food price volatility can ENSO explain?
--      R-squared of real YoY % on ONI at the best lag (0-12), per index.
--      explained = r^2, unexplained = 1 - r^2 (war, energy, policy, stocks ...).
-- =====================================================================
with {{ lags_cte(12) }},
{{ price_oni_pairs('price_pairs', 'yoy_real_pct') }},
{{ corr_best('price', 'price_pairs', 'food_index_id') }}
select
    fi.index_code,
    b.lag_months                                   as best_lag_months,
    b.n_months,
    round(b.r_value, 3)                            as r_at_best_lag,
    round(100.0 * b.r_value * b.r_value, 1)        as explained_by_enso_pct,
    round(100.0 * (1 - b.r_value * b.r_value), 1)  as explained_by_other_factors_pct,
    round(100.0 * c0.r_value * c0.r_value, 1)      as explained_at_lag0_pct
from best_price b
join corr_price c0 on c0.food_index_id = b.food_index_id and c0.lag_months = 0
join {{ ref('dim_food_index') }} fi on fi.food_index_id = b.food_index_id
where b.rk = 1
order by explained_by_enso_pct desc;


-- =====================================================================
-- D. PLANNING AND EARLY WARNING
-- =====================================================================

-- =====================================================================
-- Q16  Which past years does the 2026 event most resemble, and what happened then?
--      RMSE between the 2026 path and every earlier year ("historical analogue",
--      not a forecast).  Two analogue sets, never mixed:
--        a: events file, monthly anomaly 1950+, Jan-Jun (the file stops at 2026-06)
--        b: Nino 3.4 file, 1982+, Jan-Oct
--      c / d: yield and price outcomes of the top analogues of set b (1982-2024,
--      so every analogue can have outcomes), in year t and t+1.
-- =====================================================================

-- Q16a
with {{ analogs_events(current_year, analog_months_events) }}
select top ({{ analog_top_n }})
    year_num as analog_year, round(rmse, 3) as rmse, n_months,
    case when year_num between 1982 and {{ analog_max_yield_year }} then 'yes' else 'no' end as has_yield_data,
    case when year_num >= 1990 then 'yes' else 'no' end as has_price_data,
    case when year_num >= 2000 then 'yes' else 'no' end as has_rain_data
from analogs
order by rmse;

-- Q16b
with {{ analogs_nino(current_year, analog_months_nino, current_year - 1) }}
select top ({{ analog_top_n }})
    year_num as analog_year, round(rmse, 3) as rmse, n_months,
    case when year_num between 1982 and {{ analog_max_yield_year }} then 'yes' else 'no' end as has_yield_data,
    case when year_num >= 1990 then 'yes' else 'no' end as has_price_data,
    case when year_num >= 2000 then 'yes' else 'no' end as has_rain_data
from analogs
order by rmse;

-- Q16c  Yield outcomes in the analogue years (year_offset 0 = analogue year, 1 = next year)
with {{ analogs_nino(current_year, analog_months_nino, analog_max_yield_year) }},
top_years as (
    select top ({{ analog_top_n }}) year_num, rmse from analogs order by rmse
)
select
    t.year_num as analog_year, round(t.rmse, 3) as rmse,
    ya.year_num - t.year_num as year_offset,
    i.item_name,
    count(*)                                        as n_pairs,
    sum(case when ya.anomaly_pct < 0 then 1 else 0 end) as n_pairs_below_trend,
    round(avg(ya.anomaly_pct), 2)                   as mean_anomaly_pct,
    round(sum(ya.anomaly_pct * ya.production_t)
          / nullif(sum(case when ya.production_t is not null then ya.production_t end), 0), 2) as production_weighted_anomaly_pct
from top_years t
join {{ ref('fact_yield_anomaly') }} ya on ya.year_num between t.year_num and t.year_num + 1
join {{ ref('dim_item') }} i on i.item_code = ya.item_code
where ya.anomaly_pct is not null
group by t.year_num, t.rmse, ya.year_num, i.item_name
order by t.rmse, ya.year_num, i.item_name;

-- Q16d  Price outcomes in the analogue years (annual real index and change vs the previous year)
with {{ analogs_nino(current_year, analog_months_nino, analog_max_yield_year) }},
top_years as (
    select top ({{ analog_top_n }}) year_num, rmse from analogs order by rmse
)
select
    t.year_num as analog_year, round(t.rmse, 3) as rmse,
    pa.year_num - t.year_num as year_offset,
    fi.index_code,
    round(pa.real_index, 1) as real_index_year_avg,
    round((pa.real_index / nullif(pp.real_index, 0) - 1) * 100, 1) as real_change_vs_prev_year_pct,
    pa.months_count
from top_years t
join {{ ref('fact_food_price_annual') }} pa on pa.year_num between t.year_num and t.year_num + 1
join {{ ref('fact_food_price_annual') }} pp on pp.year_num = pa.year_num - 1 and pp.food_index_id = pa.food_index_id
join {{ ref('dim_food_index') }} fi on fi.food_index_id = pa.food_index_id
order by t.rmse, pa.year_num, fi.food_index_id;


-- =====================================================================
-- Q17  Which countries and crops should be monitored first if the event continues?
--      Watchlist score (0-100) = weighted mean of three percent-ranks:
--        country risk score (Q4)                      weight {{ w_risk }}
--        worst mean yield anomaly in the analogue years (Q16b, 1982-2024)  weight {{ w_analog }}
--        share of world production (Q3)               weight {{ w_share }}
--      A monitoring priority list, not a production forecast; no crop calendar available.
-- =====================================================================
with {{ analogs_nino(current_year, analog_months_nino, analog_max_yield_year) }},
top_years as (
    select top ({{ analog_top_n }}) year_num from analogs order by rmse
),
analog_yield as (
    select ya.area_code, ya.item_code,
           avg(cast(ya.anomaly_pct as float)) as analog_mean_anom,
           count(*) as n_analog_years
    from {{ ref('fact_yield_anomaly') }} ya
    join top_years t on t.year_num = ya.year_num
    where ya.anomaly_pct is not null
    group by ya.area_code, ya.item_code
),
scored as (
    select a.area_name, i.item_name, k.risk_score, k.risk_basis,
           ay.analog_mean_anom, ay.n_analog_years, s.world_share,
           percent_rank() over (order by k.risk_score)             as risk_pr,
           percent_rank() over (order by ay.analog_mean_anom desc) as analog_pr,
           percent_rank() over (order by s.world_share)            as share_pr
    from {{ ref('fact_yield_sensitivity') }} s
    join analog_yield ay on ay.area_code = s.area_code and ay.item_code = s.item_code
    join {{ ref('fact_food_security_risk') }} k on k.area_code = s.area_code
    join {{ ref('dim_area') }} a on a.area_code = s.area_code
    join {{ ref('dim_item') }} i on i.item_code = s.item_code
    where s.world_share is not null and k.risk_score is not null
)
select top ({{ top_n }})
    area_name, item_name,
    round(100.0 * ({{ w_risk }} * risk_pr + {{ w_analog }} * analog_pr + {{ w_share }} * share_pr)
                / ({{ w_risk + w_analog + w_share }}), 1) as watchlist_score,
    round(risk_score, 1)            as country_risk_score,
    risk_basis,
    round(analog_mean_anom, 2)      as analog_years_mean_anomaly_pct,
    n_analog_years,
    round(100.0 * world_share, 1)   as world_production_share_pct
from scored
order by watchlist_score desc;


-- =====================================================================
-- Q18  Which major producers of Egypt's crops (wheat, maize, rice, sugar cane) are most
--      at risk in El Nino, and how concentrated is world production in them?
--      Top 10 producers per crop (mean of the last 5 years, aggregates excluded), their El Nino
--      yield response, and the world share of the top 5.  No trade data: this shows global
--      exposure, not Egypt's actual suppliers.
-- =====================================================================
with last_year as (
    select max(year_num) as max_year
    from {{ ref('fact_crop_production') }}
    where element_code = 5510 and value is not null
),
recent as (
    select c.area_code, c.item_code, avg(cast(c.value as float)) as avg_prod_t
    from {{ ref('fact_crop_production') }} c
    cross join last_year ly
    where c.element_code = 5510 and c.value is not null
      and c.year_num between ly.max_year - 4 and ly.max_year
      and c.item_code in ({{ egypt_items }})
    group by c.area_code, c.item_code
),
world as (
    select r.item_code, r.avg_prod_t as world_prod_t
    from recent r
    join {{ ref('dim_area') }} a on a.area_code = r.area_code and a.area_name = 'World'
),
ranked as (
    select r.area_code, r.item_code, r.avg_prod_t,
           row_number() over (partition by r.item_code order by r.avg_prod_t desc) as rk
    from recent r
    join {{ ref('dim_area') }} a on a.area_code = r.area_code and a.is_aggregate = 0
)
select
    i.item_name, t.rk as producer_rank, a.area_name,
    round(t.avg_prod_t / 1000000.0, 2)                                  as avg_production_mt,
    round(100.0 * t.avg_prod_t / w.world_prod_t, 1)                     as share_of_world_pct,
    round(100.0 * sum(case when t.rk <= 5 then t.avg_prod_t end) over (partition by t.item_code)
                / w.world_prod_t, 1)                                    as top5_concentration_pct,
    round(s.mean_anom_el_nino_pct, 2)                                   as mean_anom_el_nino_pct,
    s.n_el_nino,
    round(s.mean_anom_la_nina_pct, 2)                                   as mean_anom_la_nina_pct,
    case when s.area_code is null then 'no sensitivity (series failed the quality filter)' else '' end as note
from ranked t
join {{ ref('dim_area') }} a on a.area_code = t.area_code
join {{ ref('dim_item') }} i on i.item_code = t.item_code
join world w on w.item_code = t.item_code
left join {{ ref('fact_yield_sensitivity') }} s on s.area_code = t.area_code and s.item_code = t.item_code
where t.rk <= 10
order by i.item_name, t.rk;


-- =====================================================================
-- E. DATA RELIABILITY
-- =====================================================================

-- =====================================================================
-- Q19  How much of the yield data behind the highest-risk results is official?
--      a: for the 10 highest-risk countries, per crop: production-weighted share of yield-years
--         by FAOSTAT flag (A official, E estimated, I imputed, X international org.)
--      b: share of official figures by recent year (the latest years are the least reliable)
-- =====================================================================

-- Q19a
with top_risk as (
    select top (10) area_code, risk_score
    from {{ ref('fact_food_security_risk') }}
    order by risk_score desc
),
obs as (
    select ya.area_code, ya.item_code, ya.flag_code, cast(coalesce(ya.production_t, 0) as float) as w
    from {{ ref('fact_yield_anomaly') }} ya
    join top_risk t on t.area_code = ya.area_code
)
select
    rank() over (order by max(t.risk_score) desc) as risk_rank,
    a.area_name, i.item_name, count(*) as n_yield_years,
    round(100.0 * sum(case when o.flag_code = 'A' then o.w else 0 end) / nullif(sum(o.w), 0), 1) as pct_official,
    round(100.0 * sum(case when o.flag_code = 'E' then o.w else 0 end) / nullif(sum(o.w), 0), 1) as pct_estimated,
    round(100.0 * sum(case when o.flag_code = 'I' then o.w else 0 end) / nullif(sum(o.w), 0), 1) as pct_imputed,
    round(100.0 * sum(case when o.flag_code = 'X' then o.w else 0 end) / nullif(sum(o.w), 0), 1) as pct_international_org,
    round(100.0 * sum(case when o.flag_code is null or o.flag_code not in ('A', 'E', 'I', 'X') then o.w else 0 end)
                / nullif(sum(o.w), 0), 1) as pct_other
from obs o
join top_risk t on t.area_code = o.area_code
join {{ ref('dim_area') }} a on a.area_code = o.area_code
join {{ ref('dim_item') }} i on i.item_code = o.item_code
group by a.area_name, i.item_name
order by risk_rank, i.item_name;

-- Q19b
select
    ya.year_num, count(*) as n_pair_years,
    round(100.0 * avg(case when ya.flag_code = 'A' then 1.0 else 0 end), 1) as pct_official,
    round(100.0 * avg(case when ya.flag_code = 'E' then 1.0 else 0 end), 1) as pct_estimated,
    round(100.0 * avg(case when ya.flag_code = 'I' then 1.0 else 0 end), 1) as pct_imputed,
    round(100.0 * avg(case when ya.flag_code = 'X' then 1.0 else 0 end), 1) as pct_international_org
from {{ ref('fact_yield_anomaly') }} ya
where ya.year_num >= (select max(year_num) from {{ ref('fact_yield_anomaly') }}) - 7
group by ya.year_num
order by ya.year_num;


-- =====================================================================
-- Q20  Which findings stay the same across methods, and which depend on method choices?
--      Re-runs three headline results with alternative choices and gives a verdict.
--      The ONI file and the Nino 3.4 file use different baselines (max gap 0.66 C), so they are
--      COMPARED here, never mixed in one calculation.  RONI is not in the data (a stated limit).
--        a: rainfall sensitivity, ONI vs Nino 3.4 anomaly            (Q1)
--        b: price lag, real vs nominal YoY, ONI vs Nino 3.4          (Q12)
--        c: worst El Nino yield pairs, with / without E,I years and with / without 2023-2024 (Q2)
--      c re-uses the stored anomalies (the trend is not re-fitted per variant).
-- =====================================================================

-- Q20a
with {{ lags_cte(6) }},
{{ rain_oni_pairs() }},
{{ corr_best('rain', 'rain_pairs', 'location_id') }},
n34_pairs as (
    select pa.location_id, l.lag_months,
           cast(pa.anomaly_mm_day as float) as y,
           cast(s.sst_anomaly as float)     as x
    from {{ ref('fact_precip_anomaly') }} pa
    join {{ ref('dim_date') }} d on d.date_key = pa.date_key
    cross join lags l
    join {{ ref('dim_date') }} d2 on d2.month_start = dateadd(month, -l.lag_months, d.month_start)
    join {{ ref('fact_nino_region_sst') }} s on s.date_key = d2.date_key
    join {{ ref('dim_nino_region') }} r on r.region_id = s.region_id and r.region_code = 'NINO3.4'
    where pa.anomaly_mm_day is not null and s.sst_anomaly is not null
),
{{ corr_best('n34', 'n34_pairs', 'location_id') }}
select
    loc.location_name,
    ob.lag_months as lag_oni,    round(ob.r_value, 3) as r_oni,
    nb.lag_months as lag_nino34, round(nb.r_value, 3) as r_nino34,
    case when sign(ob.r_value) <> sign(nb.r_value) then 'Method-dependent (sign flips)'
         when abs(ob.lag_months - nb.lag_months) <= 1 and abs(ob.r_value - nb.r_value) <= 0.1 then 'Robust'
         else 'Partly robust (same sign, lag or size differs)' end as verdict
from best_rain ob
join best_n34 nb on nb.location_id = ob.location_id and nb.rk = 1
join {{ ref('dim_location') }} loc on loc.location_id = ob.location_id
where ob.rk = 1
order by loc.location_name;

-- Q20b
with {{ lags_cte(12) }},
{{ price_oni_pairs('pp_real', 'yoy_real_pct') }},
{{ price_oni_pairs('pp_nom', 'yoy_nominal_pct') }},
pp_n34 as (
    select fy.food_index_id, l.lag_months,
           cast(fy.yoy_real_pct as float) as y,
           cast(s.sst_anomaly as float)   as x
    from {{ ref('fact_food_price_yoy') }} fy
    join {{ ref('dim_date') }} d on d.date_key = fy.date_key
    cross join lags l
    join {{ ref('dim_date') }} d2 on d2.month_start = dateadd(month, -l.lag_months, d.month_start)
    join {{ ref('fact_nino_region_sst') }} s on s.date_key = d2.date_key
    join {{ ref('dim_nino_region') }} r on r.region_id = s.region_id and r.region_code = 'NINO3.4'
    where fy.yoy_real_pct is not null and s.sst_anomaly is not null
),
{{ corr_best('real', 'pp_real', 'food_index_id') }},
{{ corr_best('nom', 'pp_nom', 'food_index_id') }},
{{ corr_best('n34', 'pp_n34', 'food_index_id') }}
select
    fi.index_code,
    br.lag_months as lag_real_oni,    round(br.r_value, 3) as r_real_oni,
    bn.lag_months as lag_nominal_oni, round(bn.r_value, 3) as r_nominal_oni,
    b3.lag_months as lag_real_nino34, round(b3.r_value, 3) as r_real_nino34,
    case when sign(br.r_value) <> sign(bn.r_value) or sign(br.r_value) <> sign(b3.r_value)
              then 'Method-dependent (sign flips)'
         when abs(br.lag_months - bn.lag_months) <= 2 and abs(br.lag_months - b3.lag_months) <= 2
              and abs(br.r_value - bn.r_value) <= 0.1 and abs(br.r_value - b3.r_value) <= 0.1 then 'Robust'
         else 'Partly robust (same sign, lag or size differs)' end as verdict
from best_real br
join best_nom bn on bn.food_index_id = br.food_index_id and bn.rk = 1
join best_n34 b3 on b3.food_index_id = br.food_index_id and b3.rk = 1
join {{ ref('dim_food_index') }} fi on fi.food_index_id = br.food_index_id
where br.rk = 1
order by fi.food_index_id;

-- Q20c
with {{ params_cte() }},
base as (
    select ya.area_code, ya.item_code, ya.year_num, cast(ya.anomaly_pct as float) as anomaly_pct,
           ya.flag_code, ph.phase_code
    from {{ ref('fact_yield_anomaly') }} ya
    join {{ ref('fact_enso_year') }} ey on ey.year_num = ya.year_num
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = ey.year_phase_id
    where ya.anomaly_pct is not null
),
variants as (
    select area_code, item_code,
           avg(case when phase_code = 'elnino' then anomaly_pct end)                                  as el_all,
           sum(case when phase_code = 'elnino' then 1 else 0 end)                                     as n_all,
           avg(case when phase_code = 'elnino' and flag_code = 'A' then anomaly_pct end)              as el_official,
           sum(case when phase_code = 'elnino' and flag_code = 'A' then 1 else 0 end)                 as n_official,
           avg(case when phase_code = 'elnino' and year_num < {{ drop_from_year }} then anomaly_pct end) as el_early,
           sum(case when phase_code = 'elnino' and year_num < {{ drop_from_year }} then 1 else 0 end)    as n_early
    from base
    group by area_code, item_code
),
rk_all as (
    select v.area_code, v.item_code, v.el_all as v_all, row_number() over (order by v.el_all) as rk
    from variants v cross join p where v.n_all >= p.min_years
),
rk_official as (
    select v.area_code, v.item_code, v.el_official as v_var, row_number() over (order by v.el_official) as rk
    from variants v cross join p where v.n_official >= p.min_years
),
rk_early as (
    select v.area_code, v.item_code, v.el_early as v_var, row_number() over (order by v.el_early) as rk
    from variants v cross join p where v.n_early >= p.min_years
),
cmp as (
    select 'only official (flag A) years' as variant,
           (select count(*) from rk_all)      as n_pairs_baseline,
           (select count(*) from rk_official) as n_pairs_variant,
           (select count(*) from rk_all a join rk_official b on b.area_code = a.area_code and b.item_code = a.item_code
             where a.rk <= {{ top_n }} and b.rk <= {{ top_n }}) as top_overlap,
           (select count(*) from rk_all a join rk_official b on b.area_code = a.area_code and b.item_code = a.item_code
             where sign(a.v_all) = sign(b.v_var)) as same_sign_pairs,
           (select count(*) from rk_all a join rk_official b on b.area_code = a.area_code and b.item_code = a.item_code) as common_pairs
    union all
    select 'without years from {{ drop_from_year }}',
           (select count(*) from rk_all),
           (select count(*) from rk_early),
           (select count(*) from rk_all a join rk_early b on b.area_code = a.area_code and b.item_code = a.item_code
             where a.rk <= {{ top_n }} and b.rk <= {{ top_n }}),
           (select count(*) from rk_all a join rk_early b on b.area_code = a.area_code and b.item_code = a.item_code
             where sign(a.v_all) = sign(b.v_var)),
           (select count(*) from rk_all a join rk_early b on b.area_code = a.area_code and b.item_code = a.item_code)
)
select
    variant, n_pairs_baseline, n_pairs_variant,
    top_overlap                                           as worst_{{ top_n }}_pairs_in_common,
    round(100.0 * same_sign_pairs / nullif(common_pairs, 0), 1) as same_sign_pct,
    case when top_overlap >= 0.7 * {{ top_n }} and 1.0 * same_sign_pairs / nullif(common_pairs, 0) >= 0.9 then 'Robust'
         when top_overlap >= 0.4 * {{ top_n }} then 'Partly robust'
         else 'Method-dependent' end                      as verdict
from cmp;


-- =====================================================================
-- F. ENSO AND RAINFALL
-- =====================================================================

-- =====================================================================
-- Q21  How many El Nino and La Nina events since 1950, how long, how strong?
--      a: event list   b: KPI summary by phase (counts by intensity included)
-- =====================================================================

-- Q21a
select
    e.event_id, ph.phase_name,
    ds.month_start as start_month, de.month_start as end_month,
    e.months as duration_months,
    round(e.peak_anom_3m, 2) as peak_oni,
    it.label as intensity
from {{ ref('dim_enso_event') }} e
join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_id
join {{ ref('dim_intensity') }} it on it.intensity_id = e.intensity_id
join {{ ref('dim_date') }} ds on ds.date_key = e.start_date_key
join {{ ref('dim_date') }} de on de.date_key = e.end_date_key
order by e.event_id;

-- Q21b
select
    ph.phase_name,
    count(*)                                              as n_events,
    round(avg(cast(e.months as float)), 1)                as avg_duration_months,
    max(e.months)                                         as longest_event_months,
    round(max(abs(e.peak_anom_3m)), 2)                    as strongest_peak_abs_oni,
    sum(case when it.label = 'Weak'        then 1 else 0 end) as n_weak,
    sum(case when it.label = 'Moderate'    then 1 else 0 end) as n_moderate,
    sum(case when it.label = 'Strong'      then 1 else 0 end) as n_strong,
    sum(case when it.label = 'Very strong' then 1 else 0 end) as n_very_strong
from {{ ref('dim_enso_event') }} e
join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_id
join {{ ref('dim_intensity') }} it on it.intensity_id = e.intensity_id
group by ph.phase_id, ph.phase_name
order by ph.phase_id;


-- =====================================================================
-- Q22  How strong is the 2026 event versus past events, and when might it peak?
--      Nino 3.4 monthly anomaly (Nino file): 2026 against the strongest past years.
--      a: month-by-month table (official phase from the events file shown where it exists)
--      b: peak month and size per year (the earlier events peaked in Nov-Dec)
-- =====================================================================

-- Q22a
with {{ n34_cte() }},
official as (
    select d.month_num, ph.phase_code as official_phase
    from {{ ref('fact_enso_monthly') }} e
    join {{ ref('dim_date') }} d on d.date_key = e.date_key
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_event_id
    where d.year_num = {{ current_year }}
),
wide as (
    select month_num, min(month_name) as month_name
           {% for y in compare_years + [current_year] %}
           , max(case when year_num = {{ y }} then anom end) as y{{ y }}
           {% endfor %}
    from n34
    group by month_num
)
select
    w.month_num, w.month_name,
    {% for y in compare_years %}round(w.y{{ y }}, 2) as y{{ y }},
    {% endfor %}
    round(w.y{{ current_year }}, 2) as y{{ current_year }},
    round(w.y{{ current_year }} - (select max(t.v) from (values {% for y in compare_years %}(w.y{{ y }}){{ "," if not loop.last }}{% endfor %}) as t(v)), 2)
        as current_minus_strongest_past,
    o.official_phase as official_phase_current_year
from wide w
left join official o on o.month_num = w.month_num
order by w.month_num;

-- Q22b
with {{ n34_cte() }},
peaks as (
    select year_num, month_num, month_name, anom,
           row_number() over (partition by year_num order by anom desc) as rk,
           max(month_num) over (partition by year_num)                  as last_month_in_data
    from n34
    where year_num in ({% for y in compare_years + [current_year] %}{{ y }}{{ "," if not loop.last }}{% endfor %})
)
select year_num, month_name as peak_month, month_num as peak_month_number,
       round(anom, 2) as peak_anomaly, last_month_in_data
from peaks
where rk = 1
order by year_num;


-- =====================================================================
-- Q23  Which Nino region best explains local rainfall (e.g. Nino 1+2 for Peru)?
--      r between rainfall anomaly and each region's SST anomaly, lags 0-6; best lag per region,
--      regions ranked per location.  Rain starts in 2000.
-- =====================================================================
with {{ lags_cte(6) }},
reg_pairs as (
    select pa.location_id, r.region_code, l.lag_months,
           cast(pa.anomaly_mm_day as float) as y,
           cast(s.sst_anomaly as float)     as x
    from {{ ref('fact_precip_anomaly') }} pa
    join {{ ref('dim_date') }} d on d.date_key = pa.date_key
    cross join lags l
    join {{ ref('dim_date') }} d2 on d2.month_start = dateadd(month, -l.lag_months, d.month_start)
    join {{ ref('fact_nino_region_sst') }} s on s.date_key = d2.date_key
    join {{ ref('dim_nino_region') }} r on r.region_id = s.region_id
    where pa.anomaly_mm_day is not null and s.sst_anomaly is not null
),
{{ corr_best('reg', 'reg_pairs', 'location_id, region_code') }},
top_lag as (
    select location_id, region_code, lag_months, n_months, r_value
    from best_reg
    where rk = 1
)
select
    loc.location_name, t.region_code, t.lag_months as best_lag_months,
    round(t.r_value, 3) as r_value,
    rank() over (partition by t.location_id order by abs(t.r_value) desc) as region_rank_for_location,
    case when rank() over (partition by t.location_id order by abs(t.r_value) desc) = 1 then 1 else 0 end as is_best_region
from top_lag t
join {{ ref('dim_location') }} loc on loc.location_id = t.location_id
order by loc.location_name, region_rank_for_location;


-- =====================================================================
-- Q24  Which countries get wetter and which drier during El Nino and La Nina?
--      Rainfall anomaly by event phase, for the whole year (ALL) and by season (DJF MAM JJA SON).
--      pct = anomaly as % of the normal; t = mean / (sd / sqrt(n)).  |t| >= {{ rain_signal_t }} is called wetter/drier,
--      otherwise "no clear signal".  n months shown so thin groups are visible.
-- =====================================================================
with by_group as (
    select pa.location_id, s.season, ph.phase_code,
           count(*)                                    as n_months,
           avg(cast(pa.anomaly_mm_day as float))       as mean_anom,
           stdev(cast(pa.anomaly_mm_day as float))     as sd_anom,
           sum(cast(pa.anomaly_mm_day as float))       as sum_anom,
           sum(cast(pa.normal_mm_day as float))        as sum_normal
    from {{ ref('fact_precip_anomaly') }} pa
    join {{ ref('dim_date') }} d on d.date_key = pa.date_key
    join {{ ref('fact_enso_monthly') }} e on e.date_key = pa.date_key
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_event_id
    cross apply (values
        ('ALL'),
        (case when d.month_num in (12, 1, 2) then 'DJF'
              when d.month_num in (3, 4, 5)  then 'MAM'
              when d.month_num in (6, 7, 8)  then 'JJA'
              else 'SON' end)
    ) as s(season)
    where pa.anomaly_mm_day is not null and ph.phase_code in ('elnino', 'lanina', 'neutral')
    group by pa.location_id, s.season, ph.phase_code
),
wide as (
    select location_id, season,
           max(case when phase_code = 'elnino'  then n_months end) as n_el,
           max(case when phase_code = 'elnino'  then mean_anom end) as anom_el,
           max(case when phase_code = 'elnino'  then 100.0 * sum_anom / nullif(sum_normal, 0) end) as pct_el,
           max(case when phase_code = 'elnino'  then mean_anom / nullif(sd_anom / sqrt(cast(n_months as float)), 0) end) as t_el,
           max(case when phase_code = 'lanina'  then n_months end) as n_la,
           max(case when phase_code = 'lanina'  then mean_anom end) as anom_la,
           max(case when phase_code = 'lanina'  then 100.0 * sum_anom / nullif(sum_normal, 0) end) as pct_la,
           max(case when phase_code = 'lanina'  then mean_anom / nullif(sd_anom / sqrt(cast(n_months as float)), 0) end) as t_la,
           max(case when phase_code = 'neutral' then mean_anom end) as anom_neutral
    from by_group
    group by location_id, season
)
select
    loc.location_name, w.season,
    w.n_el as n_el_nino_months, round(w.anom_el, 3) as el_nino_anom_mm_day,
    round(w.pct_el, 1) as el_nino_pct_of_normal, round(w.t_el, 2) as el_nino_t,
    case when w.t_el >= {{ rain_signal_t }} then 'wetter' when w.t_el <= -{{ rain_signal_t }} then 'drier' else 'no clear signal' end as el_nino_direction,
    w.n_la as n_la_nina_months, round(w.anom_la, 3) as la_nina_anom_mm_day,
    round(w.pct_la, 1) as la_nina_pct_of_normal, round(w.t_la, 2) as la_nina_t,
    case when w.t_la >= {{ rain_signal_t }} then 'wetter' when w.t_la <= -{{ rain_signal_t }} then 'drier' else 'no clear signal' end as la_nina_direction,
    round(w.anom_neutral, 3) as neutral_anom_mm_day
from wide w
join {{ ref('dim_location') }} loc on loc.location_id = w.location_id
order by loc.location_name,
         case w.season when 'ALL' then 0 when 'DJF' then 1 when 'MAM' then 2 when 'JJA' then 3 else 4 end;


-- =====================================================================
-- G. PRICES (ADDED QUESTIONS)
-- =====================================================================

-- =====================================================================
-- Q25  Are food prices already high before the 2026 El Nino effects arrive?
--      Latest REAL index of each sub-index: its percentile in its own history (0-100) and
--      its level against the level at the start of every El Nino event since 1990.
-- =====================================================================
with latest as (
    select max(date_key) as date_key from {{ ref('fact_food_price_monthly') }}
),
hist as (
    select p.date_key, p.food_index_id, p.real_index,
           percent_rank() over (partition by p.food_index_id order by p.real_index) as pctl
    from {{ ref('fact_food_price_monthly') }} p
),
starts as (
    select e.event_id, e.start_date_key, it.label as intensity, pm.food_index_id, pm.real_index as real_at_start
    from {{ ref('dim_enso_event') }} e
    join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_id and ph.phase_code = 'elnino'
    join {{ ref('dim_intensity') }} it on it.intensity_id = e.intensity_id
    join {{ ref('fact_food_price_monthly') }} pm on pm.date_key = e.start_date_key
    where e.start_date_key >= 19900101
)
select
    fi.index_code,
    dl.month_start                         as latest_month,
    round(h.real_index, 1)                 as latest_real_index,
    round(100.0 * h.pctl, 0)               as latest_percentile_in_history,
    ds.month_start                         as event_start_month,
    st.intensity                           as event_intensity,
    round(st.real_at_start, 1)             as real_index_at_event_start,
    round((h.real_index / nullif(st.real_at_start, 0) - 1) * 100, 1) as latest_vs_event_start_pct
from hist h
join latest l on l.date_key = h.date_key
join {{ ref('dim_date') }} dl on dl.date_key = h.date_key
join {{ ref('dim_food_index') }} fi on fi.food_index_id = h.food_index_id
left join starts st on st.food_index_id = h.food_index_id
left join {{ ref('dim_date') }} ds on ds.date_key = st.start_date_key
order by fi.food_index_id, ds.month_start;


-- =====================================================================
-- Q26  Which price spikes happened during ENSO events and which did not?
--      Spike month = real index at least {{ spike_sd }} SD above its trailing {{ spike_window }}-month mean (needs {{ spike_min_history }}+
--      months of history).  Consecutive spike months form one episode; each episode is matched to
--      the event phase (events file) at its peak month and across its months.
-- =====================================================================
with monthly as (
    select fi.index_code, p.food_index_id, d.month_start, p.date_key,
           cast(p.real_index as float) as real_index,
           sum(cast(p.real_index as float)) over (partition by p.food_index_id order by d.month_start
               rows between {{ spike_window }} preceding and 1 preceding) as s1,
           sum(cast(p.real_index as float) * cast(p.real_index as float)) over (partition by p.food_index_id order by d.month_start
               rows between {{ spike_window }} preceding and 1 preceding) as s2,
           count(p.real_index) over (partition by p.food_index_id order by d.month_start
               rows between {{ spike_window }} preceding and 1 preceding) as n_hist
    from {{ ref('fact_food_price_monthly') }} p
    join {{ ref('dim_date') }} d on d.date_key = p.date_key
    join {{ ref('dim_food_index') }} fi on fi.food_index_id = p.food_index_id
),
scored as (
    select m.index_code, m.food_index_id, m.month_start, m.date_key, m.real_index,
           m.s1 / nullif(m.n_hist, 0) as ma,
           sqrt(case when m.n_hist > 1 and (m.s2 - m.s1 * m.s1 / m.n_hist) > 0
                     then (m.s2 - m.s1 * m.s1 / m.n_hist) / (m.n_hist - 1) end) as sd
    from monthly m
    where m.n_hist >= {{ spike_min_history }}
),
spikes as (
    select s.index_code, s.food_index_id, s.month_start, s.real_index,
           (s.real_index - s.ma) / s.sd as z,
           coalesce(ph.phase_code, 'unknown') as phase_code
    from scored s
    left join {{ ref('fact_enso_monthly') }} e on e.date_key = s.date_key
    left join {{ ref('dim_enso_phase') }} ph on ph.phase_id = e.phase_event_id
    where s.sd > 0 and s.real_index - s.ma >= {{ spike_sd }} * s.sd
),
isl as (
    select sp.*,
           datediff(month, '1990-01-01', sp.month_start)
             - row_number() over (partition by sp.food_index_id order by sp.month_start) as grp
    from spikes sp
),
isl2 as (
    select i.*, row_number() over (partition by i.food_index_id, i.grp order by i.real_index desc) as rn
    from isl i
)
select
    index_code,
    min(month_start)                                          as spike_start,
    max(month_start)                                          as spike_end,
    count(*)                                                  as spike_months,
    max(case when rn = 1 then month_start end)                as peak_month,
    round(max(case when rn = 1 then real_index end), 1)       as peak_real_index,
    round(max(case when rn = 1 then z end), 2)                as peak_z,
    max(case when rn = 1 then phase_code end)                 as phase_at_peak,
    sum(case when phase_code = 'elnino' then 1 else 0 end)    as months_in_el_nino,
    sum(case when phase_code = 'lanina' then 1 else 0 end)    as months_in_la_nina,
    case when sum(case when phase_code in ('elnino', 'lanina') then 1 else 0 end) > 0
         then 'during an ENSO event' else 'outside ENSO events' end as enso_link
from isl2
group by index_code, food_index_id, grp
order by food_index_id, spike_start;


-- =====================================================================
-- Q27  Do major producers fail at the same time during El Nino?
--      A pair "fails" in a year if its yield anomaly is at or below -{{ fail_sd_multiple }} SD (fixed in advance).
--      a: per year, pairs failing (count and % of production), coloured by year phase
--      b: the same averaged over El Nino / La Nina / Neutral years
--      Drill down into 1997 / 2015 / 2023 by filtering (a).
-- =====================================================================

-- Q27a
with {{ fail_ctes(fail_sd_multiple) }}
select year_num, phase_name, n_pairs, n_failed,
       round(pct_pairs_failed, 1) as pct_pairs_failed,
       round(pct_production_failed, 1) as pct_production_failed
from yearly
order by year_num;

-- Q27b
with {{ fail_ctes(fail_sd_multiple) }}
select phase_name,
       count(*)                              as n_years,
       round(avg(cast(n_failed as float)), 1) as avg_pairs_failed,
       round(avg(pct_pairs_failed), 1)       as avg_pct_pairs_failed,
       round(avg(pct_production_failed), 1)  as avg_pct_production_failed
from yearly
group by phase_name
order by phase_name;


-- =====================================================================
-- H. EGYPT AND EARLY WARNING
-- =====================================================================

-- =====================================================================
-- Q28  How exposed is Egypt itself?
--      a: Egypt's yield stability and El Nino / La Nina response against all countries growing the
--         same crop (stability_pctl 0 = the most stable country, 1 = the most volatile;
--         el_nino_pctl 0 = the worst El Nino response)
--      b: year-by-year anomalies with the ENSO phase
--      Egypt's own rain is ~0 and Nile / Ethiopian rainfall is not in the data: no water mechanism.
-- =====================================================================

-- Q28a
with ranked as (
    select s.area_code, s.item_code, a.area_name, i.item_name,
           s.std_anom_pct, s.mean_anom_el_nino_pct, s.mean_anom_la_nina_pct,
           s.n_el_nino, s.n_la_nina, s.official_share,
           percent_rank() over (partition by s.item_code order by s.std_anom_pct)          as stability_pctl,
           rank()         over (partition by s.item_code order by s.std_anom_pct)          as stability_rank,
           count(*)       over (partition by s.item_code)                                  as n_countries,
           percent_rank() over (partition by s.item_code order by s.mean_anom_el_nino_pct) as el_nino_pctl
    from {{ ref('fact_yield_sensitivity') }} s
    join {{ ref('dim_area') }} a on a.area_code = s.area_code and a.is_aggregate = 0
    join {{ ref('dim_item') }} i on i.item_code = s.item_code
    where s.std_anom_pct is not null and s.item_code in ({{ egypt_items }})
)
select
    item_name,
    round(std_anom_pct, 2) as egypt_std_anomaly_pct,
    stability_rank, n_countries,
    round(stability_pctl, 2) as stability_pctl,
    round(mean_anom_el_nino_pct, 2) as egypt_mean_anom_el_nino_pct, n_el_nino,
    round(el_nino_pctl, 2) as el_nino_pctl,
    round(mean_anom_la_nina_pct, 2) as egypt_mean_anom_la_nina_pct, n_la_nina,
    round(official_share, 3) as official_share
from ranked
where area_name = 'Egypt'
order by item_name;

-- Q28b
select
    i.item_name, ya.year_num,
    round(ya.anomaly_pct, 2) as yield_anomaly_pct,
    ph.phase_name as year_phase, it.label as year_intensity, ya.flag_code
from {{ ref('fact_yield_anomaly') }} ya
join {{ ref('dim_area') }} a on a.area_code = ya.area_code and a.area_name = 'Egypt'
join {{ ref('dim_item') }} i on i.item_code = ya.item_code
left join {{ ref('fact_enso_year') }} ey on ey.year_num = ya.year_num
left join {{ ref('dim_enso_phase') }} ph on ph.phase_id = ey.year_phase_id
left join {{ ref('dim_intensity') }} it on it.intensity_id = ey.intensity_id
where ya.item_code in ({{ egypt_items }})
order by i.item_name, ya.year_num;


-- =====================================================================
-- Q29  When should each commodity be watched after a 2026-style event?
--      Turns the lags of Q9 / Q12 into a calendar from the onset of the current event.
--      Onset = first month (centred) of the latest unbroken El Nino run in the ONI series
--      (or manual_onset above).  Rain and price windows = best lag +/- {{ band_months }} months; yield
--      window = the year (same or next) whose ONI link is stronger on average (Q9c).
--      Lags are weak (|r| mostly < 0.4): read each row as a RANGE and as a trend + analogue view,
--      not a forecast.
-- =====================================================================
with {{ lags_cte(12) }},
{{ rain_oni_pairs() }},
{{ corr_best('rain', 'rain_pairs', 'location_id') }},
{{ price_oni_pairs('price_pairs', 'yoy_real_pct') }},
{{ corr_best('price', 'price_pairs', 'food_index_id') }},
{{ yield_lag_ctes(min_pair_years) }},
onset as (
    {% if manual_onset %}
    select cast('{{ manual_onset }}' as date) as onset_month
    {% else %}
    select dateadd(month, 1, min(m.month_start)) as onset_month
    from {{ ref('slv_enso_monthly') }} m
    where m.anomaly_3m is not null
      and m.month_start > (select coalesce(max(x.month_start), cast('1900-01-01' as date))
                           from {{ ref('slv_enso_monthly') }} x
                           where x.anomaly_3m is not null and x.phase_3m_code <> 'elnino')
    {% endif %}
),
yield_part as (
    select i.item_name,
           avg(abs(pl.r_same_year)) as mean_abs_same,
           avg(abs(pl.r_next_year)) as mean_abs_next
    from pair_lag pl
    join {{ ref('dim_item') }} i on i.item_code = pl.item_code
    group by i.item_name
),
timeline as (
    select 'Rainfall' as link_group, loc.location_name as commodity,
           b.lag_months as best_lag_months, b.r_value as r_value,
           dateadd(month, case when b.lag_months - {{ band_months }} < 0 then 0 else b.lag_months - {{ band_months }} end, o.onset_month) as watch_from,
           dateadd(month, b.lag_months + {{ band_months }}, o.onset_month) as watch_to
    from best_rain b
    join {{ ref('dim_location') }} loc on loc.location_id = b.location_id
    cross join onset o
    where b.rk = 1
    union all
    select 'Price (real YoY)', fi.index_code, b.lag_months, b.r_value,
           dateadd(month, case when b.lag_months - {{ band_months }} < 0 then 0 else b.lag_months - {{ band_months }} end, o.onset_month),
           dateadd(month, b.lag_months + {{ band_months }}, o.onset_month)
    from best_price b
    join {{ ref('dim_food_index') }} fi on fi.food_index_id = b.food_index_id
    cross join onset o
    where b.rk = 1
    union all
    select 'Yield (annual)', y.item_name, cast(null as int),
           case when y.mean_abs_next > y.mean_abs_same then y.mean_abs_next else y.mean_abs_same end,
           datefromparts(year(o.onset_month) + case when y.mean_abs_next > y.mean_abs_same then 1 else 0 end, 1, 1),
           datefromparts(year(o.onset_month) + case when y.mean_abs_next > y.mean_abs_same then 1 else 0 end, 12, 1)
    from yield_part y
    cross join onset o
)
select
    t.link_group, t.commodity, o.onset_month,
    t.best_lag_months,
    round(t.r_value, 3) as r_value,
    t.watch_from, t.watch_to,
    case when abs(t.r_value) < 0.2 then 'weak link (|r| < 0.2): indicative only' else '' end as note
from timeline t
cross join onset o
order by t.link_group, t.watch_from, t.commodity;


-- =====================================================================
-- I. DATA QUALITY
-- =====================================================================

-- =====================================================================
-- Q30  Which country-crop series are complete and reliable enough to use?
--      Primary-crop YIELD series, 1982-2024 (analysis_parameters).  Counts valid years, missing-value
--      rows (flag M), zeros (a zero in FAOSTAT is an official figure, not a gap), the longest gap
--      and the official share.
--        passes_basic         = >= {{ min_pair_years }} valid years, longest gap <= max_gap_years, zero share <= max_zero_share
--        passes_strict_silver = the stricter rule already stored in slv_series_quality (also caps missing share)
--      a: one row per pair   b: pass rate per crop
-- =====================================================================

-- Q30a
with {{ params_cte() }},
{{ quality_ctes(min_pair_years) }}
select
    area_name, item_name, first_year, last_year, n_valid, expected_years,
    n_rows_with_missing_value, n_zero, max_gap_years,
    round(official_share, 3) as official_share,
    passes_basic, passes_strict_silver
from quality
order by item_name, area_name;

-- Q30b
with {{ params_cte() }},
{{ quality_ctes(min_pair_years) }}
select
    item_name,
    count(*)                                               as n_pairs,
    sum(passes_basic)                                      as n_pass_basic,
    round(100.0 * sum(passes_basic) / count(*), 1)         as pct_pass_basic,
    sum(coalesce(passes_strict_silver, 0))                 as n_pass_strict_silver,
    round(100.0 * sum(coalesce(passes_strict_silver, 0)) / count(*), 1) as pct_pass_strict_silver
from quality
group by item_name
order by item_name;
