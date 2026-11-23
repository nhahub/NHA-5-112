select year_num, el_nino_months, la_nina_months, neutral_months, is_complete
from {{ ref('fact_enso_year') }}
where el_nino_months + la_nina_months + neutral_months > 12
   or (is_complete = 1 and el_nino_months + la_nina_months + neutral_months <> 12)