select
    upper(trim(flag))   as flag,
    trim(description)   as description,
    case upper(trim(flag))
        when 'A' then 'Official'
        when 'X' then 'External organization'
        when 'E' then 'Estimated'
        when 'I' then 'Estimated'
        when 'M' then 'Missing'
        else 'Other'
    end                 as source_type
from {{ ref('brz_fao_flags') }}
where flag is not null