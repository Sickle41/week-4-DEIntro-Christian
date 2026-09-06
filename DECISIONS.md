# DECISIONS.md

> Day 3 deliverable. Real data engineers leave a trail of *why*, not just *what*.
> Keep this short and honest — a few sentences per question. You're defending
> the calls you made moving a working SQL pipeline into dbt.

## 1. Your models have no CREATE TABLE. Where did the DDL go, and why is that dbt's job?

The DDL moved into `dbt_project.yml`'s `models:` config (`+materialized: view` /
`table`) and into dbt's built-in materialization macros, which wrap my bare
`SELECT` in whatever `CREATE VIEW` / `CREATE OR REPLACE TABLE` the target
adapter needs. I no longer decide per-file whether something is a view or a
table, or hand-write `DROP TABLE IF EXISTS` before every rebuild — dbt derives
that from one config in one place, so changing `clean_orders` from a view to a
table is a one-line config edit, not a rewrite of the model's SQL. It also
means the same model file works unmodified across warehouses (DuckDB here,
Snowflake/BigQuery elsewhere) since dbt's adapter picks the right DDL dialect.
The cost: I gave up control over exactly how the object gets built (I can't
tweak the `CREATE TABLE` statement itself without overriding the
materialization), and it's one more layer to understand when something goes
wrong — the error is in generated DDL I didn't write, not in my SELECT.

## 2. `ref()` looks like extra typing. `FROM clean_orders` would have worked. Why bother?

Two concrete things: **order** and **the graph**. Because `customer_order_summary`
uses `{{ ref('clean_orders') }}` and `{{ ref('customers_deduped') }}` instead of
bare table names, dbt parses those calls, builds a dependency DAG, and runs
`dbt run` in topological order — I watched it build `customers_deduped` and
`orders_deduped` first, then `clean_orders`, then the mart last, without me
ever specifying an order. A hard-coded `FROM clean_orders` would just as
happily run before `clean_orders` exists (or against yesterday's stale table)
if I ran things out of order or added a new model in between. Second, `ref()`
is what makes the DAG *visible*: `dbt docs generate` / the lineage graph is
built entirely by walking `ref()`/`source()` calls. Delete a `ref()` and swap
in a hard-coded name and that edge silently disappears from the graph —
`clean_orders` would still run fine, but nothing downstream would know it
depends on `orders_deduped`, so a change to `orders_deduped` wouldn't be
flagged as touching anything else.

## 3. Open `target/compiled/.../customer_order_summary.sql`. What did you find, and why does "dbt is just a compiler" matter?

Plain SQL, nothing more. `{{ ref('clean_orders') }}` became the literal
identifier `"warehouse"."main"."clean_orders"`, `{{ ref('customers_deduped') }}`
became `"warehouse"."main"."customers_deduped"`, and `{{ var('min_orders') }}`
became the number `2`. No Jinja, no macros, no magic left in the file — just a
`WITH ... SELECT ... JOIN ... WHERE o.order_count >= 2` that I could paste into
any SQL client and run as-is. That's the answer to "I don't trust dbt": open
the compiled file next to the source model and show them it's a 1:1,
readable, DuckDB-native mapping — dbt's whole contribution was string
substitution (name resolution + variable interpolation) plus the ordering
described in Q2, not some runtime black box executing hidden logic against the
warehouse.

## 4. Week 2 you tested code with pytest. This week `dbt test` tested data. What's the difference — and why do you want both?

pytest asserts my *transformation logic* is correct against fixed, known
inputs — e.g. "given this fake row with `price = '$1,209.50'`, my cast
produces `1209.50`." It stays green even if the real warehouse is full of
garbage, because it never touches production data. `dbt test` asserts the
*actual data* in the warehouse right now satisfies a contract — e.g. "every
`order_id` in `orders_deduped` is actually unique" — and I proved this week
that it stays green or red independent of the code: I commented out
`WHERE row_num = 1`, the code "worked" (no exceptions, `dbt run` succeeded),
but `dbt test` caught 1732 duplicate rows that no pytest suite would ever see
because pytest never ran against that data. I want both because they catch
disjoint failure modes: pytest catches "my logic is wrong before it ever
touches real data," `dbt test` catches "my logic is fine but an upstream
source changed shape, dbt's ordering ran against different data than I tested
with, or a one-off manual load broke an invariant" — regressions in the data
itself that no amount of unit testing the transformation code would surface.

## 5. `var('min_orders')` vs Week 2's `$min_orders` bound parameter — same idea or not?

Same *motivation* (don't hard-code the threshold), completely different
*mechanism and timing*. Week 2's `$min_orders` was a bound parameter: the SQL
text sent to DuckDB still contained the placeholder, and the driver substituted
the value at execution time, outside the SQL string, which is exactly what
defeats SQL injection — a malicious value can never be interpreted as SQL
syntax because it's never concatenated into the query text at all. `var()` is
the opposite: it's a Jinja template substitution that happens at **compile
time**, before the query is ever sent anywhere. Looking at the compiled file
proves it — `{{ var('min_orders') }}` is gone entirely, replaced by the literal
text `2` sitting directly in the SQL string, no different from if I'd typed
`WHERE o.order_count >= 2` by hand. So the SQL-injection argument does *not*
carry over automatically: if `min_orders` came from an untrusted source (a
user-supplied CLI flag from someone who shouldn't have shell access, say) and
were a string like `2; DROP TABLE customers_deduped`, Jinja would paste that
text straight into the compiled SQL as-is. In practice this is safe here
because `vars` only ever come from `dbt_project.yml` or a trusted operator's
`--vars` flag at run time — not from an end user or application input — so the
injection surface doesn't exist in practice, but the *mechanism* that made
bound parameters safe (execution-time substitution outside the SQL text) is
gone.

## 6. Staging models are views; the mart is a table. Defend that — then name a case where you'd flip one.

Views (`orders_deduped`, `customers_deduped`, `clean_orders`) are cheap to
create, take zero storage, and are always up to date because they just
re-run their `SELECT` against the underlying source every time something
queries them — right for staging models, which exist purely to be read by
one or two things downstream (each other, or the mart) rather than queried
directly by a human or dashboard. `customer_order_summary` is a table because
it's "the thing people actually query" per its own description: a mart gets
hit repeatedly by dashboards/analysts, and recomputing the full window
function + join + aggregate on every single query would be wasteful when the
underlying orders/customers data only changes once per `dbt run`. Materializing
it once as a table trades a bit of staleness (until the next run) for query
speed. I'd flip this if `orders_deduped` itself became expensive to
recompute — e.g. if `raw.orders` grew to hundreds of millions of rows and
multiple downstream models each re-ran that `ROW_NUMBER()` window function
independently as a view; at that volume I'd materialize `orders_deduped` as a
table (or incremental model) so the dedup work happens once, not once per
consumer. Conversely, I'd flip the mart back to a view if `min_orders` needed
to reflect near-real-time order counts (a freshness need where "up to date
as of the last `dbt run`" isn't good enough) and query volume against it was
low enough that recomputing on every read was acceptable.

## 7. What did dbt NOT do for you this week?

dbt's job starts the moment raw data already exists as queryable tables
(`raw.orders`, `raw.customers`) and ends the moment clean tables exist in the
warehouse — it is purely the T in ELT. It did not generate the fake data
(`generate_data.py`, Week 1), did not fetch or land it in the warehouse
(`load_raw.py` / the S3 + load step, Weeks 1-2) — I still ran those by hand
before `dbt run` could see anything. It also doesn't schedule itself: nothing
here re-runs nightly on its own, there's no orchestrator (Airflow/Dagster/a
cron job) invoking `dbt run && dbt test` on a cadence, and no alerting if a
scheduled run's tests fail. It doesn't serve the output either — no BI tool,
API, or export step reads `customer_order_summary` for anyone; that mart just
sits in the warehouse until something else queries it. Before this runs
unattended every night I'd still need: a scheduler/orchestrator to trigger
ingestion then `dbt build`, retry/alerting logic for when a source is late or
a test fails, and something on the consumption side (dashboard, export job)
that actually uses the mart — dbt only guarantees the middle transformation
step is correct and repeatable, not that the pipeline runs or that anyone
ever sees the result.
