WITH deduped_customers AS (
    SELECT * EXCLUDE (row_num)
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY customer_id
                ORDER BY record_version DESC
            ) AS row_num
        FROM raw_customers
    )
    WHERE row_num = 1
)
