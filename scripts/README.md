# ETL Scripts — Mongo → Postgres Sync

## What's in here

| File | Purpose |
|---|---|
| `mongo_to_postgres.py` | Main ETL script. Pulls collections from MongoDB and appends new/changed rows into PostgreSQL. |
| `utils/connection.py` *(expected, not uploaded)* | Holds Postgres + Mongo connection constants (`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DATABASE`, `POSTGRES_USERNAME`, `POSTGRES_PASSWORD`, `MONGO_URI`, `MONGO_DB`). |
| `utils/logger.py` *(expected, not uploaded)* | Provides `get_logger(name, log_file)` used for run logs. |
| `watermark.json` *(auto-generated)* | Stores the last synced `updated_at` timestamp per collection. Created/updated automatically — don't edit by hand. |

The script auto-detects `PROJECT_ROOT` as the parent of its own folder, and expects `utils/` to live there as a sibling. So your layout should look like:

```
project_root/
├── utils/
│   ├── connection.py
│   └── logger.py
├── scripts/
│   └── mongo_to_postgres.py
└── watermark.json   ← generated after first run
```

## How it works (quick version)

1. **Connect** to MongoDB using `MONGO_URI` / `MONGO_DB`.
2. **Check the watermark** (`watermark.json`) for the collection — the last `updated_at` value synced. No watermark = pull everything.
3. **Query Mongo** for docs where `updated_at > watermark`, sorted ascending, pulled in batches of 25,000.
4. **Flatten + type-cast** each batch with pandas:
   - drops Mongo's `_id`
   - sanitizes column names to be Postgres-safe
   - maps columns to types using hardcoded sets: `BIGINT_COLS`, `NUMERIC_COLS`, date/timestamp field-name rules, and everything else falls to `VARCHAR` (or `JSONB` if it's a dict/list).
5. **Ensure the target table exists** in Postgres — creates it on first run, or adds any missing columns via `ALTER TABLE`. On `--full-refresh`, it drops and recreates the table instead.
6. **Append the batch** into Postgres with `execute_values` (bulk insert — no upsert/dedupe logic, it's append-only).
7. **Save the watermark** after each batch, so a crash mid-run doesn't force a full re-pull.
8. Repeats for every collection in `ALL_COLLECTIONS` (or just one, if `--collection` is passed).

## Running it

```bash
# sync everything, incrementally
python mongo_to_postgres.py

# sync just one collection
python mongo_to_postgres.py --collection trucks

# sync one collection into a differently-named table
python mongo_to_postgres.py --collection trucks --table trucks_raw

# wipe and reload everything from scratch (ignores watermark)
python mongo_to_postgres.py --full-refresh
```

## Things to know before you run it

- **Append-only.** There's no upsert — if a doc gets updated in Mongo and re-synced, you'll get a *new row* in Postgres, not a replaced one. Fine for event-style data, not fine for mutable records unless something downstream (e.g. dedup view, dbt model) handles it.
- **Type mapping is hardcoded.** New numeric/bigint fields added to Mongo docs won't get the right Postgres type unless you add them to `BIGINT_COLS` / `NUMERIC_COLS` in `extract_schema_and_flatten()`.
- **`--full-refresh` is destructive** — it does `DROP TABLE IF EXISTS` before reloading. Don't run it on a table other things depend on without backing up first.
- **Watermark requires `updated_at`** on every doc. Collections without that field will always do a full pull (no incremental filtering).