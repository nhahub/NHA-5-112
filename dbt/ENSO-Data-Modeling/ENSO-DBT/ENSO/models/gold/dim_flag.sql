select flag as flag_code, description
from {{ ref('slv_flag') }}