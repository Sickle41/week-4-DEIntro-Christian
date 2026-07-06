"""Load the messy source files into DuckDB, AS-IS. **Provided — don't change.**

This is the "EL" of ELT, collapsed into one script so the week stays about dbt
(the "T"). No S3 this week — the point is the transform layer, not the plumbing
you already built in Weeks 1-3.

    data/source/orders.csv      -> table  raw.orders
    data/source/customers.json  -> table  raw.customers

Both land raw, mess and all: duplicate order_ids, blank cells, money-as-text,
three date formats, duplicate customers. That's expected — dbt models clean it.

dbt NEVER does this step. dbt assumes data is already IN the warehouse and only
transforms it from there. Something else (Airbyte, Fivetran, your Week 2
pipeline, this script) gets it in.

Run it with:  uv run python scripts/load_raw.py
"""

from __future__ import annotations

from pathlib import Path

import duckdb

DB_PATH = Path("data/warehouse.duckdb")
SOURCE_DIR = Path("data/source")


def main() -> None:
    orders_csv = SOURCE_DIR / "orders.csv"
    customers_json = SOURCE_DIR / "customers.json"
    if not orders_csv.exists() or not customers_json.exists():
        raise SystemExit(
            "data/source/ is missing — run `uv run python scripts/generate_data.py` first"
        )

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB_PATH))
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    # read_csv_auto lands the messy price column as text on its own — good.
    # Casting it deliberately is a dbt model's job now.
    con.execute(
        "CREATE OR REPLACE TABLE raw.orders AS SELECT * FROM read_csv_auto(?)",
        [str(orders_csv)],
    )
    con.execute(
        "CREATE OR REPLACE TABLE raw.customers AS SELECT * FROM read_json_auto(?)",
        [str(customers_json)],
    )

    n_orders = con.execute("SELECT count(*) FROM raw.orders").fetchone()[0]
    d_orders = con.execute("SELECT count(DISTINCT order_id) FROM raw.orders").fetchone()[0]
    n_cust = con.execute("SELECT count(*) FROM raw.customers").fetchone()[0]
    d_cust = con.execute("SELECT count(DISTINCT customer_id) FROM raw.customers").fetchone()[0]
    con.close()

    print(f"raw.orders:    {n_orders:,} rows ({d_orders:,} distinct order_ids) -> {DB_PATH}")
    print(f"raw.customers: {n_cust:,} rows ({d_cust:,} distinct customer_ids) -> {DB_PATH}")
    print("note: row counts > distinct counts on purpose — your dbt models dedup this.")


if __name__ == "__main__":
    main()
