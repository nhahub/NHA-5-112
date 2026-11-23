with units as (
    select element_code, max(unit) as unit
    from {{ ref('brz_fao_production') }}
    where element_code in (5312, 5412, 5510)
    group by element_code
)
select
    e.element_code,
    trim(e.element_name)                                              as element_name,
    u.unit,
    concat(trim(e.element_name), ' (', coalesce(u.unit, 'n/a'), ')')  as element_label
from {{ ref('brz_fao_elements') }} e
left join units u on u.element_code = e.element_code
where e.element_code in (5312, 5412, 5510)