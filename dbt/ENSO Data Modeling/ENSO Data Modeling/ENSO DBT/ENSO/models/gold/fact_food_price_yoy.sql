select
    date_key,
    food_index_id,
    (nominal_index / nullif(lag(nominal_index, 12) over (partition by food_index_id order by date_key), 0) - 1) * 100 as yoy_nominal_pct,
    (real_index    / nullif(lag(real_index, 12)    over (partition by food_index_id order by date_key), 0) - 1) * 100 as yoy_real_pct
from {{ ref('fact_food_price_monthly') }}