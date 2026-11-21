select
    try_cast(nullif(ltrim(rtrim(month_date)), '')    as date)            as month_date,
    try_cast(nullif(ltrim(rtrim(ffpi)), '')          as decimal(14, 6))  as ffpi,
    try_cast(nullif(ltrim(rtrim(meat)), '')          as decimal(14, 6))  as meat,
    try_cast(nullif(ltrim(rtrim(dairy)), '')         as decimal(14, 6))  as dairy,
    try_cast(nullif(ltrim(rtrim(cereals)), '')       as decimal(14, 6))  as cereals,
    try_cast(nullif(ltrim(rtrim(oils)), '')          as decimal(14, 6))  as oils,
    try_cast(nullif(ltrim(rtrim(sugar)), '')         as decimal(14, 6))  as sugar,
    try_cast(nullif(ltrim(rtrim(ffpi_real)), '')     as decimal(14, 6))  as ffpi_real,
    try_cast(nullif(ltrim(rtrim(meat_real)), '')     as decimal(14, 6))  as meat_real,
    try_cast(nullif(ltrim(rtrim(dairy_real)), '')    as decimal(14, 6))  as dairy_real,
    try_cast(nullif(ltrim(rtrim(cereals_real)), '')  as decimal(14, 6))  as cereals_real,
    try_cast(nullif(ltrim(rtrim(oils_real)), '')     as decimal(14, 6))  as oils_real,
    try_cast(nullif(ltrim(rtrim(sugar_real)), '')    as decimal(14, 6))  as sugar_real,
    try_cast(_loaded_at as datetime2(0))             as _loaded_at,
    _source_file
from {{ source('staging', 'ffpi_monthly') }}