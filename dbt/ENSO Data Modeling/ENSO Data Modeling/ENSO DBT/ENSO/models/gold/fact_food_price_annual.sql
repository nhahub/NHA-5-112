select s.year_num, f.food_index_id, s.nominal_index, s.real_index, s.months_count
from {{ ref('slv_food_price_annual') }} s
join {{ ref('dim_food_index') }} f on f.index_code = s.index_code