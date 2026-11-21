select item_code_text, item_name
from {{ ref('brz_fao_items') }}
where item_code is null