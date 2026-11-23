select food_index_id, index_code, index_name, is_headline
from {{ ref('food_indices') }}