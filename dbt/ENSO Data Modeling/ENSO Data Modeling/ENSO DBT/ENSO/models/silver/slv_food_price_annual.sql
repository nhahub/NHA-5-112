select
    year(month_start)     as year_num,
    index_code,
    avg(nominal_index)    as nominal_index,
    avg(real_index)       as real_index,
    count(nominal_index)  as months_count
from {{ ref('slv_food_price_monthly') }}
group by year(month_start), index_code