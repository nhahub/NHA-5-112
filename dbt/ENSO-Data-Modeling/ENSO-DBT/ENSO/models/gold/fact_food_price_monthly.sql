select s.date_key, f.food_index_id, s.nominal_index, s.real_index
from {{ ref('slv_food_price_monthly') }} s
join {{ ref('dim_food_index') }} f on f.index_code = s.index_code