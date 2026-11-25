select
    area_code,
    replace(m49_code, '''', '')                     as m49_code,
    trim(replace(area_name, ';', ','))              as area_name,
    case
        when area_code >= 5000 then 1   -- World / Regions / Income groups
        when area_code = 351   then 1   -- 'China' = FAO (41 + 96 + 128 + 214)
        else 0
    end                                             as is_aggregate
from {{ ref('brz_fao_areas') }}
where area_code is not null