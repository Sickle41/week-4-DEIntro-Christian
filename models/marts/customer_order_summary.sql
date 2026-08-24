-- One row per customer: customer_id, name, order_count, total_revenue.
-- Orders with a NULL customer_id are deliberately excluded before the
-- aggregate, so they can't fan out or need to match a customer downstream.
WITH order_agg AS (
    SELECT
        customer_id,
        count(*) AS order_count,
        sum(line_total) AS total_revenue
    FROM {{ ref('clean_orders') }}
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.name,
    o.order_count,
    o.total_revenue
FROM order_agg o
JOIN {{ ref('customers_deduped') }} c ON c.customer_id = o.customer_id
WHERE o.order_count >= {{ var('min_orders') }}
