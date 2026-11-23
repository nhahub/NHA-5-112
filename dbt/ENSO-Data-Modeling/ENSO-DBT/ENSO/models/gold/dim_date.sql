with n as (
    select top (972) row_number() over (order by (select null)) - 1 as n
    from sys.all_objects a
    cross join sys.all_objects b
),
d as (
    select dateadd(month, cast(n as int), cast('1950-01-01' as date)) as month_start
    from n
)
select
    year(month_start) * 10000 + month(month_start) * 100 + 1  as date_key,
    month_start,
    year(month_start)                                         as year_num,
    month(month_start)                                        as month_num,
    datename(month, month_start)                              as month_name,
    datepart(quarter, month_start)                            as quarter_num
from d