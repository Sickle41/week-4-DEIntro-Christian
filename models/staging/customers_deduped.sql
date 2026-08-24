-- Build customers_deduped: exactly one row per customer_id — the highest
-- record_version wins — keeping all the original columns.
WITH deduped_customers AS (
    SELECT * EXCLUDE (row_num)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY customer_id
                ORDER BY record_version DESC
            ) AS row_num
        FROM {{ source('raw', 'customers') }}
    )
    WHERE row_num = 1
)
SELECT * FROM deduped_customers
