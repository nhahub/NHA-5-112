select 'item_classification' as seed, cast(c.fao_item_code as varchar(20)) as code
from {{ ref('item_classification') }} c
left join {{ ref('slv_item') }} i on i.item_code = c.fao_item_code
where i.item_code is null
union all
select 'gpcp_locations', cast(l.area_code as varchar(20))
from {{ ref('gpcp_locations') }} l
left join {{ ref('slv_area') }} a on a.area_code = l.area_code
where a.area_code is null