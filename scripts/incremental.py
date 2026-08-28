"""
incremental.py

Incremental MongoDB -> PostgreSQL sync using PySpark.

What changed vs. the old mongo_to_postgres.py:
  - Plain INSERT, no upsert. "New or updated" just means
    `updated_at > watermark` in Mongo — every matching document is read and
    appended as a new row. There's no primary key / natural key anywhere in
    this script, and no ON CONFLICT.
  - IMPORTANT CONSEQUENCE: this makes the target table a history-of-changes
    table, not a current-state table. If a document's `updated_at` changes
    twice, you get two rows for it (one per sync that picked it up), not one
    row updated in place. If you need one row per entity, you need a primary
    key and an upsert (ON CONFLICT ... DO UPDATE) — that's what a PK is for.
    This script deliberately doesn't do that.
  - No stg_<table> staging tables anywhere. Insert happens directly against
    the target table.
  - watermark.json removed entirely. The watermark is now a row in a Postgres
    table (public.etl_watermark) — atomic, queryable, no local file to lose
    or fight over during concurrent runs.
  - Logs no longer land inside the script's own folder. utils/logger.py had
    a relative path bug (log_dir = os.path.join("logs", stage), resolved
    against cwd instead of the project root) — fixed there, so this now
    lands in <project_root>/logs/extraction/ via the shared get_logger().
  - pandas + pymongo row-by-row batching -> PySpark. Mongo is read as a
    distributed DataFrame, transformed, then inserted with chunked
    (execute_values) writes fired in parallel per Spark partition.
"""

import argparse
import json
import logging
import os
import sys
import warnings
from datetime import datetime, timezone
from typing import Optional

# Silence Python-level noise (DeprecationWarning, FutureWarning, etc. from
# pyspark/psycopg2/pandas-adjacent libs) so the terminal only shows this
# script's own logger output.
warnings.filterwarnings("ignore")

# Force Spark to use THIS interpreter's absolute path for its Python workers.
# sys.executable is always absolute — set before importing pyspark so it's in
# place before any SparkContext/worker-launch code reads it. Without this,
# Spark can end up launching workers with a relative ".venv\Scripts\python.exe"
# that only resolves if the process happens to be run from the project root —
# cd into scripts/ (or anywhere else) and CreateProcess fails to find it.
os.environ["PYSPARK_PYTHON"] = sys.executable
os.environ["PYSPARK_DRIVER_PYTHON"] = sys.executable

import psycopg2
from psycopg2.extras import execute_values
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    ArrayType, DateType, DecimalType, DoubleType, FloatType,
    LongType, MapType, StringType, StructType, TimestampType,
)
from rich.console import Console
from rich.table import Table
from rich import box

# py4j (the Java<->Python bridge pyspark runs on) logs its own INFO/DEBUG
# chatter straight to stderr, separate from Spark's own log4j output below —
# quiet it here too.
logging.getLogger("py4j").setLevel(logging.ERROR)

# Adjust path to find utils and project root
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from utils.connection import (
    POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DATABASE,
    POSTGRES_USERNAME, POSTGRES_PASSWORD, MONGO_URI, MONGO_DB,
)
from utils.logger import get_logger

# =========================================================
# LOGGING
# =========================================================
# utils/logger.py now resolves log_dir from the project root instead of the
# caller's cwd, so this lands in <project_root>/logs/extraction/ no matter
# which directory the script is invoked from.
logger = get_logger("extraction", "incremental_sync")

# get_logger() may attach its own console StreamHandler in addition to a
# file handler. Rich owns the terminal now (banner + summary table below),
# so drop any handler that isn't a FileHandler to avoid every log line
# getting printed twice in two different styles. Full detail (including
# tracebacks) still lands in the log file untouched.
for _h in list(logger.handlers):
    if isinstance(_h, logging.StreamHandler) and not isinstance(_h, logging.FileHandler):
        logger.removeHandler(_h)

console = Console()

# =========================================================
# CONFIG
# =========================================================
UPDATED_AT_FIELD = "updated_at"
CHUNK_SIZE = 5000        # rows per execute_values call, per Spark partition
SPARK_PARTITIONS = 8     # parallel writer partitions (this is the "chunking")

ALL_COLLECTIONS = [
    "customers", "delivery_events", "drivers", "driver_monthly_metrics",
    "facilities", "fuel_purchases", "loads", "maintenance_records",
    "routes", "safety_incidents", "trailers", "trips", "trucks",
    "truck_utilization_metrics",
]

TIMESTAMP_COLS = {"updated_at", "created_at", "scheduled_datetime", "actual_datetime"}

# Each collection's real natural/primary key, used ONLY to label rejected
# rows in logs/summary with something a human can look up in Mongo — this
# script still does plain INSERT (see module docstring), so this is not a
# constraint and never drives an ON CONFLICT.
#
# "trips" is stored in Mongo as "trip-id" (hyphen, unlike every other
# collection's "<x>_id" convention). _pg_safe_identifier() turns any
# non-alphanumeric character into "_", so by the time flatten_and_cast()
# runs, the column is named "trip_id" like everything else — map to the
# post-sanitization name here.
PRIMARY_KEYS = {
    "customers": "customer_id",
    "drivers": "driver_id",
    "delivery_events": "event_id",
    "facilities": "facility_id",
    "fuel_purchases": "fuel_purchase_id",
    "loads": "load_id",
    "maintenance_records": "maintenance_id",
    "routes": "route_id",
    "safety_incidents": "incident_id",
    "trailers": "trailer_id",
    "trips": "trip_id",  # source field: "trip-id"
    "trucks": "truck_id",
    "truck_utilization_metrics": "truck_id",
    "driver_monthly_metrics": "driver_id",
}

BIGINT_COLS = {
    'credit_terms_days', 'annual_revenue_potential', 'detention_minutes',
    'trips_completed', 'total_miles', 'years_experience', 'dock_doors',
    'weight_lbs', 'pieces', 'accessorial_charges', 'odometer_reading',
    'typical_distance_miles', 'typical_transit_days', 'trailer_number',
    'length_feet', 'model_year', 'actual_distance_miles', 'maintenance_events',
    'unit_number', 'acquisition_mileage', 'tank_capacity_gallons',
}

NUMERIC_COLS = {
    'total_revenue', 'average_mpg', 'total_fuel_gallons', 'on_time_delivery_rate',
    'average_idle_hours', 'latitude', 'longitude', 'gallons', 'price_per_gallon',
    'total_cost', 'revenue', 'fuel_surcharge', 'labor_hours', 'labor_cost', 'parts_cost',
    'downtime_hours', 'base_rate_per_mile', 'fuel_surcharge_rate', 'vehicle_damage_cost',
    'cargo_damage_cost', 'claim_amount', 'actual_duration_hours', 'fuel_gallons_used',
    'idle_time_hours', 'maintenance_cost', 'utilization_rate',
}


def _pg_safe_identifier(name: str) -> str:
    import re
    safe = re.sub(r"[^0-9A-Za-z_]", "_", name)
    if not safe or safe[0].isdigit():
        safe = f"_{safe}"
    return safe[:63].lower()


# =========================================================
# WATERMARK — Postgres table, no more watermark.json
# =========================================================

def get_pg_connection():
    return psycopg2.connect(
        host=POSTGRES_HOST, port=POSTGRES_PORT, dbname=POSTGRES_DATABASE,
        user=POSTGRES_USERNAME, password=POSTGRES_PASSWORD,
    )


def ensure_watermark_table():
    with get_pg_connection() as conn, conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.etl_watermark (
                table_name     VARCHAR(63) PRIMARY KEY,
                last_watermark TIMESTAMP,
                updated_at     TIMESTAMP NOT NULL DEFAULT now()
            );
        """)


def load_watermark(table_name: str) -> Optional[datetime]:
    with get_pg_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT last_watermark FROM public.etl_watermark WHERE table_name = %s",
            (table_name,),
        )
        row = cur.fetchone()
        return row[0] if row and row[0] else None


def save_watermark(table_name: str, max_ts):
    if max_ts is None:
        return
    with get_pg_connection() as conn, conn.cursor() as cur:
        cur.execute("""
            INSERT INTO public.etl_watermark (table_name, last_watermark, updated_at)
            VALUES (%s, %s, now())
            ON CONFLICT (table_name)
            DO UPDATE SET last_watermark = EXCLUDED.last_watermark, updated_at = now();
        """, (table_name, max_ts))


# =========================================================
# SPARK
# =========================================================

# Local jars (project_root/jars/) instead of spark.jars.packages — no Maven
# fetch at runtime, and this pins the exact jar set you're actually testing
# against: mongo-spark-connector_2.12-10.4.0 + its bson/driver deps, plus the
# postgresql JDBC driver.
JARS_DIR = os.path.join(PROJECT_ROOT, "jars")


def _local_jars() -> str:
    if not os.path.isdir(JARS_DIR):
        logger.warning(f"Jars directory not found: {JARS_DIR} — Spark will start with no extra jars on the classpath.")
        return ""
    jar_paths = [
        os.path.join(JARS_DIR, f) for f in sorted(os.listdir(JARS_DIR)) if f.lower().endswith(".jar")
    ]
    if not jar_paths:
        logger.warning(f"No .jar files found in {JARS_DIR}.")
    return ",".join(jar_paths)


def get_spark(app_name: str = "incremental_sync") -> SparkSession:
    builder = (
        SparkSession.builder
        .appName(app_name)
        .config("spark.mongodb.read.connection.uri", MONGO_URI)
        .config("spark.pyspark.python", sys.executable)
        .config("spark.pyspark.driver.python", sys.executable)
        # Stops the "[Stage 0:====> (3 + 5) / 8]" progress bars that spam
        # stdout during every read/write.
        .config("spark.ui.showConsoleProgress", "false")
    )
    jars = _local_jars()
    if jars:
        # spark.jars puts these on both the driver and executor classpath —
        # no spark-submit --jars step needed for local-mode runs.
        builder = builder.config("spark.jars", jars)
    spark = builder.getOrCreate()
    # setLogLevel talks to the underlying log4j logger directly. FATAL (not
    # ERROR) is intentional: a failed task logs its exception at ERROR
    # severity from the JVM side regardless, which is exactly the giant
    # Java stack trace we're trying to keep off the terminal. We catch and
    # summarize failures ourselves in Python (see sync_collection / the
    # rich summary table), so we don't need Spark's own copy on screen too
    # — the full detail still reaches the log file via logger.error(...).
    spark.sparkContext.setLogLevel("FATAL")
    return spark


def read_incremental(spark: SparkSession, collection_name: str, watermark: Optional[datetime]) -> DataFrame:
    reader = (
        spark.read.format("mongodb")
        .option("database", MONGO_DB)
        .option("collection", collection_name)
    )
    if watermark:
        wm_str = watermark.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        pipeline = f'[{{"$match": {{"{UPDATED_AT_FIELD}": {{"$gt": {{"$date": "{wm_str}"}}}}}}}}]'
        reader = reader.option("aggregation.pipeline", pipeline)
    return reader.load()


def flatten_and_cast(df: DataFrame):
    """Drop _id, sanitize column names, cast to target PG-facing types.
    Returns (df, jsonb_cols) — jsonb_cols is the set of columns that were
    complex Mongo subdocuments/arrays, now JSON-encoded strings bound for JSONB.
    """
    if "_id" in df.columns:
        df = df.drop("_id")

    for old in df.columns:
        new = _pg_safe_identifier(old)
        if new != old:
            df = df.withColumnRenamed(old, new)

    jsonb_cols = set()
    for field in df.schema.fields:
        col = field.name
        dtype = field.dataType

        if col in TIMESTAMP_COLS:
            df = df.withColumn(col, F.to_timestamp(F.col(col)))
        elif col.endswith("_date") or col in ("date_of_birth", "month"):
            df = df.withColumn(col, F.to_date(F.col(col)))
        elif col in BIGINT_COLS:
            df = df.withColumn(col, F.col(col).cast(LongType()))
        elif col in NUMERIC_COLS:
            df = df.withColumn(col, F.col(col).cast(DoubleType()))
        elif isinstance(dtype, (StructType, ArrayType, MapType)):
            df = df.withColumn(col, F.to_json(F.col(col)))
            jsonb_cols.add(col)
        else:
            df = df.withColumn(col, F.col(col).cast(StringType()))

    return df, jsonb_cols


def infer_pg_types(df: DataFrame, jsonb_cols: set) -> dict:
    pg_types = {}
    for field in df.schema.fields:
        col = field.name
        dtype = field.dataType
        if col in jsonb_cols:
            pg_types[col] = "JSONB"
        elif isinstance(dtype, TimestampType):
            pg_types[col] = "TIMESTAMP"
        elif isinstance(dtype, DateType):
            pg_types[col] = "DATE"
        elif isinstance(dtype, LongType):
            pg_types[col] = "BIGINT"
        elif isinstance(dtype, (DoubleType, FloatType, DecimalType)):
            pg_types[col] = "NUMERIC"
        else:
            pg_types[col] = "VARCHAR"
    return pg_types


# =========================================================
# TARGET TABLE DDL (create / add missing columns — no PK/constraint)
# =========================================================

def ensure_table_schema(table_name: str, pg_types: dict, full_refresh: bool):
    """Create the table if missing, or add any new columns if it exists.
    No primary key / unique constraint — this is a history table, and plain
    INSERT doesn't need one to know what to do with a row.
    """
    with get_pg_connection() as conn, conn.cursor() as cur:
        if full_refresh:
            cur.execute(f'DROP TABLE IF EXISTS public."{table_name}"')

        cur.execute(
            "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=%s",
            (table_name,),
        )
        exists = cur.fetchone() is not None

        if not exists:
            cols_sql = [f'"{c}" {t}' for c, t in pg_types.items()]
            ddl = f'CREATE TABLE public."{table_name}" (\n  ' + ",\n  ".join(cols_sql) + "\n);"
            cur.execute(ddl)
            logger.info(f"[{table_name}] Created table.")
        else:
            cur.execute(
                "SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=%s",
                (table_name,),
            )
            existing = {r[0] for r in cur.fetchall()}
            for c, t in pg_types.items():
                if c not in existing:
                    cur.execute(f'ALTER TABLE public."{table_name}" ADD COLUMN "{c}" {t}')
                    logger.info(f"[{table_name}] Added missing column: {c} ({t})")

            # Self-heal tables created by an earlier, upsert-based version
            # of this script: those left a UNIQUE/PRIMARY KEY constraint
            # (e.g. "<table>_natural_key") behind. This script only ever
            # does plain INSERTs now, so that constraint has nothing to do
            # except throw UniqueViolation the moment two rows share an id
            # — which is expected and fine for a history table. Drop it.
            cur.execute("""
                SELECT constraint_name, constraint_type
                FROM information_schema.table_constraints
                WHERE table_schema = 'public' AND table_name = %s
                  AND constraint_type IN ('UNIQUE', 'PRIMARY KEY')
            """, (table_name,))
            stale_constraints = cur.fetchall()
            for constraint_name, constraint_type in stale_constraints:
                cur.execute(
                    f'ALTER TABLE public."{table_name}" DROP CONSTRAINT "{constraint_name}"'
                )
                logger.warning(
                    f"[{table_name}] Dropped leftover {constraint_type} constraint "
                    f"'{constraint_name}' from a previous upsert-based run — "
                    f"this table is insert-only now, so it no longer applies."
                )


# =========================================================
# TERMINAL-FRIENDLY ERROR MESSAGES
# =========================================================

def _short_error(exc: Exception) -> str:
    """Boil a (possibly huge, Py4J/JVM-wrapped) exception down to one
    actionable line for the terminal summary table. The full traceback is
    still written to the log file via logger.error(..., exc_info=True).
    """
    text = str(exc)
    for marker in ("psycopg2.errors.", "pymongo.errors.", "py4j.protocol."):
        idx = text.find(marker)
        if idx != -1:
            end = text.find("\n", idx)
            return text[idx:end if end != -1 else idx + 200].strip()
    for line in text.splitlines():
        line = line.strip()
        if line:
            return line[:200]
    return exc.__class__.__name__


# =========================================================
# INSERT WRITER — chunked, per Spark partition, no staging table
# =========================================================
#
# Plain INSERT, no ON CONFLICT. Every row read from Mongo (updated_at >
# watermark) gets appended. If a document was updated twice since the last
# sync it was picked up, or across two separate syncs, that's two rows here,
# not one row updated twice — this table accumulates a history of changes
# per entity rather than holding current state.
#
# A chunk is normally bulk-inserted in one execute_values call (fast path).
# If Postgres rejects the WHOLE chunk — most commonly a DB-side CHECK or
# trigger tripping on exactly one row, e.g. fuel_purchases' "total_cost
# must equal gallons * price_per_gallon" — that one bad row shouldn't take
# the other several thousand good rows in the same chunk down with it, and
# it definitely shouldn't fail the entire collection's sync. On a chunk
# failure we roll back and retry that chunk one row at a time so we can
# isolate exactly which row(s) are bad: good rows get inserted, bad rows
# get quarantined (logged + reported, not written) and everything moves on.
#
# This is a generator used with rdd.mapPartitions (not foreachPartition,
# which returns nothing) so each partition can report back what happened:
# one {"inserted": N, "rejected": [...]} dict per partition, collected by
# the driver in sync_collection.

def insert_partition(rows_iter, table_name: str, columns: list, chunk_size: int, id_col: Optional[str] = None):
    rows = list(rows_iter)
    if not rows:
        return

    col_list = ", ".join(f'"{c}"' for c in columns)
    bulk_sql = f'INSERT INTO public."{table_name}" ({col_list}) VALUES %s'
    single_sql = f'INSERT INTO public."{table_name}" ({col_list}) VALUES ({", ".join(["%s"] * len(columns))})'

    # id_col is resolved by the caller (sync_collection) from PRIMARY_KEYS,
    # so the human-readable identifier attached to a rejected row is the
    # table's actual natural key (e.g. fuel_purchase_id) — not just
    # whichever "<something>_id" column happened to come first, which
    # could easily be an unrelated foreign key (e.g. driver_id on
    # fuel_purchases) and point a reader at the wrong entity entirely.
    if id_col is None:
        id_col = next((c for c in columns if c.endswith("_id")), None)

    conn = psycopg2.connect(
        host=POSTGRES_HOST, port=POSTGRES_PORT, dbname=POSTGRES_DATABASE,
        user=POSTGRES_USERNAME, password=POSTGRES_PASSWORD,
    )
    inserted = 0
    rejected = []
    try:
        values = [tuple(r[c] for c in columns) for r in rows]
        for i in range(0, len(values), chunk_size):
            chunk = values[i:i + chunk_size]
            try:
                with conn.cursor() as cur:
                    execute_values(cur, bulk_sql, chunk, page_size=chunk_size)
                conn.commit()
                inserted += len(chunk)
            except psycopg2.Error:
                conn.rollback()
                for row_values in chunk:
                    try:
                        with conn.cursor() as cur:
                            cur.execute(single_sql, row_values)
                        conn.commit()
                        inserted += 1
                    except psycopg2.Error as row_exc:
                        conn.rollback()
                        row = dict(zip(columns, row_values))
                        rejected.append({
                            "id": str(row.get(id_col, "?")) if id_col else "?",
                            "error": _short_error(row_exc),
                        })
    finally:
        conn.close()

    yield {"inserted": inserted, "rejected": rejected}


# =========================================================
# NEW VS UPDATED — best-effort split for the summary table
# =========================================================

def classify_new_vs_updated(df: DataFrame, watermark: Optional[datetime]):
    """Split this batch into "new" vs "updated" for reporting purposes.

    This script has no primary key (deliberately — see module docstring),
    so it can't truly know per-row whether a given entity already existed.
    What it CAN do:
      - No prior watermark (first sync / --full-refresh): every row is new
        by definition, since nothing existed in the target table before.
      - A watermark exists AND the collection has a `created_at` field:
        rows created after the watermark are "new", the rest are documents
        that existed before but changed since ("updated").
      - A watermark exists but there's no `created_at` field: there's no
        way to tell, so everything is conservatively counted as "updated".

    Returns (total, new_count, updated_count, note).
    """
    if watermark is None:
        total = df.count()
        return total, total, 0, ""

    if "created_at" in df.columns:
        row = df.agg(
            F.count(F.lit(1)).alias("total"),
            F.count(F.when(F.col("created_at") > watermark, 1)).alias("new"),
        ).collect()[0]
        total, new_count = row["total"], row["new"]
        return total, new_count, total - new_count, ""

    total = df.count()
    return total, 0, total, "no created_at field — can't split, counted as updated"


# =========================================================
# MAIN SYNC
# =========================================================

def sync_collection(spark: SparkSession, collection_name: str, table_name: str, full_refresh: bool):
    logger.info(f"[{collection_name}] Starting sync...")
    stats = {
        "collection": collection_name, "table": table_name,
        "mongo_rows": 0, "new": 0, "updated": 0, "rejected": 0,
        "status": "ok", "note": "",
    }
    try:
        watermark = None if full_refresh else load_watermark(table_name)
        if watermark:
            logger.info(f"[{collection_name}] Resuming from watermark: {watermark.isoformat()}")
        else:
            logger.info(f"[{collection_name}] No watermark found or full refresh — pulling all records.")

        df = read_incremental(spark, collection_name, watermark)
        if df.rdd.isEmpty():
            logger.info(f"[{collection_name}] No new or updated records found.")
            stats["status"] = "empty"
            return stats

        df, jsonb_cols = flatten_and_cast(df)
        pg_types = infer_pg_types(df, jsonb_cols)

        ensure_table_schema(table_name, pg_types, full_refresh)

        max_ts = None
        if UPDATED_AT_FIELD in df.columns:
            max_ts = df.agg(F.max(UPDATED_AT_FIELD)).collect()[0][0]

        total, new_count, updated_count, note = classify_new_vs_updated(df, watermark)
        columns = df.columns

        id_col = PRIMARY_KEYS.get(collection_name)
        if id_col is not None and id_col not in columns:
            logger.warning(
                f"[{collection_name}] Expected primary key column '{id_col}' not found "
                f"among synced columns — falling back to a best-guess identifier for "
                f"rejected-row logging."
            )
            id_col = None

        partition_results = (
            df.repartition(SPARK_PARTITIONS)
            .rdd.mapPartitions(lambda rows: insert_partition(rows, table_name, columns, CHUNK_SIZE, id_col))
            .collect()
        )
        inserted_total = sum(r["inserted"] for r in partition_results)
        rejected_rows = [rr for r in partition_results for rr in r["rejected"]]

        for rr in rejected_rows:
            logger.warning(f"[{collection_name}] Rejected {rr['id']}: {rr['error']}")

        # Watermark still advances past the full batch (including rejects):
        # NOT doing so would mean every future run re-pulls the whole
        # window and re-inserts the rows that already succeeded (this is
        # an insert-only history table — no dedup on retry). A rejected
        # row is logged above for manual follow-up instead of being
        # retried automatically.
        if max_ts:
            save_watermark(table_name, max_ts)

        if rejected_rows:
            first = rejected_rows[0]
            more = f" (+{len(rejected_rows) - 1} more, see log)" if len(rejected_rows) > 1 else ""
            note = f"{len(rejected_rows)} rejected — {first['id']}: {first['error']}{more}"
            stats["status"] = "partial" if inserted_total > 0 else "failed"

        stats.update(mongo_rows=total, new=new_count, updated=updated_count, rejected=len(rejected_rows), note=note)
        logger.info(
            f"[{collection_name}] Inserted {inserted_total:,}/{total:,} records "
            f"({new_count:,} new, {updated_count:,} updated, {len(rejected_rows):,} rejected)."
        )
        return stats

    except Exception as exc:
        logger.error(f"[{collection_name}] Failed: {exc}", exc_info=True)
        stats["status"] = "failed"
        stats["note"] = _short_error(exc)
        return stats


def _print_summary(results: list) -> bool:
    """Render the rich summary table. Returns True if nothing hard-failed
    (collections with some rows quarantined but the rest inserted OK count
    as success — see 'partial' below)."""
    table = Table(title="Mongo -> Postgres Sync Summary", box=box.SIMPLE_HEAVY, show_lines=False)
    table.add_column("Collection", style="cyan")
    table.add_column("Table", style="dim")
    table.add_column("Mongo Rows", justify="right")
    table.add_column("New", justify="right", style="green")
    table.add_column("Updated", justify="right", style="yellow")
    table.add_column("Rejected", justify="right", style="red")
    table.add_column("Status")
    table.add_column("Note", style="dim")

    total_rows = total_new = total_updated = total_rejected = 0
    any_failed = False

    for r in results:
        if r["status"] == "failed":
            status_text, any_failed = "[bold red]FAILED[/bold red]", True
        elif r["status"] == "partial":
            status_text = "[bold yellow]PARTIAL[/bold yellow]"
        elif r["status"] == "empty":
            status_text = "[dim]no changes[/dim]"
        else:
            status_text = "[bold green]OK[/bold green]"

        table.add_row(
            r["collection"], r["table"],
            f"{r['mongo_rows']:,}", f"{r['new']:,}", f"{r['updated']:,}",
            f"{r['rejected']:,}" if r["rejected"] else "0",
            status_text, r["note"],
        )
        total_rows += r["mongo_rows"]
        total_new += r["new"]
        total_updated += r["updated"]
        total_rejected += r["rejected"]

    table.add_section()
    table.add_row(
        "[bold]TOTAL[/bold]", "",
        f"[bold]{total_rows:,}[/bold]", f"[bold]{total_new:,}[/bold]", f"[bold]{total_updated:,}[/bold]",
        f"[bold]{total_rejected:,}[/bold]", "", "",
    )

    console.print(table)
    return not any_failed


def run(collection_name=None, table_name=None, full_refresh=False):
    console.rule("[bold cyan]MONGO -> POSTGRES INCREMENTAL SYNC[/bold cyan]")

    ensure_watermark_table()
    spark = get_spark()

    targets = [(collection_name, table_name or collection_name)] if collection_name else [
        (c, c) for c in ALL_COLLECTIONS
    ]

    results = []
    for cname, tname in targets:
        with console.status(f"[cyan]Syncing {cname}...[/cyan]"):
            stats = sync_collection(spark, cname, tname, full_refresh)
        results.append(stats)

        if stats["status"] == "failed":
            console.print(f"  [red]\u2717[/red] {cname}: {stats['note']}")
        elif stats["status"] == "partial":
            console.print(
                f"  [yellow]\u26a0[/yellow] {cname}: {stats['mongo_rows']:,} rows "
                f"({stats['new']:,} new, {stats['updated']:,} updated, "
                f"[red]{stats['rejected']:,} rejected[/red]) — {stats['note']}"
            )
        elif stats["status"] == "empty":
            console.print(f"  [dim]\u2013[/dim] {cname}: no new or updated records")
        else:
            console.print(
                f"  [green]\u2713[/green] {cname}: {stats['mongo_rows']:,} rows "
                f"({stats['new']:,} new, {stats['updated']:,} updated)"
            )

    spark.stop()

    console.print()
    all_ok = _print_summary(results)

    if not all_ok:
        failed = [r["collection"] for r in results if r["status"] == "failed"]
        console.print(f"\n[bold red]{len(failed)} of {len(results)} collections failed:[/bold red] {', '.join(failed)}")
        sys.exit(1)
    else:
        partial = [r["collection"] for r in results if r["status"] == "partial"]
        if partial:
            console.print(
                f"\n[bold yellow]All collections synced, but {len(partial)} had rejected rows "
                f"(see log for details):[/bold yellow] {', '.join(partial)}"
            )
        else:
            console.print("\n[bold green]All tables synced successfully.[/bold green]")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--collection", default=None)
    parser.add_argument("--table", default=None)
    parser.add_argument("--full-refresh", action="store_true", help="Ignore watermark, wipe target table, and load everything.")
    args = parser.parse_args()

    run(args.collection, args.table, args.full_refresh)