select
    try_cast(nullif(ltrim(rtrim(area_code)), '') as int)   as area_code,
    nullif(ltrim(rtrim(m49_code)), '')                     as m49_code,
    nullif(ltrim(rtrim(area_name)), '')                    as area_name,
    try_cast(_loaded_at as datetime2(0))                   as _loaded_at,
    _source_file
from {{ source('staging', 'fao_areas') }}