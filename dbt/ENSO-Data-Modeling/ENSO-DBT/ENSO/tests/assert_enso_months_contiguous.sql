select count(*) as n_months,
       datediff(month, min(month_start), max(month_start)) + 1 as expected_months
from {{ ref('slv_enso_monthly') }}
having count(*) <> datediff(month, min(month_start), max(month_start)) + 1