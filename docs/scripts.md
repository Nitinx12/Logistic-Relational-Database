# scripts/

Operational scripts for the ETL pipeline: syncing data from Mongo into
Postgres, and testing the PL/pgSQL stored procedures that run against it.
Both scripts import shared config/logging from `utils/` at the project root
and write their logs under `<project_root>/logs/<stage>/`.

| Script | Purpose | Run it |
|---|---|---|
| `incremental.py` | Sync MongoDB collections into Postgres tables | `python scripts/incremental.py` |
| `tests.py` | Run PL/pgSQL stored-procedure tests | `python scripts/tests.py` |

---

## incremental.py

Incremental **MongoDB → PostgreSQL** sync, built on PySpark.

**What it does:**
- Reads each Mongo collection as a distributed Spark DataFrame, pulling only
  documents where `updated_at` is newer than a saved watermark.
- Flattens/casts fields to Postgres-friendly types (timestamps, numerics,
  JSONB for nested docs/arrays) and auto-creates or alters the target table
  to match.
- **Plain INSERT only — no upsert, no primary key, no `ON CONFLICT`.** The
  target table is a history-of-changes table: if a document changes twice,
  you get two rows, not one row updated in place. This is deliberate (see
  the file's own docstring for the reasoning).
- Writes are chunked (`execute_values`) and parallelized per Spark
  partition. If a chunk fails (e.g. a CHECK constraint trips on one bad
  row), it retries that chunk row-by-row so only the bad row is quarantined
  — the rest of the chunk still gets inserted.
- The watermark lives in a Postgres table (`public.etl_watermark`), not a
  local JSON file, so it's atomic and safe under concurrent runs.
- Prints a Rich summary table at the end (rows synced, new vs. updated,
  rejected, status per collection) and logs full detail to
  `logs/extraction/incremental_sync_<timestamp>.log`.

**Usage:**
```bash
python scripts/incremental.py                       # sync all collections
python scripts/incremental.py --collection drivers   # sync just one
python scripts/incremental.py --collection drivers --table drivers_v2
python scripts/incremental.py --full-refresh         # drop target table(s), reload everything
```

**Requires:** `PYSPARK_PYTHON`/local jars for the Mongo Spark connector +
Postgres JDBC driver (expected under `<project_root>/jars/`), plus the same
Postgres/Mongo env vars as the rest of the project (`utils/connection.py`).

**Exit code:** `1` if any collection hard-fails; `0` otherwise (collections
with some rejected rows still count as a partial success).

---

## tests.py

Runs every PL/pgSQL test file under `tests/*.sql` against the database and
reports pass/fail.

**Convention:** each `.sql` file is one independent test.
- **PASS** — the file executes with no error.
- **FAIL** — it raises an error (typically `RAISE EXCEPTION` inside a
  `DO $$ ... $$` block or stored-procedure call, on a failed assertion).

Each test runs in its own transaction which is always rolled back
afterward, so tests never leave data behind or affect each other.

**What it shows per test:**
- The `[PASS]`/`[FAIL]` status and how long it took.
- Any `RAISE NOTICE` / `INFO` / `WARNING` output the procedure emitted
  while running — the same messages you'd see running the file in `psql`.
- Any rows returned by the file's final statement (a `SELECT`, or a `CALL`
  with `OUT` parameters).

**Usage:**
```bash
python scripts/tests.py                    # run all tests
python scripts/tests.py --tests-dir ../tests
python scripts/tests.py -v                 # also print full error detail on failure
```

**Logs:** every run and its summary go to
`logs/tests/tests-log_<timestamp>.log` as well as the console.

**Exit code:** `1` if any test failed; `0` if all passed.

---

## Shared conventions

- Both scripts resolve `<project_root>` from their own file location and
  add it to `sys.path`, so `utils.*` imports work no matter which
  directory you run them from.
- Both use `utils/logger.py::get_logger(stage, name)` — console gets
  `INFO`+, the log file gets everything down to `DEBUG` (full tracebacks,
  per-row rejection detail, etc.).
- DB credentials come from `utils/connection.py`, loaded from a `.env` file
  at the project root (`POSTGRES_*`, `MONGO_URI`, `MONGO_DB`).