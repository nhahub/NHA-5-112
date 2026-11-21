select
    datefromparts(year(month_date), month(month_date), 1)                 as month_start,
    year(month_date) * 10000 + month(month_date) * 100 + 1                as date_key,
    total_sst                                                             as sst_total,
    clim_adjust                                                           as sst_climatology,
    anom                                                                  as anomaly,
    anom_trimester                                                        as anomaly_3m,
    anom_trimester_round                                                  as anomaly_3m_rounded,
    case
        when anom_trimester is null then 'unknown'
        when replace(replace(phase_trimester, ' ', ''), '_', '') like '%elni%'    then 'elnino'
        when replace(replace(phase_trimester, ' ', ''), '_', '') like '%lani%'    then 'lanina'
        when replace(replace(phase_trimester, ' ', ''), '_', '') like '%neutral%' then 'neutral'
        else 'unknown'
    end                                                                   as phase_3m_code,
    case
        when anom_trimester is null then 'unknown'
        when replace(replace(phase_event, ' ', ''), '_', '') like '%elni%'        then 'elnino'
        when replace(replace(phase_event, ' ', ''), '_', '') like '%lani%'        then 'lanina'
        when replace(replace(phase_event, ' ', ''), '_', '') like '%neutral%'     then 'neutral'
        else 'unknown'
    end                                                                   as phase_event_code
from {{ ref('brz_enso_events') }}
where month_date is not null