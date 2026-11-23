select f.food_index_id, count(*) as n_months,
       datediff(month, min(d.month_start), max(d.month_start)) + 1 as expected_months
from {{ ref('fact_food_price_monthly') }} f
join {{ ref('dim_date') }} d on d.date_key = f.date_key
group by f.food_index_id
having count(*) <> datediff(month, min(d.month_start), max(d.month_start)) + 1