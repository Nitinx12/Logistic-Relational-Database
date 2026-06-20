# LRDB — Trucking & Logistics Data Platform

LRDB is a batch-oriented analytics platform built around a trucking and logistics operation. It takes a set of flat source files, stages them in MongoDB, syncs them incrementally into a PostgreSQL warehouse, and then layers data quality checks, parameterized reporting functions, financial validation, and operational alerting on top of that warehouse.

This README covers the whole repository at a glance. For the full system design, see `docs/architecture.md`. For how the tables relate to each other, see `docs/datacatlog.md`.

## What This Project Does

The platform models a typical trucking operation end to end: customers book loads, loads are carried over routes, trips execute those loads with a driver, truck, and trailer, and a handful of supporting tables record what actually happened — delivery events, fuel purchases, maintenance, and safety incidents. Two rollup tables summarize driver and truck performance month by month, and three monitoring tables (`kpi_thresholds`, `operational_alerts`, `financial_validation_log`) watch over the data and flag problems.

Everything downstream of the warehouse — data quality, reporting, alerting — only reads from PostgreSQL. Nothing writes back upstream to MongoDB, and MongoDB never writes back to the source CSVs.

## Tech Stack

| Layer | Tools |
|---|---|
| Language / packaging | Python, managed with `uv` |
| Staging store | MongoDB, accessed via PyMongo |
| Warehouse | PostgreSQL, accessed via `psycopg2` and SQLAlchemy |
| Data shaping | pandas |
| Warehouse logic | PL/pgSQL functions, stored procedures, and triggers, plus the `dblink` extension for autonomous transactions |
| Reporting output | Markdown reports with PNG charts (pandas, matplotlib, seaborn) |

## Repository Layout

```
LRDB
├─ assets/              PNGs referenced by reports/*.md
├─ dataset/             14 source CSVs (13 entities + 2 monthly rollups)
├─ docs/
│  ├─ architecture.md   full system design and data flow
│  └─ datacatlog.md     table relationships and entity-relationship diagram
├─ reports/
│  ├─ customer_report.md
│  ├─ driver_report.md
│  └─ truck_report.md
├─ scripts/
│  ├─ mongo_to_postgres.py   incremental Mongo -> Postgres ETL
│  └─ README.md
├─ sql/                 14 numbered scripts: reset, EDA, reporting, QA, ops
├─ tests/               6 data-quality stored procedures, one per core table
├─ utils/
│  ├─ connection.py     loads and validates DB credentials from .env
│  ├─ engine.py         builds the Postgres engine and Mongo client
│  ├─ logger.py         stage-aware logger factory
│  └─ README.md
├─ main.py              orchestration entry point
├─ watermark.json       ETL progress checkpoint, auto-generated
├─ pyproject.toml / uv.lock / .python-version
└─ LICENSE
```

## Architecture at a Glance

```mermaid
flowchart LR
    CSV[("dataset/*.csv")] -.-> MONGO[("MongoDB")]
    MONGO -- "updated_at > watermark" --> ETL["mongo_to_postgres.py"]
    ETL <--> WM[("watermark.json")]
    ETL -- "append-only insert" --> PG[("PostgreSQL warehouse")]
    PG --> DQ["data quality procs"]
    PG --> ANALYTICS["reporting functions"] --> REPORTS[["reports/*.md"]]
    PG -.-> TRIGGER["financial validation trigger"] --> FVL[("financial_validation_log")]
    FEEDBACK["operational feedback loop"] --> PG
    FEEDBACK --> ALERTS[("operational_alerts")]
```

The dotted line into MongoDB marks a real gap: nothing in this repository documents how the source CSVs actually get loaded into MongoDB in the first place. See the limitations section below.

The warehouse itself has no declared foreign keys anywhere except primary keys on the three monitoring tables. Every relationship between tables is inferred from matching `*_id` column names rather than enforced by PostgreSQL. The central chain is:

```
customers ──┐
            ├──▶ loads ──▶ trips ──▶ (drivers + trucks + trailers)
routes ─────┘                │
                             ├──▶ delivery_events  (+ facilities)
                             ├──▶ fuel_purchases    (+ trucks, drivers)
                             └──▶ safety_incidents  (+ trucks, drivers)

maintenance_records ──▶ trucks
```

Full table-by-table mapping and the entity-relationship diagram are in `docs/datacatlog.md`.

## Getting Started

### 1. Prerequisites

- Python 3.x, managed via [`uv`](https://docs.astral.sh/uv/) (the project ships `pyproject.toml`, `uv.lock`, and `.python-version`, so `uv` will pick up the right interpreter automatically)
- A running PostgreSQL instance with the `dblink` extension available (used by the financial validation trigger in `sql/13`)
- A running MongoDB instance, pre-loaded with the entity collections (see the limitations section below — how the source CSVs get into MongoDB is not covered by this repository)
- `git`

### 2. Clone the repository

```bash
git clone <repository-url> LRDB
cd LRDB
```

Replace `<repository-url>` with the actual clone URL for this repo (HTTPS or SSH, depending on how it is hosted).

### 3. Install dependencies

```bash
uv sync
```

This creates a `.venv` in the project root and installs everything pinned in `uv.lock`. If you would rather use plain `pip`, a `requirements.txt` can be generated from the lock file with `uv export --format requirements-txt > requirements.txt` and installed in a virtual environment of your choice.

### 4. Configure environment variables

Create a `.env` file at the project root:

```env
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DATABASE=your_db
POSTGRES_USERNAME=your_user
POSTGRES_PASSWORD=your_password

MONGO_URI=mongodb://localhost:XXXXX
MONGO_DB=your_mongo_db
```

`utils/connection.py` validates all seven variables are present the moment it is imported, so a missing credential fails immediately at startup rather than partway through a run. Keep `.env` out of version control — it should already be covered by `.gitignore`.

### 5. Run the ETL

```Python
uv run python scripts/mongo_to_postgres.py                            # full incremental sync, all collections
uv run python scripts/mongo_to_postgres.py --collection trucks         # one collection only
uv run python scripts/mongo_to_postgres.py --collection trucks --table trucks_raw
uv run python scripts/mongo_to_postgres.py --full-refresh              # drops and reloads everything, ignores watermark
```

(Drop the `uv run` prefix if you activated the virtual environment yourself with `source .venv/bin/activate`.)

This pulls each MongoDB collection in batches of 25,000 documents, keeping only documents newer than the saved watermark, casts columns into PostgreSQL types, and appends them into the matching table. See `docs/incremental.md` for a full walkthrough of how the watermark logic, type mapping, and table creation work underneath.

### 6. Build the warehouse and run the SQL layers

The `sql/` directory is numbered for sequential execution. Run each script against your PostgreSQL database with `psql` (or any SQL client), in order:

```bash
psql "$DATABASE_URL" -f sql/01_lp_drop_all_tables.sql
psql "$DATABASE_URL" -f sql/02_list_table_columns.sql
# ...continue through sql/14_lp_operational_feedback.sql
```

| Range | Purpose |
|---|---|
| `01`–`03` | Drop-all-tables reset and schema/row-count inspection |
| `04`–`05` | Exploratory analysis: fuel spend and fleet composition |
| `06`–`11` | Parameterized reporting functions (customers, drivers, trucks, routes, sales, facilities) |
| `12`–`13` | Metrics reconciliation and the financial validation trigger |
| `14` | Operational feedback loop and alerting |

### 7. Run the data quality procedures

```SQL
CALL proc_customer_data_quality();
CALL proc_driver_data_quality();
CALL proc_delivery_events_data_quality();
CALL proc_loads_data_quality();
CALL proc_routes_data_quality();
CALL proc_trucks_data_quality();
```

Each procedure checks its table for nulls, duplicates, invalid formats, out-of-range values, and cross-field inconsistencies. A clean table raises a `NOTICE` and passes silently; a problem raises an `EXCEPTION` listing every failed check with its record count. Some checks are deliberately `NOTICE`-only warnings rather than hard failures, where the underlying business rule has not yet been confirmed against real data — for example, the years-of-experience-versus-age check on drivers.

## Components

**`dataset/`** — fourteen source CSVs: six core entities (`customers`, `drivers`, `trucks`, `trailers`, `routes`, `facilities`), six operational/event tables (`loads`, `trips`, `delivery_events`, `fuel_purchases`, `maintenance_records`, `safety_incidents`), and two monthly rollups (`driver_monthly_metrics`, `truck_utilization_metrics`).

**`scripts/`** — the Mongo-to-Postgres ETL described above, plus its own README.

**`utils/`** — shared infrastructure used by every Python script in the project: `connection.py` for credentials, `engine.py` for the actual SQLAlchemy/PyMongo connection objects (pooled, with `pool_pre_ping=True`), and `logger.py` for stage-aware logging (`extraction`, `transformation`, or `loading`), writing timestamped logs under `logs/<stage>/`.

**`sql/`** — fourteen numbered scripts covering reset/inspection, exploratory analysis, the reporting-function API, financial validation (via a `dblink`-based autonomous transaction so rejected records are still logged even when the main transaction rolls back), and the operational alerting loop.

**`tests/`** — six data-quality stored procedures, one per core table, each independently callable.

**`reports/`** — markdown reports generated from the `sql/06`–`08` reporting functions, illustrated with PNGs from `assets/`. `customer_report.md` covers portfolio revenue, segmentation, and delivery performance across 200 customers. `truck_report.md` covers fleet revenue, fuel efficiency by make, and maintenance cost concentration across 120 trucks. `driver_report.md` follows the same pattern for drivers.

**`docs/`** — `architecture.md` for the full system design and data flow, and `datacatlog.md` for the table relationship map and entity-relationship diagram.

## Logs

`utils/logger.py` writes timestamped log files under `logs/<stage>/<name>_<timestamp>.log` for whichever stage a script declares (`extraction`, `transformation`, or `loading`). Console output is `INFO` and above; the file itself captures `DEBUG` and above. This directory is created automatically the first time a script runs, so there is nothing to set up ahead of time.

## Troubleshooting

- **`EnvironmentError` on startup** — one of the seven required variables is missing from `.env`. Check the variable names exactly match those listed in the configuration step above.
- **ETL pulls every row every time** — the collection's documents are missing the `updated_at` field, or `watermark.json` was deleted or reset. Without a watermark, the script always does a full pull for that collection.
- **A new MongoDB field shows up as text instead of a number in Postgres** — add the field name to `BIGINT_COLS` or `NUMERIC_COLS` inside `extract_schema_and_flatten()` in `scripts/mongo_to_postgres.py`.
- **Duplicate rows for the same `*_id` after a re-sync** — expected behavior for mutable records under the current append-only design; see the limitations section below.
- **`dblink` errors when running `sql/13_trg_financial_validation.sql`** — confirm the `dblink` extension is installed and enabled on the target PostgreSQL database (`CREATE EXTENSION IF NOT EXISTS dblink;`).

## Contributing

This is a small, single-pipeline project rather than a library with a formal contribution process, but the usual workflow applies: branch off, make a change, and make sure the relevant data quality procedures in `tests/` still pass clean against a real warehouse before opening a pull request. If you add a new MongoDB field that should map to `BIGINT` or `NUMERIC` in Postgres, remember to update the hardcoded column sets mentioned in the troubleshooting section above.

## Known Limitations

- **No foreign key enforcement.** Every join across the data quality, reporting, and alerting layers depends on `*_id` naming conventions rather than database-enforced relationships. An orphaned row will not raise a database error anywhere in this stack.
- **The ETL is append-only, not upsert.** A new watermark only guarantees nothing is missed, not that updated records replace old ones. Any table holding mutable records will accumulate duplicate `*_id` rows over time unless something downstream collapses them.
- **Type mapping in the ETL is hand-maintained.** New numeric or integer fields added on the MongoDB side need a matching entry in `BIGINT_COLS` or `NUMERIC_COLS` inside `extract_schema_and_flatten()`, or they fall through to `VARCHAR`.
- **`updated_at` is a hard dependency for incremental sync.** Any collection missing this field is always fully re-pulled.
- **`--full-refresh` is destructive.** It runs `DROP TABLE IF EXISTS` with no backup step built in.
- **The CSV-to-MongoDB loading step is undocumented.** Nothing in this repository describes how `dataset/*.csv` gets into MongoDB in the first place.
- **Report-generation mechanics are unconfirmed.** `main.py` is the likely orchestrator for `reports/*.md` and `assets/*.png`, but the exact build process is not detailed anywhere yet.
- **Some data-quality rules are unvalidated warnings**, pending confirmation against more data before being promoted to hard failures.

## License

See `LICENSE`.