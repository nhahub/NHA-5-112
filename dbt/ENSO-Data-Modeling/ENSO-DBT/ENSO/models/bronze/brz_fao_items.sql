select
    nullif(ltrim(rtrim(item_code)), '')                        as item_code_text,
    try_cast(nullif(ltrim(rtrim(item_code)), '') as int)       as item_code,
    nullif(ltrim(rtrim(cpc_code)), '')                         as cpc_code,
    nullif(ltrim(rtrim(item_name)), '')                        as item_name,
    try_cast(_loaded_at as datetime2(0))                       as _loaded_at,
    _source_file
from {{ source('staging', 'fao_items') }}
where try_cast(nullif(ltrim(rtrim(item_code)), '') as int) is not null