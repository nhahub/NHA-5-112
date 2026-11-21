select
    i.item_code,
    i.item_name,
    i.cpc_code,
    i.is_primary_crop,
    f.food_index_id
from {{ ref('slv_item') }} i
left join {{ ref('dim_food_index') }} f on f.index_code = i.food_index_code