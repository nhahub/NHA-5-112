-- ENSO year type = the event phase of November (centre of the Oct-Nov-Dec season).
-- oni_ond = ONI centred on November = the 3-month mean labelled October in the source file.
with base as (
    select
        d.year_num,
        d.month_num,
        pe.phase_code                                       as phase_code,
        lag(f.anomaly_3m, 1) over (order by d.month_start)  as oni_centered
    from {{ ref('fact_enso_monthly') }} f
    join {{ ref('dim_date') }} d         on d.date_key = f.date_key
    join {{ ref('dim_enso_phase') }} pe  on pe.phase_id = f.phase_event_id
),
yr as (
    select
        year_num,
        sum(case when phase_code = 'elnino'  then 1 else 0 end)   as el_nino_months,
        sum(case when phase_code = 'lanina'  then 1 else 0 end)   as la_nina_months,
        sum(case when phase_code = 'neutral' then 1 else 0 end)   as neutral_months,
        sum(case when phase_code <> 'unknown' then 1 else 0 end)  as months_known,
        avg(oni_centered)                                         as oni_mean,
        max(case when month_num = 11 then oni_centered end)       as oni_ond,
        max(case when month_num = 11 then phase_code end)         as ond_phase_code
    from base
    group by year_num
)
select
    y.year_num,
    y.el_nino_months,
    y.la_nina_months,
    y.neutral_months,
    case when y.months_known = 12 then 1 else 0 end  as is_complete,
    y.oni_mean,
    y.oni_ond,
    ph.phase_id                                      as year_phase_id,
    it.intensity_id
from yr y
join {{ ref('dim_enso_phase') }} ph on ph.phase_code = coalesce(y.ond_phase_code, 'unknown')
left join {{ ref('dim_intensity') }} it
       on abs(y.oni_ond) >= it.min_abs_anom
      and (abs(y.oni_ond) < it.max_abs_anom or it.max_abs_anom is null)