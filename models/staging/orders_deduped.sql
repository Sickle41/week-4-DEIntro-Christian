-- Build orders_deduped: exactly one row per order_id — the newest copy by
-- updated_at — keeping all the original columns.
CREATE OR REPLACE TABLE orders_deduped AS
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY updated_at DESC
        ) AS row_num
    FROM raw_orders
)
SELECT * EXCLUDE (row_num)
FROM ranked
WHERE row_num = 1
