"""
sync_mongo_to_postgres.py

Incremental MongoDB -> PostgreSQL loader using Pandas & PyMongo.
- Tracks `updated_at` watermarks in project root.
- Drops MongoDB `_id`.
- Performs an Append-Only incremental load.
- Enforces strict target schema types (VARCHAR, BIGINT, DATE, TIMESTAMP, NUMERIC).
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from typing import Optional

import pandas as pd
from pymongo import MongoClient
import psycopg2
from psycopg2.extras import execute_values

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

logger = get_logger("extraction", "mongo_to_postgres_sync")

# =========================================================
# CONFIG
# =========================================================

BATCH_SIZE = 25000
UPDATED_AT_FIELD = "updated_at"
WATERMARK_FILE = os.path.join(PROJECT_ROOT, "watermark.json")
SEPARATOR = "=" * 72

ALL_COLLECTIONS = [
    "customers", "delivery_events", "drivers", "driver_monthly_metrics",
    "facilities", "fuel_purchases", "loads", "maintenance_records",
    "routes", "safety_incidents", "trailers", "trips", "trucks",
    "truck_utilization_metrics",
]

# =========================================================
# WATERMARK MANAGEMENT
# =========================================================

def load_watermark(collection_name: str) -> Optional[datetime]:
    if os.path.exists(WATERMARK_FILE):
        try:
            with open(WATERMARK_FILE, "r") as f:
                data = json.load(f)
                wm_str = data.get(collection_name)
                if wm_str:
                    return datetime.fromisoformat(wm_str.replace("Z", "+00:00"))
        except Exception as e:
            logger.warning(f"Failed to read watermark for {collection_name}: {e}")
    return None

def save_watermark(collection_name: str, max_ts: pd.Timestamp):
    if pd.isnull(max_ts):
        return

    wm_str = max_ts.isoformat()
    if not wm_str.endswith("Z") and "+" not in wm_str:
        wm_str += "Z"
        
    data = {}
    if os.path.exists(WATERMARK_FILE):
        try:
            with open(WATERMARK_FILE, "r") as f:
                data = json.load(f)
        except Exception:
            pass

    data[collection_name] = wm_str
    
    with open(WATERMARK_FILE, "w") as f:
        json.dump(data, f, indent=2)

# =========================================================
# POSTGRES HELPERS & DDL
# =========================================================

def get_pg_connection():
    return psycopg2.connect(
        host=POSTGRES_HOST, port=POSTGRES_PORT, dbname=POSTGRES_DATABASE,
        user=POSTGRES_USERNAME, password=POSTGRES_PASSWORD
    )

def _pg_safe_identifier(name: str) -> str:
    safe = re.sub(r"[^0-9A-Za-z_]", "_", name)
    if not safe or safe[0].isdigit(): safe = f"_{safe}"
    return safe[:63].lower()

def extract_schema_and_flatten(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    pg_types = {}
    
    # Drop _id as requested
    if '_id' in df.columns:
        df = df.drop(columns=['_id'])

    rename_map = {col: _pg_safe_identifier(col) for col in df.columns}
    df = df.rename(columns=rename_map)

    # Hardcoded schema mapping based on PostgreSQL definitions
    BIGINT_COLS = {
        'credit_terms_days', 'annual_revenue_potential', 'detention_minutes',
        'trips_completed', 'total_miles', 'years_experience', 'dock_doors',
        'weight_lbs', 'pieces', 'accessorial_charges', 'odometer_reading',
        'typical_distance_miles', 'typical_transit_days', 'trailer_number',
        'length_feet', 'model_year', 'actual_distance_miles', 'maintenance_events',
        'unit_number', 'acquisition_mileage', 'tank_capacity_gallons'
    }

    NUMERIC_COLS = {
        'total_revenue', 'average_mpg', 'total_fuel_gallons', 'on_time_delivery_rate',
        'average_idle_hours', 'latitude', 'longitude', 'gallons', 'price_per_gallon',
        'total_cost', 'revenue', 'fuel_surcharge', 'labor_hours', 'labor_cost', 'parts_cost',
        'downtime_hours', 'base_rate_per_mile', 'fuel_surcharge_rate', 'vehicle_damage_cost',
        'cargo_damage_cost', 'claim_amount', 'actual_duration_hours', 'fuel_gallons_used',
        'idle_time_hours', 'maintenance_cost', 'utilization_rate'
    }

    for col in df.columns:
        # 1. TIMESTAMPS
        if col in ['updated_at', 'scheduled_datetime', 'actual_datetime']:
            pg_types[col] = 'TIMESTAMP'
            df[col] = pd.to_datetime(df[col], errors='coerce')
            df[col] = df[col].astype(object).where(pd.notnull(df[col]), None)
            
        # 2. DATES
        elif col.endswith('_date') or col == 'date_of_birth' or col == 'month':
            pg_types[col] = 'DATE'
            df[col] = pd.to_datetime(df[col], errors='coerce').dt.date
            df[col] = df[col].astype(object).where(pd.notnull(df[col]), None)

        # 3. BIGINTS
        elif col in BIGINT_COLS:
            pg_types[col] = 'BIGINT'
            df[col] = pd.to_numeric(df[col], errors='coerce').astype('Int64')
            df[col] = df[col].astype(object).where(pd.notnull(df[col]), None)

        # 4. NUMERICS
        elif col in NUMERIC_COLS:
            pg_types[col] = 'NUMERIC'
            df[col] = pd.to_numeric(df[col], errors='coerce')
            df[col] = df[col].astype(object).where(pd.notnull(df[col]), None)

        # 5. JSONB OR VARCHAR
        else:
            first_valid = df[col].dropna().iloc[0] if not df[col].dropna().empty else None
            
            if isinstance(first_valid, (dict, list)):
                pg_types[col] = 'JSONB'
                df[col] = df[col].apply(lambda x: json.dumps(x, default=str) if isinstance(x, (dict, list)) else x)
            else:
                pg_types[col] = 'VARCHAR'
                df[col] = df[col].apply(lambda x: str(x) if pd.notnull(x) else None)
                
    return df, pg_types

def ensure_table_schema(table_name: str, pg_types: dict, is_first_batch: bool, is_full_refresh: bool):
    with get_pg_connection() as conn, conn.cursor() as cur:
        if is_full_refresh and is_first_batch:
            cur.execute(f'DROP TABLE IF EXISTS public."{table_name}"')
            
        cur.execute("SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = %s", (table_name,))
        table_exists = cur.fetchone() is not None

        if not table_exists:
            cols_sql = [f'"{col}" {pg_type}' for col, pg_type in pg_types.items()]
            ddl_create = f'CREATE TABLE public."{table_name}" (\n  ' + ",\n  ".join(cols_sql) + "\n);"
            cur.execute(ddl_create)
        else:
            cur.execute("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = %s", (table_name,))
            existing_cols = {row[0] for row in cur.fetchall()}
            for col, pg_type in pg_types.items():
                if col not in existing_cols:
                    cur.execute(f'ALTER TABLE public."{table_name}" ADD COLUMN "{col}" {pg_type}')

def append_dataframe(df: pd.DataFrame, table_name: str):
    columns = list(df.columns)
    col_list = ", ".join(f'"{c}"' for c in columns)
    sql = f'INSERT INTO public."{table_name}" ({col_list}) VALUES %s'
    
    values = [tuple(x) for x in df.to_numpy()]
    
    with get_pg_connection() as conn, conn.cursor() as cur:
        execute_values(cur, sql, values, page_size=1000)

# =========================================================
# MAIN SYNC
# =========================================================

def fetch_incremental_batches(collection, watermark: Optional[datetime]):
    query = {}
    if watermark:
        query = {UPDATED_AT_FIELD: {"$gt": watermark}}
        
    cursor = collection.find(query).sort(UPDATED_AT_FIELD, 1).batch_size(BATCH_SIZE)
    
    batch = []
    for doc in cursor:
        batch.append(doc)
        if len(batch) == BATCH_SIZE:
            yield batch
            batch = []
    if batch:
        yield batch

def sync_collection(db, collection_name: str, table_name: str, full_refresh: bool):
    logger.info(f"[{collection_name}] Starting sync...")
    
    try:
        coll = db[collection_name]
        watermark = None if full_refresh else load_watermark(collection_name)
        
        if watermark:
            logger.info(f"[{collection_name}] Resuming from watermark: {watermark.isoformat()}")
        else:
            logger.info(f"[{collection_name}] No watermark found or Full Refresh triggered. Pulling all records.")

        is_first_batch = True
        total_inserted = 0
        latest_timestamp = None

        for batch_data in fetch_incremental_batches(coll, watermark):
            df = pd.DataFrame(batch_data)
            
            if UPDATED_AT_FIELD in df.columns:
                batch_max_ts = df[UPDATED_AT_FIELD].max()
                if latest_timestamp is None or batch_max_ts > latest_timestamp:
                    latest_timestamp = batch_max_ts

            df, pg_types = extract_schema_and_flatten(df)
            ensure_table_schema(table_name, pg_types, is_first_batch, full_refresh)
            
            append_dataframe(df, table_name)
            
            total_inserted += len(df)
            is_first_batch = False
            logger.info(f"[{collection_name}] Appended {len(df):,} rows (Total: {total_inserted:,})")

            if latest_timestamp:
                save_watermark(collection_name, latest_timestamp)

        if total_inserted == 0:
            logger.info(f"[{collection_name}] No new records found.")
        else:
            logger.info(f"[{collection_name}] Successfully synced {total_inserted:,} total records.")

        return total_inserted, None

    except Exception as exc:
        logger.error(f"[{collection_name}] Failed: {exc}", exc_info=True)
        return 0, str(exc)

def run(collection_name=None, table_name=None, full_refresh=False):
    print(f"\n{SEPARATOR}\n  MONGO -> POSTGRES SYNC\n{SEPARATOR}")
    
    client = MongoClient(MONGO_URI)
    db = client[MONGO_DB]
    targets = [(collection_name, table_name or collection_name)] if collection_name else [(c, c) for c in ALL_COLLECTIONS]
    
    failed_tables = []
    
    for cname, tname in targets:
        _, error = sync_collection(db, cname, tname, full_refresh)
        if error:
            failed_tables.append((cname, error))
            
    print(SEPARATOR)
    if failed_tables:
        print("  SYNC FAILED FOR:")
        for tbl, err in failed_tables:
            print(f"    - {tbl}: {err}")
        sys.exit(1)
    else:
        print("  ALL TABLES SYNCED SUCCESSFULLY.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--collection", default=None)
    parser.add_argument("--table", default=None)
    parser.add_argument("--full-refresh", action="store_true", help="Ignore watermark, wipe target table, and load everything.")
    args = parser.parse_args()
    
    run(args.collection, args.table, args.full_refresh)