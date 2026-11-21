with base as (
    select
        datefromparts(year(month_date), month(month_date), 1) as month_start,
        ffpi, meat, dairy, cereals, oils, sugar,
        ffpi_real, meat_real, dairy_real, cereals_real, oils_real, sugar_real
    from {{ ref('brz_ffpi_monthly') }}
    where month_date is not null
)
select
    b.month_start,
    year(b.month_start) * 10000 + month(b.month_start) * 100 + 1  as date_key,
    v.index_code,
    v.nominal_index,
    v.real_index
from base b
cross apply (values
    ('FFPI',    b.ffpi,    b.ffpi_real),
    ('MEAT',    b.meat,    b.meat_real),
    ('DAIRY',   b.dairy,   b.dairy_real),
    ('CEREALS', b.cereals, b.cereals_real),
    ('OILS',    b.oils,    b.oils_real),
    ('SUGAR',   b.sugar,   b.sugar_real)
) as v(index_code, nominal_index, real_index)