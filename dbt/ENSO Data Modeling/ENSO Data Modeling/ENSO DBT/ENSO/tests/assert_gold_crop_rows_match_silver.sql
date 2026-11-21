select s.n as silver_rows, g.n as gold_rows
from (select count(*) as n from {{ ref('slv_crop_production') }}) s
cross join (select count(*) as n from {{ ref('fact_crop_production') }}) g
where s.n <> g.n