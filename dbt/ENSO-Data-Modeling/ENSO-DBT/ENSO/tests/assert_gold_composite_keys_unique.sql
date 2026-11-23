select 'fact_crop_production' as tbl, count(*) as duplicate_keys from (
    select area_code, item_code, element_code, year_num from {{ ref('fact_crop_production') }}
    group by area_code, item_code, element_code, year_num having count(*) > 1) x having count(*) > 0
union all
select 'fact_precipitation' as tbl, count(*) as duplicate_keys from (
    select date_key, location_id from {{ ref('fact_precipitation') }}
    group by date_key, location_id having count(*) > 1) x having count(*) > 0
union all
select 'fact_food_price_monthly' as tbl, count(*) as duplicate_keys from (
    select date_key, food_index_id from {{ ref('fact_food_price_monthly') }}
    group by date_key, food_index_id having count(*) > 1) x having count(*) > 0
union all
select 'fact_food_price_annual' as tbl, count(*) as duplicate_keys from (
    select year_num, food_index_id from {{ ref('fact_food_price_annual') }}
    group by year_num, food_index_id having count(*) > 1) x having count(*) > 0
union all
select 'fact_nino_region_sst' as tbl, count(*) as duplicate_keys from (
    select date_key, region_id from {{ ref('fact_nino_region_sst') }}
    group by date_key, region_id having count(*) > 1) x having count(*) > 0
union all
select 'fact_yield_anomaly' as tbl, count(*) as duplicate_keys from (
    select area_code, item_code, year_num from {{ ref('fact_yield_anomaly') }}
    group by area_code, item_code, year_num having count(*) > 1) x having count(*) > 0
union all
select 'fact_yield_sensitivity' as tbl, count(*) as duplicate_keys from (
    select area_code, item_code from {{ ref('fact_yield_sensitivity') }}
    group by area_code, item_code having count(*) > 1) x having count(*) > 0
union all
select 'fact_precip_anomaly' as tbl, count(*) as duplicate_keys from (
    select date_key, location_id from {{ ref('fact_precip_anomaly') }}
    group by date_key, location_id having count(*) > 1) x having count(*) > 0
union all
select 'fact_food_price_yoy' as tbl, count(*) as duplicate_keys from (
    select date_key, food_index_id from {{ ref('fact_food_price_yoy') }}
    group by date_key, food_index_id having count(*) > 1) x having count(*) > 0