{{ config(severity='warn') }}

select p.phase_code, count(*) as n_events
from {{ ref('dim_enso_event') }} e
join {{ ref('dim_enso_phase') }} p on p.phase_id = e.phase_id
group by p.phase_code
having (p.phase_code = 'elnino' and count(*) <> 25)
    or (p.phase_code = 'lanina' and count(*) <> 20)