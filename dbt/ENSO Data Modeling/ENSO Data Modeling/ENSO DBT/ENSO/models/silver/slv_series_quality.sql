with p as (
    select
        max(case when param_name = 'analysis_start_year' then param_value end) as start_year,
        max(case when param_name = 'analysis_end_year'   then param_value end) as end_year,
        max(case when param_name = 'max_missing_share'   then param_value end) as max_missing_share,
        max(case when param_name = 'max_zero_share'      then param_value end) as max_zero_share,
        max(case when param_name = 'max_gap_years'       then param_value end) as max_gap_years
    from {{ ref('analysis_parameters') }}
),
y as (
    select c.area_code, c.item_code, c.year_num, c.value
    from {{ ref('slv_crop_production') }} c
    cross join p
    where c.element_code = 5412
      and c.value is not null
      and c.year_num between p.start_year and p.end_year
),
g as (
    select area_code, item_code, year_num, value,
           year_num - lag(year_num) over (partition by area_code, item_code order by year_num) - 1 as gap_before
    from y
),
agg as (
    select area_code, item_code,
           count(*)                                    as n_years,
           sum(case when value = 0 then 1 else 0 end)  as n_zero_years,
           min(year_num)                               as first_year,
           max(year_num)                               as last_year,
           max(coalesce(gap_before, 0))                as max_gap_years
    from g
    group by area_code, item_code
)
select
    a.area_code,
    a.item_code,
    a.n_years,
    a.n_zero_years,
    a.first_year,
    a.last_year,
    a.max_gap_years,
    (p.end_year - p.start_year + 1)                                               as expected_years,
    1.0 - cast(a.n_years as float) / (p.end_year - p.start_year + 1)              as missing_share,
    cast(a.n_zero_years as float) / a.n_years                                     as zero_share,
    case when 1.0 - cast(a.n_years as float) / (p.end_year - p.start_year + 1) <= p.max_missing_share
          and cast(a.n_zero_years as float) / a.n_years <= p.max_zero_share
          and a.max_gap_years <= p.max_gap_years
         then 1 else 0 end                                                        as passes_quality
from agg a
cross join p