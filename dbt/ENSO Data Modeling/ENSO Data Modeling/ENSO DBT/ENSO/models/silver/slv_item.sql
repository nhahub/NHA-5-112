select
    i.item_code,
    replace(i.cpc_code, '''', '')               as cpc_code,
    trim(replace(i.item_name, ';', ','))        as item_name,
    coalesce(c.is_primary_crop, 0)              as is_primary_crop,
    c.food_index_code
from {{ ref('brz_fao_items') }} i
left join {{ ref('item_classification') }} c on c.fao_item_code = i.item_code
where i.item_code is not null