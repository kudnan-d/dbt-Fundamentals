{{ 
  config(
    materialized = 'incremental',
    unique_key = 'order_id',
    incremental_strategy = 'merge',
    on_schema_change= 'fail'
  )
}}

with orders as (
    select
        order_id,
        customer_id,
        order_date,
        order_date as order_updated_at
    from {{ ref('stg_jaffle_shop__orders') }}
),

payments as (
    select
        order_id,
        amount,
        status,
        created_at as payment_updated_at
    from {{ ref('stg_stripe__payments') }}
),

order_payments as (
    select
        order_id,
        sum(case when status = 'success' then amount else 0 end) as amount,
        max(payment_updated_at) as payment_updated_at
    from payments
    group by order_id
),

final as (
    select
        o.order_id,
        o.customer_id,
        o.order_date,
        coalesce(p.amount, 0) as amount,
        greatest(
            o.order_updated_at,
            p.payment_updated_at
        ) as last_updated_at
    from orders o
    left join order_payments p
        on o.order_id = p.order_id
)

select *
from final

{% if is_incremental() %}
where last_updated_at >
      (select max(last_updated_at) from {{ this }})
{% endif %}
