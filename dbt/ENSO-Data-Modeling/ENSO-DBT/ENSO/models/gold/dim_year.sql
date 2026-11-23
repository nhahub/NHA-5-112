with n as (
    select top (81) row_number() over (order by (select null)) - 1 as n
    from sys.all_objects a
    cross join sys.all_objects b
)
select
    cast(1950 + n as int)               as year_num,
    cast(((1950 + n) / 10) * 10 as int) as decade
from n