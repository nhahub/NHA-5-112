select
    try_cast(nullif(ltrim(rtrim(month_date)), '')                                         as date)            as month_date,
    nullif(ltrim(rtrim(country)), '')                                                                         as gpcp_region,
    try_cast(nullif(ltrim(rtrim(original_lat)), '')                                       as decimal(9, 4))   as original_lat,
    try_cast(nullif(ltrim(rtrim(original_lon)), '')                                       as decimal(9, 4))   as original_lon,
    try_cast(nullif(ltrim(rtrim(grid_lat)), '')                                           as decimal(9, 4))   as grid_lat,
    try_cast(nullif(ltrim(rtrim(grid_lon)), '')                                           as decimal(9, 4))   as grid_lon,
    try_cast(try_cast(nullif(ltrim(rtrim(precipitation_mm_per_day)), '') as float)        as decimal(18, 13)) as precipitation_mm_per_day,
    try_cast(_loaded_at as datetime2(0))                                                                      as _loaded_at,
    _source_file
from {{ source('staging', 'gpcp_precipitation') }}