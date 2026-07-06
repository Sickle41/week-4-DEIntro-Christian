# DECISIONS.md

> Day 3 deliverable. Real data engineers leave a trail of *why*, not just *what*.
> Keep this short and honest — a few sentences per question. You're defending
> the calls you made moving a working SQL pipeline into dbt.

## 1. Your models have no CREATE TABLE. Where did the DDL go, and why is that dbt's job?

In Week 2 *you* wrote `CREATE TABLE ... AS SELECT`. In dbt every model is a bare
SELECT and materialization lives in `dbt_project.yml`. What does taking DDL out
of your hands buy you — and what did it cost you?

## 2. `ref()` looks like extra typing. `FROM clean_orders` would have worked. Why bother?

Name the two concrete things `{{ ref('...') }}` did for you this week that a
hard-coded table name can't. (Hint: one is about *order*, one is about the
*graph*. If you're stuck, delete a ref and run `dbt docs generate` again.)

## 3. Open `target/compiled/.../customer_order_summary.sql`. What did you find, and why does "dbt is just a compiler" matter?

Compare the compiled file to your model. What did Jinja resolve to? If a
teammate says "dbt is magic and I don't trust it," what would you show them?

## 4. Week 2 you tested code with pytest. This week `dbt test` tested data. What's the difference — and why do you want both?

A pytest suite that's green and a dbt test that's green are promising different
things. What failure does each one catch that the other misses?

## 5. `var('min_orders')` vs Week 2's `$min_orders` bound parameter — same idea or not?

Both keep a value out of the SQL string. When is a dbt var resolved vs when was
the bound parameter resolved, and does the SQL-injection argument from Week 2
still apply here? (Look at the compiled SQL before you answer.)

## 6. Staging models are views; the mart is a table. Defend that — then name a case where you'd flip one.

`dbt_project.yml` made this call for you. Why does it make sense for THIS
pipeline's shapes and sizes — and what change (data volume, query pattern,
freshness need) would make you override it for a specific model?

## 7. What did dbt NOT do for you this week?

You still ran `generate_data.py` and `load_raw.py` by hand, and nothing here
schedules, ingests, or serves. Where does dbt's job start and end in the
pipelines you built in Weeks 1-3 — and what's still missing before this runs
unattended every night?
