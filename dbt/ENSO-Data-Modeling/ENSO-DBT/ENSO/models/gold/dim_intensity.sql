select intensity_id, label, min_abs_anom, max_abs_anom
from {{ ref('enso_intensity') }}