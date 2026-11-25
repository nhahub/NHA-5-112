{#-
  GOLD LAYER HEALTH CHECK  (T-SQL, one result set)
  ---------------------------------------------------------------------------
  Run it (from this dbt project folder, with the venv active and `dbt debug` OK):

      dbt compile --select test       # writes target/compiled/ENSO/analyses/test.sql  (plain T-SQL)
                                      # -> open that file in SSMS / Azure Data Studio / VS Code SQL and run it
      dbt show --select test --limit 200   # optional: may fail on SQL Server, because the query uses
                                           # WITH ... and ORDER BY, which T-SQL does not allow inside a wrapper

  Result: first row = SUMMARY ('ALL PASS' or 'n FAILED'); then every check as
          check_group | check_name | actual | min_ok | max_ok | status (PASS / FAIL)
  FAIL rows come first. A check passes when  min_ok <= actual <= max_ok  (max_ok empty = no upper limit).

  Groups: 1 not_empty | 2 dimension_size | 3 silver_vs_gold | 4 known_counts | 5 events |
          6 unique_keys | 7 foreign_keys | 8 sanity
  "known_counts" and the dimension sizes are the numbers of the CSV files used in the project
  (Nino 1982-01..2026-10, GPCP 10 points 2000-01..2026-06, FFPI 1990-01..2026-09, events 1950-01..2026-06).
  If you refresh the raw files and the series get longer, update those expected values.
-#}

{% set all_tables = [
    'dim_area','dim_date','dim_element','dim_enso_event','dim_enso_phase','dim_flag','dim_food_index',
    'dim_intensity','dim_item','dim_location','dim_nino_region','dim_year',
    'fact_crop_production','fact_enso_monthly','fact_enso_year','fact_food_price_annual',
    'fact_food_price_monthly','fact_food_price_yoy','fact_nino_region_sst','fact_precipitation',
    'fact_precip_anomaly','fact_yield_anomaly','fact_yield_sensitivity','fact_food_security_risk'
] %}

{# (dimension, expected rows) #}
{% set dim_sizes = [
    ('dim_date', 972), ('dim_year', 81), ('dim_enso_phase', 4), ('dim_intensity', 5),
    ('dim_nino_region', 4), ('dim_location', 10), ('dim_food_index', 6), ('dim_enso_event', 45)
] %}

{# (gold table, silver table) must have the same number of rows #}
{% set reconcile = [
    ('fact_enso_monthly', 'slv_enso_monthly'), ('fact_precipitation', 'slv_precipitation'),
    ('fact_nino_region_sst', 'slv_nino_region_sst'), ('fact_food_price_monthly', 'slv_food_price_monthly'),
    ('fact_food_price_annual', 'slv_food_price_annual'), ('fact_crop_production', 'slv_crop_production')
] %}

{# (gold table, expected rows from the raw files) #}
{% set known = [
    ('fact_enso_monthly', 918), ('fact_precipitation', 3180),
    ('fact_nino_region_sst', 2152), ('fact_food_price_monthly', 2652), ('fact_food_price_yoy', 2652)
] %}

{# (child table, fk column, parent table, parent column, only_when_not_null) -> rows without a parent must be 0 #}
{% set fks = [
    ('fact_enso_monthly', 'date_key', 'dim_date', 'date_key', 0),
    ('fact_enso_monthly', 'phase_event_id', 'dim_enso_phase', 'phase_id', 0),
    ('fact_enso_monthly', 'event_id', 'dim_enso_event', 'event_id', 1),
    ('dim_enso_event', 'phase_id', 'dim_enso_phase', 'phase_id', 0),
    ('dim_enso_event', 'intensity_id', 'dim_intensity', 'intensity_id', 0),
    ('fact_nino_region_sst', 'date_key', 'dim_date', 'date_key', 0),
    ('fact_nino_region_sst', 'region_id', 'dim_nino_region', 'region_id', 0),
    ('fact_precipitation', 'date_key', 'dim_date', 'date_key', 0),
    ('fact_precipitation', 'location_id', 'dim_location', 'location_id', 0),
    ('dim_location', 'area_code', 'dim_area', 'area_code', 1),
    ('fact_food_price_monthly', 'date_key', 'dim_date', 'date_key', 0),
    ('fact_food_price_monthly', 'food_index_id', 'dim_food_index', 'food_index_id', 0),
    ('fact_food_price_annual', 'year_num', 'dim_year', 'year_num', 0),
    ('fact_food_price_annual', 'food_index_id', 'dim_food_index', 'food_index_id', 0),
    ('fact_crop_production', 'area_code', 'dim_area', 'area_code', 0),
    ('fact_crop_production', 'item_code', 'dim_item', 'item_code', 0),
    ('fact_crop_production', 'element_code', 'dim_element', 'element_code', 0),
    ('fact_crop_production', 'flag_code', 'dim_flag', 'flag_code', 1),
    ('fact_enso_year', 'year_num', 'dim_year', 'year_num', 0),
    ('fact_enso_year', 'year_phase_id', 'dim_enso_phase', 'phase_id', 0),
    ('fact_precip_anomaly', 'location_id', 'dim_location', 'location_id', 0),
    ('fact_yield_anomaly', 'area_code', 'dim_area', 'area_code', 0),
    ('fact_yield_anomaly', 'item_code', 'dim_item', 'item_code', 0),
    ('fact_yield_sensitivity', 'area_code', 'dim_area', 'area_code', 0),
    ('fact_food_security_risk', 'area_code', 'dim_area', 'area_code', 0)
] %}

{# (table, comma-separated key columns) -> number of duplicated keys must be 0 #}
{% set keys = [
    ('fact_enso_monthly', 'date_key'),
    ('dim_enso_event', 'event_id'),
    ('fact_nino_region_sst', 'date_key, region_id'),
    ('fact_precipitation', 'date_key, location_id'),
    ('fact_food_price_monthly', 'date_key, food_index_id'),
    ('fact_food_price_annual', 'year_num, food_index_id'),
    ('fact_crop_production', 'area_code, item_code, element_code, year_num'),
    ('fact_yield_anomaly', 'area_code, item_code, year_num'),
    ('fact_yield_sensitivity', 'area_code, item_code'),
    ('fact_food_security_risk', 'area_code')
] %}

with checks as (

    -- 1. every gold table has rows
    {% for t in all_tables %}
    select '1 not_empty' as check_group, '{{ t }} has rows' as check_name,
           cast(count(*) as float) as actual, cast(1 as float) as min_ok, cast(null as float) as max_ok
    from {{ ref(t) }}
    union all
    {% endfor %}

    -- 2. dimensions have the expected size
    {% for t, n in dim_sizes %}
    select '2 dimension_size', '{{ t }} = {{ n }} rows', cast(count(*) as float), {{ n }}, {{ n }}
    from {{ ref(t) }}
    union all
    {% endfor %}

    -- 3. gold facts have exactly the rows of their silver source
    {% for g, s in reconcile %}
    select '3 silver_vs_gold', '{{ g }} rows = {{ s }} rows', cast((select count(*) from {{ ref(g) }}) as float),
           cast((select count(*) from {{ ref(s) }}) as float), cast((select count(*) from {{ ref(s) }}) as float)
    union all
    {% endfor %}

    -- 4. row counts known from the raw CSV files
    {% for t, n in known %}
    select '4 known_counts', '{{ t }} = {{ n }} rows', cast(count(*) as float), {{ n }}, {{ n }}
    from {{ ref(t) }}
    union all
    {% endfor %}

    -- 5. ENSO events
    select '5 events', 'El Nino events = 25', cast(count(*) as float), 25, 25
    from {{ ref('dim_enso_event') }} e join {{ ref('dim_enso_phase') }} p on p.phase_id = e.phase_id
    where p.phase_code = 'elnino'
    union all
    select '5 events', 'La Nina events = 20', cast(count(*) as float), 20, 20
    from {{ ref('dim_enso_event') }} e join {{ ref('dim_enso_phase') }} p on p.phase_id = e.phase_id
    where p.phase_code = 'lanina'
    union all
    select '5 events', 'shortest event >= 5 months', cast(min(months) as float), 5, null
    from {{ ref('dim_enso_event') }}
    union all
    select '5 events', 'months tagged with an event = sum of event months',
           cast((select count(*) from {{ ref('fact_enso_monthly') }} where event_id is not null) as float),
           cast((select sum(months) from {{ ref('dim_enso_event') }}) as float),
           cast((select sum(months) from {{ ref('dim_enso_event') }}) as float)
    union all
    select '5 events', 'months with unknown phase = 2 (no 3-month mean yet)', cast(count(*) as float), 2, 2
    from {{ ref('fact_enso_monthly') }} f join {{ ref('dim_enso_phase') }} p on p.phase_id = f.phase_event_id
    where p.phase_code = 'unknown'
    union all
    select '5 events', concat('year ', cast(y.year_num as varchar(4)), ' is ', y.expect),
           cast(case when p.phase_code = y.expect then 1 else 0 end as float), 1, 1
    from (select 2010 as year_num, 'lanina' as expect union all select 2015, 'elnino'
          union all select 2022, 'lanina' union all select 2023, 'elnino') y
    left join {{ ref('fact_enso_year') }} fy on fy.year_num = y.year_num
    left join {{ ref('dim_enso_phase') }} p on p.phase_id = fy.year_phase_id
    union all
    select '5 events', 'current year is flagged incomplete', cast(coalesce(max(is_complete), 0) as float), 0, 0
    from {{ ref('fact_enso_year') }} where year_num = 2026
    union all

    -- 6. unique keys (number of duplicated keys must be 0)
    {% for t, k in keys %}
    select '6 unique_keys', '{{ t }} ({{ k }}) has no duplicates', cast(count(*) as float), 0, 0
    from (select {{ k }} from {{ ref(t) }} group by {{ k }} having count(*) > 1) d
    union all
    {% endfor %}

    -- 7. foreign keys (rows without a parent must be 0)
    {% for c, col, p, pcol, nullable in fks %}
    select '7 foreign_keys', '{{ c }}.{{ col }} -> {{ p }}.{{ pcol }}', cast(count(*) as float), 0, 0
    from {{ ref(c) }} c left join {{ ref(p) }} p on p.{{ pcol }} = c.{{ col }}
    where p.{{ pcol }} is null {% if nullable %}and c.{{ col }} is not null{% endif %}
    union all
    {% endfor %}

    -- 8. sanity of the values
    select '8 sanity', 'ONI (anomaly_3m) inside -4..4: rows outside', cast(count(*) as float), 0, 0
    from {{ ref('fact_enso_monthly') }} where anomaly_3m < -4 or anomaly_3m > 4
    union all
    select '8 sanity', 'food price indices > 0: rows <= 0', cast(count(*) as float), 0, 0
    from {{ ref('fact_food_price_monthly') }} where nominal_index <= 0 or real_index <= 0
    union all
    select '8 sanity', 'year-over-year is empty only for the first 12 months of each index (6 x 12)',
           cast(count(*) as float), 72, 72
    from {{ ref('fact_food_price_yoy') }} where yoy_nominal_pct is null
    union all
    select '8 sanity', 'rain anomaly: largest |mean| per point-and-month (must be ~0)',
           cast(max(abs(m)) as float), 0, 0.0001
    from (select a.location_id, d.month_num, avg(a.anomaly_mm_day) as m
          from {{ ref('fact_precip_anomaly') }} a join {{ ref('dim_date') }} d on d.date_key = a.date_key
          group by a.location_id, d.month_num) x
    union all
    select '8 sanity', 'yield anomalies only inside the analysis years (rows outside)', cast(count(*) as float), 0, 0
    from {{ ref('fact_yield_anomaly') }} ya
    cross join (select max(case when param_name = 'analysis_start_year' then param_value end) as s,
                       max(case when param_name = 'analysis_end_year'   then param_value end) as e
                from {{ ref('analysis_parameters') }}) p
    where ya.year_num < p.s or ya.year_num > p.e
    union all
    select '8 sanity', 'corr(yield anomaly, ONI) inside -1..1: rows outside', cast(count(*) as float), 0, 0
    from {{ ref('fact_yield_sensitivity') }} where corr_oni_ond < -1 or corr_oni_ond > 1
    union all
    select '8 sanity', 'risk_score inside 0..100: rows outside', cast(count(*) as float), 0, 0
    from {{ ref('fact_food_security_risk') }} where risk_score < 0 or risk_score > 100
    union all
    select '8 sanity', 'countries scored with rain + yield (GPCP points: 1..10)', cast(count(*) as float), 1, 10
    from {{ ref('fact_food_security_risk') }} where risk_basis = 'rain + yield'
    union all
    select '8 sanity', 'Egypt has a risk score', cast(count(*) as float), 1, 1
    from {{ ref('fact_food_security_risk') }} r join {{ ref('dim_area') }} a on a.area_code = r.area_code
    where a.area_name = 'Egypt'
),

scored as (
    select check_group, check_name, actual, min_ok, max_ok,
           case when actual is not null
                 and actual >= min_ok
                 and (max_ok is null or actual <= max_ok) then 'PASS' else 'FAIL' end as status
    from checks
)

select 0 as sort_key, '0 SUMMARY' as check_group,
       concat(cast(sum(case when status = 'PASS' then 1 else 0 end) as varchar(10)), ' of ', cast(count(*) as varchar(10)), ' checks passed') as check_name,
       cast(sum(case when status = 'FAIL' then 1 else 0 end) as float) as actual,
       cast(0 as float) as min_ok, cast(0 as float) as max_ok,
       case when sum(case when status = 'FAIL' then 1 else 0 end) = 0 then 'ALL PASS'
            else concat(cast(sum(case when status = 'FAIL' then 1 else 0 end) as varchar(10)), ' FAILED') end as status
from scored
union all
select case when status = 'FAIL' then 1 else 2 end, check_group, check_name, actual, min_ok, max_ok, status
from scored
order by sort_key, check_group, check_name