select 'corr_oni_ond' as metric, area_code, item_code, corr_oni_ond as bad_value
from {{ ref('fact_yield_sensitivity') }}
where corr_oni_ond < -1 or corr_oni_ond > 1
union all
select 'risk_score', area_code, null, risk_score
from {{ ref('fact_food_security_risk') }}
where risk_score < 0 or risk_score > 100
union all
select 'rain_sensitivity', area_code, null, rain_sensitivity
from {{ ref('fact_food_security_risk') }}
where rain_sensitivity < 0 or rain_sensitivity > 1