"""
sync_mongo_to_postgres.py

Incremental MongoDB -> PostgreSQL loader using PySpark.

WHAT IT DOES
------------
1. Reads the last successful watermark (max `updated_at` processed) from a
   local JSON file.
2. Pulls only documents from Mongo where `updated_at` > watermark
   (full collection on first run, since there's no watermark yet).
3. Flattens nested/array Mongo fields into JSONB-friendly JSON strings
   (top-level scalars stay native types; dates/timestamps stay dates/timestamps).
4. Creates the target Postgres table in the `public` schema if it doesn't
   exist yet, inferring column types from the first batch read.
5. Upserts rows into Postgres via psycopg2 (INSERT ... ON CONFLICT (_id)
   DO UPDATE), executed per-partition with execute_values for speed.
6. Detects deletes by diffing the full set of `_id`s in Mongo against the
   full set of `_id`s currently in Postgres, and deletes anything missing
   from Mongo.
7. Saves the new watermark back to the JSON file.
8. Prints a detailed per-table report (new / updated / deleted / total rows).

REQUIREMENTS
------------
    pip install pyspark psycopg2-binary

You already have the Postgres JDBC driver at driver/postgresql.jar.
The MongoDB Spark Connector is fetched automatically via --packages, and
the correct version is determined dynamically based on your PySpark version.
"""

import argparse
import json
import logging
import os
import re
import sys
import warnings
from datetime import datetime, timezone
from dataclasses import dataclass, field
from typing import Optional

# ---------------------------------------------------------------------------
# Silence noisy Java / PySpark / py4j warnings BEFORE importing pyspark,
# so they never appear on stderr during a production run.
# ---------------------------------------------------------------------------
os.environ["PYSPARK_SUBMIT_ARGS"] = "--driver-java-options -Divy.message.logger.level=4 pyspark-shell"
os.environ.setdefault("PYSPARK_PYTHON", sys.executable)

# Redirect py4j / JVM stderr noise
import logging as _logging
_logging.getLogger("py4j").setLevel(_logging.ERROR)
_logging.getLogger("pyspark").setLevel(_logging.ERROR)

# Suppress Python-level DeprecationWarnings from pyspark internals
warnings.filterwarnings("ignore", category=DeprecationWarning)

# This script is expected to live in <project_root>/scripts/, with
# utils/, driver/, and watermark.json all living in <project_root>/.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import pyspark
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType,
    ArrayType,
    MapType,
    BooleanType,
    IntegerType,
    ShortType,
    LongType,
    DoubleType,
    FloatType,
    DecimalType,
    DateType,
    TimestampType,
    StringType,
)

import psycopg2
from psycopg2.extras import execute_values

from utils.connection import (
    POSTGRES_HOST,
    POSTGRES_PORT,
    POSTGRES_DATABASE,
    POSTGRES_USERNAME,
    POSTGRES_PASSWORD,
    MONGO_URI,
    MONGO_DB,
)
from utils.logger import get_logger

logger = get_logger("extraction", "mongo_to_postgres_sync")

# =========================================================
# CONFIG
# =========================================================

PK_FIELD = "_id"
UPDATED_AT_FIELD = "updated_at"

WATERMARK_FILE = os.path.join(PROJECT_ROOT, "watermark.json")
POSTGRES_JDBC_JAR = os.path.join(PROJECT_ROOT, "driver", "postgresql.jar")

SEPARATOR = "=" * 72


def get_mongo_connector_package():
    """Dynamically resolve the correct MongoDB Spark Connector based on PySpark version."""
    version = pyspark.__version__
    if version.startswith("3.2"):
        return "org.mongodb.spark:mongo-spark-connector_2.12:10.0.2"
    elif version.startswith("3.3"):
        return "org.mongodb.spark:mongo-spark-connector_2.12:10.1.1"
    elif version.startswith("3.4"):
        return "org.mongodb.spark:mongo-spark-connector_2.12:10.2.2"
    elif version.startswith("3.5"):
        return "org.mongodb.spark:mongo-spark-connector_2.12:10.4.0"
    elif version.startswith("4."):
        return "org.mongodb.spark:mongo-spark-connector_2.13:10.4.0"
    return "org.mongodb.spark:mongo-spark-connector_2.12:10.4.0"


MONGO_SPARK_CONNECTOR_PACKAGE = get_mongo_connector_package()

# Collections synced when no --collection flag is given (table name = collection name).
ALL_COLLECTIONS = [
    "customers",
    "delivery_events",
    "drivers",
    "driver_monthly_metrics",
    "facilities",
    "fuel_purchases",
    "loads",
    "maintenance_records",
    "routes",
    "safety_incidents",
    "trailers",
    "trips",
    "trucks",
    "truck_utilization_metrics",
]


# =========================================================
# SYNC REPORT — per-table metrics
# =========================================================

@dataclass
class TableSyncReport:
    collection: str
    table: str
    mode: str                      # "FULL REFRESH" | "Incremental"
    rows_in_mongo: int = 0
    rows_before: int = 0           # PG row count before this run
    rows_inserted: int = 0         # brand-new rows
    rows_updated: int = 0          # rows that already existed and were overwritten
    rows_deleted: int = 0          # rows removed because they vanished from Mongo
    rows_after: int = 0            # PG row count after this run
    error: Optional[str] = None

    @property
    def rows_unchanged(self) -> int:
        return max(0, self.rows_before - self.rows_updated - self.rows_deleted)


@dataclass
class RunSummary:
    started_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    finished_at: Optional[datetime] = None
    tables: list = field(default_factory=list)

    def add(self, report: TableSyncReport):
        self.tables.append(report)

    def finish(self):
        self.finished_at = datetime.now(timezone.utc)

    def print_report(self):
        elapsed = ""
        if self.finished_at:
            secs = (self.finished_at - self.started_at).total_seconds()
            elapsed = f"{secs:.1f}s"

        print()
        print(SEPARATOR)
        print("  MONGO -> POSTGRES SYNC  |  FINAL REPORT")
        print(f"  Started : {self.started_at.strftime('%Y-%m-%d %H:%M:%S UTC')}")
        if self.finished_at:
            print(f"  Finished: {self.finished_at.strftime('%Y-%m-%d %H:%M:%S UTC')}  ({elapsed})")
        print(SEPARATOR)

        ok_tables = [t for t in self.tables if t.error is None]
        err_tables = [t for t in self.tables if t.error is not None]

        for rep in self.tables:
            status = "✓" if rep.error is None else "✗"
            print()
            print(f"  {status}  [{rep.mode}]  {rep.collection}  →  public.\"{rep.table}\"")
            print(f"     {'-' * 60}")
            if rep.error:
                print(f"     ERROR: {rep.error}")
            else:
                print(f"     Rows in MongoDB (fetched)  : {rep.rows_in_mongo:>10,}")
                print(f"     Rows in Postgres (before)  : {rep.rows_before:>10,}")
                print(f"     ----------------------------------------")
                print(f"     New rows inserted          : {rep.rows_inserted:>10,}")
                print(f"     Existing rows updated      : {rep.rows_updated:>10,}")
                print(f"     Rows deleted (not in Mongo): {rep.rows_deleted:>10,}")
                print(f"     ----------------------------------------")
                print(f"     Rows in Postgres (after)   : {rep.rows_after:>10,}")

        print()
        print(SEPARATOR)

        # Totals
        total_ins  = sum(r.rows_inserted for r in ok_tables)
        total_upd  = sum(r.rows_updated  for r in ok_tables)
        total_del  = sum(r.rows_deleted  for r in ok_tables)
        total_aft  = sum(r.rows_after    for r in ok_tables)

        print(f"  TOTALS  |  {len(ok_tables)} table(s) OK, {len(err_tables)} failed")
        print(f"  New rows inserted          : {total_ins:>10,}")
        print(f"  Existing rows updated      : {total_upd:>10,}")
        print(f"  Rows deleted               : {total_del:>10,}")
        print(f"  Total rows in Postgres now : {total_aft:>10,}")

        if err_tables:
            print()
            print("  FAILED TABLES:")
            for rep in err_tables:
                print(f"    - {rep.collection}: {rep.error}")

        print(SEPARATOR)
        print()


# =========================================================
# WATERMARK STORAGE (local JSON file at project root)
# =========================================================

def load_watermark(collection_name: str):
    if not os.path.exists(WATERMARK_FILE):
        return None
    with open(WATERMARK_FILE, "r") as f:
        data = json.load(f)
    return data.get(collection_name)


def save_watermark(collection_name: str, value: str):
    data = {}
    if os.path.exists(WATERMARK_FILE):
        with open(WATERMARK_FILE, "r") as f:
            data = json.load(f)
    data[collection_name] = value
    with open(WATERMARK_FILE, "w") as f:
        json.dump(data, f, indent=2)


def to_watermark_string(value) -> str:
    """
    Normalize a Spark-collected timestamp value into an ISO-8601 UTC string
    that MongoDB's Extended JSON $date parser will actually accept.

    BUG FIXED: strftime("%f") always emits 6-digit microseconds
    (e.g. ".123456Z"). The Extended JSON spec for $date caps fractional
    seconds at exactly 3 digits (milliseconds), omitted entirely when zero:
    https://github.com/mongodb/specifications/blob/master/source/extended-json/extended-json.md
    A 6-digit value is invalid, so every incremental run after the very
    first one (once a watermark exists) would fail to parse the
    {"$date": ...} filter in read_incremental() and the sync would never
    progress past day one. BSON Date is millisecond-precision anyway, so
    truncating here loses nothing.
    """
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        value = value.astimezone(timezone.utc)
        millis = value.microsecond // 1000
        base = value.strftime("%Y-%m-%dT%H:%M:%S")
        return f"{base}.{millis:03d}Z" if millis else f"{base}Z"
    return str(value)


# =========================================================
# SPARK SESSION  (all Spark / Hadoop log levels suppressed)
# =========================================================

def build_spark_session() -> SparkSession:
    logger.info(f"Using MongoDB Spark Connector: {MONGO_SPARK_CONNECTOR_PACKAGE}")

    # Use extraClassPath instead of spark.jars for the JDBC driver.
    #
    # WHY: spark.jars tells Spark to COPY the JAR into its temp dir
    # (AppData\Local\Temp\spark-*\userFiles-*\postgresql.jar on Windows).
    # At JVM shutdown, Spark tries to delete that temp copy — but on Windows
    # the JVM still holds a file lock on the JAR, causing:
    #   ERROR ShutdownHookManager: Failed to delete: postgresql.jar
    #
    # spark.driver.extraClassPath loads the JAR directly from its original
    # path on the classpath — no copy, no temp file, no lock, no error.
    jdbc_jar_path = os.path.abspath(POSTGRES_JDBC_JAR)
    if not os.path.isfile(jdbc_jar_path):
        raise FileNotFoundError(
            f"\n\nPostgreSQL JDBC JAR not found at:\n  {jdbc_jar_path}\n\n"
            "It's required for the delete-diff read in handle_deletes().\n"
            "Place the driver at driver/postgresql.jar or fix POSTGRES_JDBC_JAR.\n"
            "Download from: https://jdbc.postgresql.org/download/\n"
        )

    spark = (
        SparkSession.builder.appName("mongo_to_postgres_sync")
        .config("spark.driver.extraClassPath", jdbc_jar_path)
        # Add this line to mute the Ivy package manager's "resolving dependencies" wall of text:
        .config("spark.driver.extraJavaOptions", "-Divy.message.logger.level=4")
        .config("spark.jars.packages", MONGO_SPARK_CONNECTOR_PACKAGE)
        .config("spark.mongodb.read.connection.uri", MONGO_URI)
        .config("spark.mongodb.read.database", MONGO_DB)
        .config("spark.ui.showConsoleProgress", "false")
        .config("spark.sql.execution.arrow.pyspark.enabled", "false")
        .getOrCreate()
    )

    # Set log levels on the active Spark context
    spark.sparkContext.setLogLevel("ERROR")

    # Silence loggers via the JVM log4j gateway.
    # ShutdownHookManager is silenced specifically at FATAL so its Windows
    # temp-dir cleanup errors (harmless, post-shutdown) never appear.
    try:
        log4j   = spark._jvm.org.apache.log4j
        Level   = log4j.Level
        manager = log4j.LogManager

        # Root logger → ERROR (kills all Hadoop / connector INFO/WARN)
        manager.getRootLogger().setLevel(Level.ERROR)

        # ShutdownHookManager → FATAL only  (kills the JAR-delete ERROR on Windows)
        manager.getLogger(
            "org.apache.spark.util.ShutdownHookManager"
        ).setLevel(Level.FATAL)

        # Also silence the SparkFileUtils logger that emits the same cleanup errors
        manager.getLogger(
            "org.apache.spark.util.SparkFileUtils"
        ).setLevel(Level.FATAL)

    except Exception:
        pass  # non-fatal; suppression is best-effort

    return spark


# =========================================================
# MONGO READS
# =========================================================

def read_incremental(spark: SparkSession, collection_name: str, watermark: str):
    """Read full collection (first run) or only docs updated since watermark."""
    options = {"collection": collection_name}

    if watermark:
        pipeline = [
            {"$match": {UPDATED_AT_FIELD: {"$gt": {"$date": watermark}}}}
        ]
        options["aggregation.pipeline"] = json.dumps(pipeline)
        logger.info(f"Reading {collection_name} where {UPDATED_AT_FIELD} > {watermark}")
    else:
        logger.info(f"No watermark found — performing full load of {collection_name}")

    return spark.read.format("mongodb").options(**options).load()


def read_all_ids(spark: SparkSession, collection_name: str):
    """Read just the PK field for every live document (used for delete-diffing)."""
    df = (
        spark.read.format("mongodb")
        .options(collection=collection_name)
        .load()
        .select(PK_FIELD)
    )
    return normalize_pk(df)


# =========================================================
# SCHEMA FLATTENING / TYPE HANDLING
# =========================================================

def _pg_safe_identifier(name: str) -> str:
    """
    Make a MongoDB field name safe to use as a bare Postgres column
    identifier. Mongo field names can contain spaces, hyphens, dots,
    leading digits, or be longer than Postgres' 63-byte identifier limit —
    none of that is valid/safe even when quoted consistently across DDL
    and DML, so unsafe characters are normalized away.

    '_id' is always passed through untouched: PK_FIELD == "_id" is relied
    on verbatim everywhere else in this script (normalize_pk, upserts,
    delete-diffing), so it must never be rewritten.
    """
    if name == PK_FIELD:
        return name
    safe = re.sub(r"[^0-9A-Za-z_]", "_", name)
    if not safe or safe[0].isdigit():
        safe = f"_{safe}"
    return safe[:63]


def normalize_pk(df):
    """
    Mongo's connector reads ObjectId as a struct {oid: string}.
    Flatten that to a plain string and keep the column name exactly as '_id'
    — never rename it or cast it differently based on collection.

    IMPORTANT: we preserve the column name '_id' (PK_FIELD) so the Postgres
    PRIMARY KEY column is always called '_id', matching MongoDB exactly.
    """
    pk_type = df.schema[PK_FIELD].dataType
    if isinstance(pk_type, StructType) and "oid" in pk_type.fieldNames():
        # ObjectId struct → extract the hex string, keep column name '_id'
        df = df.withColumn(PK_FIELD, F.col(f"{PK_FIELD}.oid").cast(StringType()))
    elif not isinstance(pk_type, StringType):
        # Any other non-string type → cast to string, keep column name '_id'
        df = df.withColumn(PK_FIELD, F.col(PK_FIELD).cast(StringType()))
    # If it's already a StringType, leave it completely untouched.
    return df


def flatten_for_postgres(df):
    """
    - Nested structs / arrays / maps  → serialised as JSON (stored as JSONB).
    - Scalar types (int, bool, date …) → left as-is so Postgres gets the right
      native column type.
    - '_id' is normalised via normalize_pk() first.
    - Field names are sanitized into safe Postgres identifiers.

    Returns (flattened_df, pg_types) where pg_types maps each (sanitized)
    column name to its Postgres DDL type, computed from the field's
    ORIGINAL Spark type — i.e. BEFORE nested types get serialised to JSON
    text. Callers must use pg_types for DDL, not the flattened df's schema,
    or every nested field will look like a plain string and never become
    JSONB.
    """
    df = normalize_pk(df)
    cols = []
    pg_types: dict[str, str] = {}
    for field in df.schema.fields:
        safe_name = _pg_safe_identifier(field.name)
        if field.name == PK_FIELD:
            cols.append(F.col(field.name))
            pg_types[safe_name] = "TEXT"
            continue
        pg_types[safe_name] = spark_type_to_postgres(field.dataType)
        if isinstance(field.dataType, (StructType, ArrayType, MapType)):
            cols.append(F.to_json(F.col(field.name)).alias(safe_name))
        else:
            cols.append(F.col(field.name).alias(safe_name))
    return df.select(*cols), pg_types


def spark_type_to_postgres(data_type) -> str:
    """Map a Spark DataType to the best-fit PostgreSQL column type."""
    if isinstance(data_type, (StructType, ArrayType, MapType)):
        return "JSONB"
    if isinstance(data_type, BooleanType):
        return "BOOLEAN"
    if isinstance(data_type, (IntegerType, ShortType)):
        return "INTEGER"
    if isinstance(data_type, LongType):
        return "BIGINT"
    if isinstance(data_type, (DoubleType, FloatType)):
        return "DOUBLE PRECISION"
    if isinstance(data_type, DecimalType):
        return f"NUMERIC({data_type.precision},{data_type.scale})"
    if isinstance(data_type, DateType):
        return "DATE"
    if isinstance(data_type, TimestampType):
        return "TIMESTAMP"
    return "TEXT"


# =========================================================
# POSTGRES — CONNECTION / DDL / DML
# =========================================================

def get_pg_connection():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DATABASE,
        user=POSTGRES_USERNAME,
        password=POSTGRES_PASSWORD,
    )


def get_pg_row_count(table_name: str) -> int:
    """Return current row count of a Postgres table, or 0 if it doesn't exist."""
    if not table_exists(table_name):
        return 0
    conn = get_pg_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(f'SELECT COUNT(*) FROM public."{table_name}"')
            return cur.fetchone()[0]
    finally:
        conn.close()


def ensure_table_exists(table_name: str, pg_types: dict):
    """
    CREATE TABLE IF NOT EXISTS using the pg_types map built by
    flatten_for_postgres() (NOT the flattened df's own schema — by the
    time a df is flattened, nested fields have already been serialised to
    JSON text and look like plain strings, so deriving types from the
    flattened df would silently turn every JSONB column into TEXT).

      - '_id'                       → TEXT PRIMARY KEY (always)
      - numeric, boolean, date/ts    → their native Postgres equivalents
      - nested structs/arrays/maps   → JSONB
    """
    cols_sql = []
    for name, pg_type in pg_types.items():
        if name == PK_FIELD:
            cols_sql.append(f'"{PK_FIELD}" TEXT')
        else:
            cols_sql.append(f'"{name}" {pg_type}')

    ddl = (
        f'CREATE TABLE IF NOT EXISTS public."{table_name}" (\n  '
        + ",\n  ".join(cols_sql)
        + f',\n  PRIMARY KEY ("{PK_FIELD}")\n);'
    )

    conn = get_pg_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(ddl)
        conn.commit()
        logger.info(f'Ensured table public."{table_name}" exists')
    finally:
        conn.close()


def sync_table_schema(table_name: str, pg_types: dict):
    """
    Add any column that's present in this batch but missing from the
    already-existing Postgres table (schema evolution).

    Only additive changes are applied automatically. If a field's type
    genuinely conflicts with an existing column (e.g. a field that used to
    be an integer everywhere is now sometimes a string), that is
    intentionally NOT auto-migrated — silently widening/narrowing a live
    column's type unattended is unsafe. The upsert will fail loudly with
    Postgres' own type error in that case, surfaced via report.error, and
    a human should decide how to reconcile the column.
    """
    conn = get_pg_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema = 'public' AND table_name = %s",
                (table_name,),
            )
            existing = {row[0] for row in cur.fetchall()}

        missing = {n: t for n, t in pg_types.items() if n not in existing}
        if not missing:
            return

        with conn.cursor() as cur:
            for name, pg_type in missing.items():
                cur.execute(
                    f'ALTER TABLE public."{table_name}" ADD COLUMN "{name}" {pg_type}'
                )
                logger.info(
                    f'Schema evolution: added column "{name}" ({pg_type}) '
                    f'to public."{table_name}"'
                )
        conn.commit()
    finally:
        conn.close()


def count_existing_ids(table_name: str, ids: list) -> int:
    """
    Return how many of the given _id values already exist in Postgres.
    Used to split an upsert batch into 'new inserts' vs 'updates'.
    """
    if not ids or not table_exists(table_name):
        return 0
    conn = get_pg_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f'SELECT COUNT(*) FROM public."{table_name}" WHERE "{PK_FIELD}" = ANY(%s)',
                (ids,),
            )
            return cur.fetchone()[0]
    finally:
        conn.close()


def upsert_partition(rows, table_name: str, columns: list):
    """
    Upsert a single Spark partition into Postgres.
    Returns a tuple (inserted, updated) counts.
    Because foreachPartition cannot return values, counts are accumulated
    separately via count_existing_ids() before the upsert.
    """
    rows = list(rows)
    if not rows:
        return

    conn = psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        dbname=POSTGRES_DATABASE,
        user=POSTGRES_USERNAME,
        password=POSTGRES_PASSWORD,
    )
    try:
        cur = conn.cursor()
        col_list = ", ".join(f'"{c}"' for c in columns)
        update_clause = ", ".join(
            f'"{c}" = EXCLUDED."{c}"' for c in columns if c != PK_FIELD
        )
        sql = (
            f'INSERT INTO public."{table_name}" ({col_list}) VALUES %s '
            f'ON CONFLICT ("{PK_FIELD}") DO UPDATE SET {update_clause}'
        )
        values = [tuple(row[c] for c in columns) for row in rows]
        execute_values(cur, sql, values, page_size=500)
        conn.commit()
    finally:
        conn.close()


def table_exists(table_name: str) -> bool:
    conn = get_pg_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM information_schema.tables "
                "WHERE table_schema = 'public' AND table_name = %s",
                (table_name,),
            )
            return cur.fetchone() is not None
    finally:
        conn.close()


def drop_table_if_exists(table_name: str):
    """Used by --full-refresh: wipes the table so it gets rebuilt fresh."""
    conn = get_pg_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(f'DROP TABLE IF EXISTS public."{table_name}"')
        conn.commit()
        logger.info(f'Dropped public."{table_name}" for full refresh.')
    finally:
        conn.close()


# =========================================================
# DELETE HANDLING — diff PKs between Mongo and Postgres
# =========================================================

def handle_deletes(
    spark: SparkSession,
    collection_name: str,
    table_name: str,
) -> int:
    """
    Delete rows from Postgres that are no longer present in MongoDB.
    Returns the number of rows deleted.
    """
    if not table_exists(table_name):
        logger.info("Target table doesn't exist yet — skipping delete check.")
        return 0

    mongo_ids = {
        row[PK_FIELD]
        for row in read_all_ids(spark, collection_name).collect()
    }

    pg_ids_df = (
        spark.read.format("jdbc")
        .option(
            "url",
            f"jdbc:postgresql://{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DATABASE}",
        )
        .option("dbtable", f'public."{table_name}"')
        .option("user", POSTGRES_USERNAME)
        .option("password", POSTGRES_PASSWORD)
        .option("driver", "org.postgresql.Driver")
        .load()
        .select(PK_FIELD)
    )
    pg_ids = {row[PK_FIELD] for row in pg_ids_df.collect()}

    ids_to_delete = list(pg_ids - mongo_ids)
    if not ids_to_delete:
        logger.info("No deletes detected.")
        return 0

    conn = get_pg_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            f'DELETE FROM public."{table_name}" WHERE "{PK_FIELD}" = ANY(%s)',
            (ids_to_delete,),
        )
        conn.commit()
        deleted = cur.rowcount
        logger.info(f"Deleted {deleted} row(s) no longer present in Mongo.")
        return deleted
    finally:
        conn.close()


# =========================================================
# MAIN SYNC PER COLLECTION
# =========================================================

def sync_collection(
    spark: SparkSession,
    collection_name: str,
    table_name: str,
    full_refresh: bool = False,
) -> TableSyncReport:
    mode_label = "FULL REFRESH" if full_refresh else "Incremental"
    report = TableSyncReport(
        collection=collection_name,
        table=table_name,
        mode=mode_label,
    )

    print()
    print(SEPARATOR)
    print(f"  TABLE  : public.\"{table_name}\"")
    print(f"  SOURCE : MongoDB collection  →  {collection_name}")
    print(f"  MODE   : {mode_label}")
    print(SEPARATOR)

    try:
        if full_refresh:
            drop_table_if_exists(table_name)
            watermark = None
        else:
            watermark = load_watermark(collection_name)

        # ── Capture pre-run Postgres row count ──────────────────────────────
        report.rows_before = get_pg_row_count(table_name)
        logger.info(
            f"[{collection_name}] Rows in Postgres before sync: {report.rows_before:,}"
        )

        # ── Fetch from MongoDB ───────────────────────────────────────────────
        df = read_incremental(spark, collection_name, watermark)
        row_count = df.count()
        report.rows_in_mongo = row_count
        logger.info(f"[{collection_name}] Fetched {row_count:,} row(s) from Mongo")

        if row_count > 0:
            df, pg_types = flatten_for_postgres(df)
            ensure_table_exists(table_name, pg_types)
            sync_table_schema(table_name, pg_types)

            # ── Count how many of the fetched IDs already exist in PG ───────
            fetched_ids = [row[PK_FIELD] for row in df.select(PK_FIELD).collect()]
            existing_count = count_existing_ids(table_name, fetched_ids)
            report.rows_updated = existing_count
            report.rows_inserted = row_count - existing_count

            # ── Upsert ───────────────────────────────────────────────────────
            columns = df.columns
            df.foreachPartition(
                lambda rows: upsert_partition(rows, table_name, columns)
            )
            logger.info(
                f"[{collection_name}] Upserted {row_count:,} rows "
                f"({report.rows_inserted:,} new, {report.rows_updated:,} updated)"
            )

            # ── Advance watermark ─────────────────────────────────────────────
            if UPDATED_AT_FIELD in df.columns:
                max_updated = df.agg(F.max(UPDATED_AT_FIELD)).collect()[0][0]
                if max_updated is not None:
                    wm_str = to_watermark_string(max_updated)
                    save_watermark(collection_name, wm_str)
                    logger.info(f"[{collection_name}] Watermark updated to {wm_str}")
        else:
            logger.info(f"[{collection_name}] No rows to upsert.")

        # ── Delete handling ──────────────────────────────────────────────────
        if full_refresh:
            logger.info(
                f"[{collection_name}] Full refresh — table was rebuilt; skipping delete-diff."
            )
        else:
            report.rows_deleted = handle_deletes(spark, collection_name, table_name)

        # ── Capture post-run Postgres row count ──────────────────────────────
        report.rows_after = get_pg_row_count(table_name)
        logger.info(
            f"[{collection_name}] Rows in Postgres after sync: {report.rows_after:,}"
        )

    except Exception as exc:
        report.error = str(exc)
        logger.error(f"[{collection_name}] Sync FAILED: {exc}", exc_info=True)

    return report


# =========================================================
# ENTRY POINT
# =========================================================

def run(
    collection_name: str = None,
    table_name: str = None,
    full_refresh: bool = False,
):
    summary = RunSummary()
    spark = build_spark_session()

    try:
        if collection_name:
            targets = [(collection_name, table_name or collection_name)]
        else:
            targets = [(c, c) for c in ALL_COLLECTIONS]

        mode = "FULL REFRESH" if full_refresh else "incremental"
        logger.info(
            f"Starting {mode} sync for {len(targets)} collection(s): "
            f"{[t[0] for t in targets]}"
        )

        for cname, tname in targets:
            report = sync_collection(spark, cname, tname, full_refresh)
            summary.add(report)

            if report.error and collection_name:
                # Single-collection mode → fail loudly so CI/CD catches it.
                raise RuntimeError(
                    f"Sync failed for '{cname}': {report.error}"
                )
    finally:
        spark.stop()

    summary.finish()
    summary.print_report()

    # Exit with non-zero code if any table failed (useful for orchestrators).
    failed = [r for r in summary.tables if r.error]
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Mongo -> Postgres sync (incremental or full refresh)"
    )
    parser.add_argument(
        "--collection",
        required=False,
        default=None,
        help="MongoDB collection name. Omit to run ALL_COLLECTIONS.",
    )
    parser.add_argument(
        "--table",
        required=False,
        default=None,
        help=(
            "Target Postgres table name (defaults to collection name). "
            "Only used with --collection."
        ),
    )
    parser.add_argument(
        "--full-refresh",
        action="store_true",
        help=(
            "Drop and rebuild the target table(s) from a full Mongo read "
            "instead of incremental sync."
        ),
    )
    args = parser.parse_args()

    run(
        collection_name=args.collection,
        table_name=args.table,
        full_refresh=args.full_refresh,
    )