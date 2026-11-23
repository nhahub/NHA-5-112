select
    try_cast(try_cast(nullif(ltrim(rtrim(replace(replace(replace(month_date, char(13), ''), char(10), ''), char(9), ''))), '') as datetime2) as date) as month_date,
    try_cast(try_cast(nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(total_sst, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') as float) as decimal(10, 4)) as total_sst,
    try_cast(try_cast(nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(clim_adjust, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') as float) as decimal(10, 4)) as clim_adjust,
    try_cast(try_cast(nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(anom, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') as float) as decimal(10, 4)) as anom,
    try_cast(try_cast(nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(anom_trimester, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') as float) as decimal(12, 8)) as anom_trimester,
    try_cast(try_cast(nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(anom_trimester_round, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') as float) as decimal(6, 2)) as anom_trimester_round,
    nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(phase_trimester, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') as phase_trimester,
    nullif(nullif(lower(ltrim(rtrim(replace(replace(replace(phase_event, char(13), ''), char(10), ''), char(9), '')))), ''), 'nan') as phase_event,
    try_cast(_loaded_at as datetime2(0)) as _loaded_at,
    _source_file
from {{ source('staging', 'enso_events') }}