{{ config(severity='warn') }}

select flag, count(*) as rows_without_value
from {{ ref('brz_fao_production') }}
where value is null
  and (flag is null or flag <> 'M')
group by flag