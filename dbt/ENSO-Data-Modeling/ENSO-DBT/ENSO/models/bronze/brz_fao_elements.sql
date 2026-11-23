select
    try_cast(nullif(ltrim(rtrim(element_code)), '') as int)  as element_code,
    nullif(ltrim(rtrim(element_name)), '')                   as element_name,
    try_cast(_loaded_at as datetime2(0))                     as _loaded_at,
    _source_file
from {{ source('staging', 'fao_elements') }}