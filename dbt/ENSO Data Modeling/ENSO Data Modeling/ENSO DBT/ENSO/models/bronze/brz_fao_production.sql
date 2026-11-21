select
    try_cast(nullif(ltrim(rtrim(area_code)), '')    as int)            as area_code,
    nullif(ltrim(rtrim(area_code_m49)), '')                            as area_code_m49,
    nullif(ltrim(rtrim(area_name)), '')                                as area_name,
    try_cast(nullif(ltrim(rtrim(item_code)), '')    as int)            as item_code,
    nullif(ltrim(rtrim(item_code_cpc)), '')                            as item_code_cpc,
    nullif(ltrim(rtrim(item_name)), '')                                as item_name,
    try_cast(nullif(ltrim(rtrim(element_code)), '') as int)            as element_code,
    nullif(ltrim(rtrim(element_name)), '')                             as element_name,
    try_cast(nullif(ltrim(rtrim(year_code)), '')    as int)            as year_code,
    try_cast(nullif(ltrim(rtrim([year])), '')       as int)            as year,
    nullif(ltrim(rtrim(unit)), '')                                     as unit,
    try_cast(nullif(ltrim(rtrim([value])), '')      as decimal(24, 6)) as value,
    nullif(ltrim(rtrim(flag)), '')                                     as flag,
    try_cast(_loaded_at as datetime2(0))                               as _loaded_at,
    _source_file
from {{ source('staging', 'fao_production') }}