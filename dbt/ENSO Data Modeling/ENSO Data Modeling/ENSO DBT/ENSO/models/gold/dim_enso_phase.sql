select phase_id, phase_code, phase_name
from {{ ref('enso_phases') }}