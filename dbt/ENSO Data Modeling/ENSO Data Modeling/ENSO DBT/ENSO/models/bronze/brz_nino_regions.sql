select
    try_cast(nullif(ltrim(rtrim(yr)), '')           as int)            as yr,
    try_cast(nullif(ltrim(rtrim(mon)), '')          as int)            as mon,
    try_cast(nullif(ltrim(rtrim(nino12)), '')       as decimal(8, 3))  as nino12,
    try_cast(nullif(ltrim(rtrim(nino12_anom)), '')  as decimal(8, 3))  as nino12_anom,
    try_cast(nullif(ltrim(rtrim(nino3)), '')        as decimal(8, 3))  as nino3,
    try_cast(nullif(ltrim(rtrim(nino3_anom)), '')   as decimal(8, 3))  as nino3_anom,
    try_cast(nullif(ltrim(rtrim(nino4)), '')        as decimal(8, 3))  as nino4,
    try_cast(nullif(ltrim(rtrim(nino4_anom)), '')   as decimal(8, 3))  as nino4_anom,
    try_cast(nullif(ltrim(rtrim(nino34)), '')       as decimal(8, 3))  as nino34,
    try_cast(nullif(ltrim(rtrim(nino34_anom)), '')  as decimal(8, 3))  as nino34_anom,
    try_cast(_loaded_at as datetime2(0))                               as _loaded_at,
    _source_file
from {{ source('staging', 'nino_regions') }}