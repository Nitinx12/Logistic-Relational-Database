# How the Mongo to Postgres Incremental Sync Works

This document walks through `mongo_to_postgres.py` piece by piece and explains the reasoning behind each part, not just what the code does but why it is built that way. It is meant for someone who has to maintain, debug, or extend this script later and does not want to re-read every line to remember how the pieces fit together.

## The Big Picture

The script moves data out of MongoDB collections and into matching PostgreSQL tables. It does this on a schedule (or on demand), and instead of copying every document every time, it only pulls documents that changed since the last successful run. It figures out "since the last run" using a timestamp it saves to a local JSON file, called a watermark.

At a high level, one run looks like this:

```
                      ┌──────────────────────────┐
                      │   watermark.json         │
                      │   (last updated_at seen  │
                      │   per collection)        │
                      └─────────────┬────────────┘
                                    │ read
                                    ▼
   MongoDB collection  ──filter──▶  documents with
   (e.g. "loads")      updated_at   updated_at > watermark
                       greater than
                       watermark
                                    │
                                    ▼
                       ┌─────────────────────────┐
                       │  pandas DataFrame       │
                       │  (one batch, up to      │
                       │   25,000 rows)          │
                       └─────────────┬───────────┘
                                    │ clean + type
                                    ▼
                       drop _id, rename columns,
                       cast to BIGINT / NUMERIC /
                       DATE / TIMESTAMP / JSONB /
                       VARCHAR
                                    │
                                    ▼
                       ┌─────────────────────────┐
                       │  PostgreSQL table       │
                       │  (created if missing,   │
                       │   columns added if new) │
                       └─────────────┬───────────┘
                                    │ INSERT (append only)
                                    ▼
                       update watermark.json with
                       the max updated_at seen in
                       this batch
```

That loop repeats batch by batch until the collection is exhausted, then the script moves on to the next collection.

## Configuration at the Top

A few constants drive the whole script:

- `BATCH_SIZE = 25000` — how many MongoDB documents get pulled into memory and processed as one pandas DataFrame before being inserted into Postgres. This keeps memory usage bounded even for collections with millions of documents.
- `UPDATED_AT_FIELD = "updated_at"` — the field the script trusts to know whether a document is new or changed. Every collection is expected to have this field if incremental loading is going to work for it.
- `WATERMARK_FILE` — a single JSON file sitting one directory above the script (the project root), holding one timestamp per collection.
- `ALL_COLLECTIONS` — the full list of collections this script knows about. If you run the script with no arguments, it will loop through every name in this list and sync each one into a Postgres table of the same name.

Connection details for Mongo and Postgres are not in this file at all. They are imported from `utils.connection`, so credentials and hosts live in one place and this script just borrows them.

## Watermark Management

This is the mechanism that makes the sync "incremental" instead of a full reload every time.

**`load_watermark(collection_name)`** opens `watermark.json`, looks up the entry for that collection, and turns the stored string back into a Python `datetime`. If the file does not exist, or the collection has no entry yet, it returns `None`, which tells the rest of the script "there is no watermark, pull everything."

**`save_watermark(collection_name, max_ts)`** does the reverse. It takes the newest `updated_at` value seen in a batch, formats it as an ISO 8601 string, and writes it back into the JSON file under that collection's key. A couple of details worth knowing:

- It reads the whole file first and only overwrites the one key for the current collection, so syncing one collection does not wipe out the saved watermarks for the others.
- It appends a trailing "Z" if the timestamp does not already have timezone information, to signal UTC.
- If `max_ts` is null (meaning the batch had no usable timestamp), it simply does nothing and leaves the previous watermark alone.

One thing to flag for whoever maintains this: the watermark is saved after every batch within a collection, not just once at the end. That is a deliberate safety net — if the script crashes halfway through a huge collection, the next run will resume from the last completed batch instead of starting over. The tradeoff is that if a batch is inserted into Postgres but the watermark write fails right after (power loss, disk full, etc.), the next run could re-pull and re-insert that batch, creating duplicate rows, since this script is append-only and does not deduplicate.

## Reading From MongoDB in Batches

**`fetch_incremental_batches(collection, watermark)`** builds the Mongo query. If a watermark exists, the query becomes `{"updated_at": {"$gt": watermark}}`, meaning strictly newer documents only. If there is no watermark, the query is empty, meaning every document in the collection.

The result is sorted by `updated_at` ascending and pulled through a cursor with `batch_size(25000)` to control how MongoDB streams data over the wire. The function itself is a generator: it accumulates documents into a Python list, and as soon as that list reaches 25,000 entries, it yields the batch and starts a new list. Whatever is left over after the cursor is exhausted gets yielded as a final, smaller batch.

Sorting by `updated_at` matters for correctness, not just tidiness. Because the watermark is saved using the maximum timestamp seen in the most recently processed batch, the script depends on batches arriving in increasing timestamp order. If documents were not sorted, a batch could contain a high timestamp early and a low one late, and the watermark logic could still work out, but the guarantee that "everything before the watermark has already been synced" would no longer hold cleanly.

## Turning a Batch Into a Typed DataFrame

This is the part of the script with the most logic, so it deserves the most attention.

**`extract_schema_and_flatten(df)`** takes the raw pandas DataFrame built directly from MongoDB documents and does three jobs at once: clean it up, decide a PostgreSQL type for every column, and convert the actual Python values into something psycopg2 can insert safely.

Step by step:

1. **Drop `_id`.** MongoDB's own object id is never carried into Postgres. The target tables are expected to either not need a primary key or to define their own.

2. **Sanitize column names.** `_pg_safe_identifier` replaces anything that is not a letter, digit, or underscore with an underscore, prefixes the name with an underscore if it starts with a digit, lowercases it, and truncates to 63 characters (Postgres' identifier length limit). This protects against MongoDB field names that would otherwise be illegal or awkward as SQL column names.

3. **Decide a type for every column**, using a strict order of checks:

   - **Timestamps.** Columns literally named `updated_at`, `scheduled_datetime`, or `actual_datetime` are parsed with `pd.to_datetime` and mapped to Postgres `TIMESTAMP`.
   - **Dates.** Any column ending in `_date`, plus the special cases `date_of_birth` and `month`, are parsed and truncated down to a calendar date (no time component) and mapped to `DATE`.
   - **Big integers.** A hardcoded set, `BIGINT_COLS`, lists every field across all collections that should be treated as a whole number, things like `trips_completed`, `odometer_reading`, `weight_lbs`. These go through `pd.to_numeric` and get cast to pandas' nullable `Int64` type so that missing values do not force the whole column into floating point.
   - **Numerics.** Another hardcoded set, `NUMERIC_COLS`, covers decimal-bearing fields like `total_revenue`, `average_mpg`, `latitude`, `fuel_surcharge_rate`. These map to Postgres `NUMERIC`.
   - **Everything else** falls through to a final check: if the first non-null value in the column is a Python `dict` or `list`, the whole column is treated as `JSONB` and every value is serialized with `json.dumps`. Otherwise, the column becomes `VARCHAR` and every value is coerced to a plain string.

   Because the BIGINT and NUMERIC column names are hardcoded rather than inferred from the data, this is really a hand-maintained schema masquerading as a type-detection routine. If a new numeric field gets added to a Mongo collection and nobody adds its name to one of these two sets, it will silently end up as `VARCHAR` in Postgres instead of a proper number.

4. **Normalize missing values.** For every typed column, the code does `df[col].astype(object).where(pd.notnull(df[col]), None)`. This is necessary because pandas' native null markers (`NaT`, `NaN`, pandas' own `pd.NA`) are not things psycopg2 knows how to insert directly. Converting them to plain Python `None` lets psycopg2 turn them into proper SQL `NULL`.

The function returns both the cleaned DataFrame and a dictionary mapping column name to chosen Postgres type, which the rest of the pipeline uses to build or extend the actual table.

## Creating or Updating the Postgres Table

**`ensure_table_schema(table_name, pg_types, is_first_batch, is_full_refresh)`** runs once per batch, but its behavior changes depending on the flags:

- If this run was started with `--full-refresh` and this is the very first batch of the very first collection in this call, the existing table is dropped outright with `DROP TABLE IF EXISTS`. This is the only place data is ever destroyed in this script.
- It then checks `information_schema.tables` to see whether the table already exists.
  - If it does not exist, it builds a `CREATE TABLE` statement from scratch using the column-to-type mapping produced by `extract_schema_and_flatten`.
  - If it does exist, it compares the incoming column names against `information_schema.columns` and runs `ALTER TABLE ... ADD COLUMN` for any column present in this batch but missing from the table.

This means the table's schema can grow over time as new fields show up in MongoDB documents, but it never shrinks or changes an existing column's type automatically. If a column that used to hold numbers starts holding text in a later document, this script will not catch or fix that; it will likely cause an insert error.

## Inserting the Data

**`append_dataframe(df, table_name)`** is intentionally simple. It builds one `INSERT INTO ... VALUES %s` statement and hands it to psycopg2's `execute_values`, which batches the insert efficiently (in chunks of 1000 rows at a time, per the `page_size` argument) rather than issuing one `INSERT` per row.

There is no `ON CONFLICT` clause anywhere in this statement. That is consistent with the script's stated design as an append-only loader: it assumes every row coming through has not been inserted before. If a document that was already synced gets pulled in again (for example, because of the crash scenario described earlier under watermark management), it will be inserted as a brand new row rather than updating the existing one, leading to duplicates rather than corrected data.

## Orchestrating One Collection

**`sync_collection(db, collection_name, table_name, full_refresh)`** ties the pieces above together for a single collection:

1. Load the watermark, unless `full_refresh` was requested, in which case the watermark is ignored entirely so every document gets pulled again.
2. Loop over batches from `fetch_incremental_batches`.
3. For each batch, track the highest `updated_at` value seen so far in `latest_timestamp`.
4. Convert the batch to a typed DataFrame, make sure the destination table has the right shape, and insert the rows.
5. Save the watermark immediately after each successful insert, using the running maximum timestamp.
6. Log a running total of rows inserted.
7. If nothing happened at all, log explicitly that no new records were found, so a quiet successful run is distinguishable from a run that never started.

Any exception raised inside this whole flow is caught at the top, logged with a full stack trace, and reported back as an error string rather than crashing the whole script. That choice matters when syncing many collections in one run: a failure in `trips` should not prevent `customers` or `drivers` from being attempted.

## Orchestrating the Whole Run

**`run(collection_name, table_name, full_refresh)`** is the entry point used by the command line interface.

- If a specific `--collection` was passed, only that one collection is synced (optionally writing to a different table name if `--table` was also passed).
- If nothing was passed, every collection in `ALL_COLLECTIONS` is synced, one after another, into a table with the same name as the collection.
- After everything finishes, it prints a summary. If any collection failed, the script exits with status code 1 and lists every failure, which makes it straightforward to wire this script into a scheduler or CI job that needs to know whether the sync actually succeeded.

## Command Line Usage

```
python mongo_to_postgres.py
```
Syncs every collection in `ALL_COLLECTIONS`, incrementally, using whatever watermarks already exist.

```
python mongo_to_postgres.py --collection loads
```
Syncs only the `loads` collection into a Postgres table also named `loads`.

```
python mongo_to_postgres.py --collection loads --table loads_v2
```
Same as above, but writes into a table named `loads_v2` instead.

```
python mongo_to_postgres.py --full-refresh
```
Ignores every watermark, drops each target table before its first batch, and reloads everything from scratch for every collection in the list.

## Things Worth Knowing Before Relying on This Script

- **No deduplication.** Because inserts are append-only with no conflict handling, any situation where a document gets pulled twice (crash recovery, manual re-runs without `--full-refresh`, clock skew on `updated_at`) will produce duplicate rows in Postgres.
- **Schema is partly hand-maintained.** The BIGINT and NUMERIC column name sets are not derived from MongoDB's data, they are typed in by hand. Adding a new numeric field in Mongo requires manually adding it to one of those sets, or it will land in Postgres as text.
- **Column types only ever get added, not changed.** If a field's type changes in MongoDB after the table was created, this script does not alter the existing column type and an insert can fail.
- **Watermarks rely on `updated_at` being reliable.** Collections without this field, or where it is not kept current on every write, will not sync incrementally in any meaningful way; they will either always do a full pull or never pick up changes.
- **The drop-table step in full refresh only triggers on the first batch of a run.** If a full refresh run is somehow interrupted and restarted on the same collection without restarting the whole process, it will not try to drop the table again, since `is_first_batch` is scoped to a single call of `sync_collection`.