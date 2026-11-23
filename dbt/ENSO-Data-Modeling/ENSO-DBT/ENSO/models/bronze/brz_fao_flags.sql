select
    nullif(ltrim(rtrim(flag)), '')         as flag,
    nullif(ltrim(rtrim(description)), '')  as description,
    try_cast(_loaded_at as datetime2(0))   as _loaded_at,
    _source_file
from {{ source('staging', 'fao_flags') }}