select element_code, element_name, unit
from {{ ref('slv_element') }}