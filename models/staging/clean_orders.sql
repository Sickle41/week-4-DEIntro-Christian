-- Build clean_orders from orders_deduped: cast money/quantity, parse dates
-- (all three formats), normalize status, drop unusable rows, add line_total.
CREATE OR REPLACE TABLE clean_orders AS
WITH parsed AS (
    SELECT
        order_id,
        customer_id,
        sku,
        quantity,
        TRY_CAST(
            REPLACE(REPLACE(TRIM(price), '$', ''), ',', '') AS DOUBLE
        ) AS price,
        COALESCE(NULLIF(LOWER(TRIM(status)), ''), 'unknown') AS status,
        COALESCE(
            TRY_STRPTIME(order_date, '%d-%b-%Y'),
            TRY_STRPTIME(order_date, '%Y-%m-%d'),
            TRY_STRPTIME(order_date, '%m/%d/%Y')
        )::DATE AS order_date,
        updated_at
    FROM orders_deduped
)
SELECT
    order_id,
    customer_id,
    sku,
    quantity,
    price,
    status,
    order_date,
    updated_at,
    quantity * price AS line_total
FROM parsed
WHERE quantity IS NOT NULL AND price IS NOT NULL
