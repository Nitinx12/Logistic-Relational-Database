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

REQUIREMENTS
------------
    pip install pyspark psycopg2-binary

You already have the Postgres JDBC driver at driver/postgresql.jar.
You'll also need the MongoDB Spark Connector, fetched automatically via
--packages (since you said Spark has internet access at run time).

IMPORTANT: pick a connector version that matches your Spark + Scala build.
Check your Spark version first:

    python -c "import pyspark; print(pyspark.__version__)"

Then find a matching mongo-spark-connector release here:
https://www.mongodb.com/docs/spark-connector/current/

Most PySpark 3.x installs use Scala 2.12, so the example below uses
`mongo-spark-connector_2.12:10.4.0` -- CHANGE THIS if your setup differs.

RUNNING IT — 4 MODES
---------------------
1. Incremental, ALL collections (default — no flags):
       python scripts/mongo_to_postgres.py

2. Incremental, ONE collection only:
       python scripts/mongo_to_postgres.py --collection loads

3. Full refresh, ALL collections (drops + rebuilds every table from a
   full Mongo read, ignoring the watermark):
       python scripts/mongo_to_postgres.py --full-refresh

4. Full refresh, ONE collection only:
       python scripts/mongo_to_postgres.py --full-refresh --collection loads

Optional: give the Postgres table a different name than the collection
(only applies when --collection is also given):
       python scripts/mongo_to_postgres.py --collection loads --table loads_v2

The list of collections used for "ALL collections" modes lives in the
ALL_COLLECTIONS constant below — update it if your collection names change.

KNOWN LIMITATIONS (MVP, by design given your answers)
-------------------------------------------------------
- Table schema is inferred ONCE from the first batch that creates the
  table. If brand-new fields show up in Mongo later that weren't present
  in that first batch, inserts referencing those fields will fail until
  you add the column manually (`ALTER TABLE ... ADD COLUMN ...`).
- Delete-diffing pulls the full set of `_id`s from both Mongo and Postgres
  into the driver. Fine for low millions of rows; if your collection is
  huge, this step will need to move to a join-based approach instead.
- Nested objects/arrays in Mongo documents are stored as JSONB columns in
  Postgres (stringified JSON via to_json). Top-level scalars (numbers,
  strings, booleans, dates) keep their native Postgres type.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

# This script is expected to live in <project_root>/scripts/, with
# utils/, driver/, and watermark.json all living in <project_root>/.
# Add the project root to sys.path so `from utils.connection import ...`
# works no matter where this script is invoked from.
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

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

# CHANGE THIS to match your Spark version (see docstring above).
MONGO_SPARK_CONNECTOR_PACKAGE = "org.mongodb.spark:mongo-spark-connector_2.12:10.4.0"

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
    """Normalize a Spark-collected timestamp value into an ISO-8601 UTC string."""
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    return str(value)


# =========================================================
# SPARK SESSION
# =========================================================

def build_spark_session() -> SparkSession:
    return (
        SparkSession.builder.appName("mongo_to_postgres_sync")
        .config("spark.jars", POSTGRES_JDBC_JAR)
        .config("spark.jars.packages", MONGO_SPARK_CONNECTOR_PACKAGE)
        .config("spark.mongodb.read.connection.uri", MONGO_URI)
        .config("spark.mongodb.read.database", MONGO_DB)
        .getOrCreate()
    )


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

def normalize_pk(df):
    """Mongo's connector sometimes reads ObjectId as a struct {oid: string}.
    Flatten that down to a plain string so it matches a Postgres TEXT PK."""
    pk_type = df.schema[PK_FIELD].dataType
    if isinstance(pk_type, StructType) and "oid" in pk_type.fieldNames():
        df = df.withColumn(PK_FIELD, F.col(f"{PK_FIELD}.oid"))
    else:
        df = df.withColumn(PK_FIELD, F.col(PK_FIELD).cast("string"))
    return df


def flatten_for_postgres(df):
    """Stringify nested structs/arrays/maps as JSON; leave scalars/dates as-is."""
    df = normalize_pk(df)
    cols = []
    for field in df.schema.fields:
        if field.name == PK_FIELD:
            cols.append(F.col(field.name))
            continue
        if isinstance(field.dataType, (StructType, ArrayType, MapType)):
            cols.append(F.to_json(F.col(field.name)).alias(field.name))
        else:
            cols.append(F.col(field.name))
    return df.select(*cols)


def spark_type_to_postgres(data_type) -> str:
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


def ensure_table_exists(df, table_name: str):
    cols_sql = []
    for field in df.schema.fields:
        pg_type = spark_type_to_postgres(field.dataType)
        if field.name == PK_FIELD:
            pg_type = "TEXT"
        cols_sql.append(f'"{field.name}" {pg_type}')

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
        logger.info(f"Ensured table public.\"{table_name}\" exists")
    finally:
        conn.close()


def upsert_partition(rows, table_name: str, columns: list):
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
        update_clause = ", ".join(f'"{c}" = EXCLUDED."{c}"' for c in columns if c != PK_FIELD)
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
                "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = %s",
                (table_name,),
            )
            return cur.fetchone() is not None
    finally:
        conn.close()


def drop_table_if_exists(table_name: str):
    """Used by --full-refresh: wipes the table so it gets rebuilt fresh from
    whatever schema this run's full Mongo read produces (also fixes schema
    drift, since ensure_table_exists() re-infers columns from scratch)."""
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

def handle_deletes(spark: SparkSession, collection_name: str, table_name: str):
    if not table_exists(table_name):
        logger.info("Target table doesn't exist yet — skipping delete check.")
        return

    mongo_ids = {row[PK_FIELD] for row in read_all_ids(spark, collection_name).collect()}

    pg_ids_df = (
        spark.read.format("jdbc")
        .option("url", f"jdbc:postgresql://{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DATABASE}")
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
        return

    conn = get_pg_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            f'DELETE FROM public."{table_name}" WHERE "{PK_FIELD}" = ANY(%s)',
            (ids_to_delete,),
        )
        conn.commit()
        logger.info(f"Deleted {cur.rowcount} row(s) no longer present in Mongo.")
    finally:
        conn.close()


# =========================================================
# MAIN
# =========================================================

def sync_collection(spark: SparkSession, collection_name: str, table_name: str, full_refresh: bool = False):
    mode_label = "FULL REFRESH" if full_refresh else "Incremental sync"
    logger.info(f"--- {mode_label}: {collection_name} -> public.{table_name} ---")

    if full_refresh:
        drop_table_if_exists(table_name)
        watermark = None
    else:
        watermark = load_watermark(collection_name)

    df = read_incremental(spark, collection_name, watermark)
    row_count = df.count()
    logger.info(f"Fetched {row_count} row(s) from Mongo for {collection_name}")

    if row_count > 0:
        df = flatten_for_postgres(df)
        ensure_table_exists(df, table_name)

        columns = df.columns
        df.foreachPartition(lambda rows: upsert_partition(rows, table_name, columns))

        max_updated = df.agg(F.max(UPDATED_AT_FIELD)).collect()[0][0]
        if max_updated is not None:
            save_watermark(collection_name, to_watermark_string(max_updated))
            logger.info(f"Watermark for {collection_name} updated to {to_watermark_string(max_updated)}")
    else:
        logger.info(f"No rows for {collection_name} — nothing to upsert.")

    if full_refresh:
        logger.info("Full refresh — table was dropped & rebuilt, skipping delete-diff.")
    else:
        handle_deletes(spark, collection_name, table_name)


def run(collection_name: str = None, table_name: str = None, full_refresh: bool = False):
    spark = build_spark_session()
    try:
        if collection_name:
            targets = [(collection_name, table_name or collection_name)]
        else:
            targets = [(c, c) for c in ALL_COLLECTIONS]

        logger.info(f"Running {'FULL REFRESH' if full_refresh else 'incremental'} sync for: "
                    f"{[t[0] for t in targets]}")

        for cname, tname in targets:
            try:
                sync_collection(spark, cname, tname, full_refresh)
            except Exception as e:
                logger.error(f"Sync failed for {cname}: {e}")
                if collection_name:
                    raise  # single-collection mode: fail loudly
                # all-collections mode: log and keep going with the rest
    finally:
        spark.stop()
    logger.info("All sync job(s) complete.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Mongo -> Postgres sync (incremental or full refresh)")
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
        help="Target Postgres table name (defaults to collection name). Only used with --collection.",
    )
    parser.add_argument(
        "--full-refresh",
        action="store_true",
        help="Drop and rebuild the target table(s) from a full Mongo read instead of incremental sync.",
    )
    args = parser.parse_args()

    run(collection_name=args.collection, table_name=args.table, full_refresh=args.full_refresh)