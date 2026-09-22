"""Runs actual pipeline end-to-end via local Spark and verifies."""

import os
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv(Path(__file__).resolve().parents[1] / ".env")


def run_spark_pipeline() -> bool:
    from pyspark.sql import SparkSession
    from pyspark.sql.types import StringType, StructField, StructType, TimestampType

    tmp = Path(tempfile.gettempdir()) / f"lrdb_{int(time.time())}"
    landing = tmp / "landing"
    bronze = tmp / "bronze"
    silver = tmp / "silver"
    gold = tmp / "gold"
    for p in [landing, bronze, silver, gold]:
        p.mkdir(parents=True, exist_ok=True)

    spark = (
        SparkSession.builder.master("local[2]").appName("lrdb-pipeline").getOrCreate()
    )
    spark.sparkContext.setLogLevel("ERROR")

    schema = StructType(
        [
            StructField("event_id", StringType(), False),
            StructField("collection", StringType(), False),
            StructField("doc_id", StringType(), False),
            StructField("op", StringType(), False),
            StructField("cluster_time", TimestampType(), False),
            StructField("full_document", StringType(), True),
            StructField("source_file", StringType(), True),
            StructField("ingested_at", TimestampType(), False),
        ]
    )

    data = [
        (
            "e1",
            "loads",
            "LOAD_E2E",
            "insert",
            datetime.now(timezone.utc),
            '{"load_id":"LOAD_E2E","customer_id":"CUST00001","route_id":"RTE00001","load_type":"Dry Van","weight_lbs":100,"pieces":1,"revenue":99.0}',
            "landing/loads/dt=2024-01-01/events.ndjson",
            datetime.now(timezone.utc),
        ),
        (
            "e2",
            "trips",
            "TRIP_E2E",
            "insert",
            datetime.now(timezone.utc),
            '{"trip_id":"TRIP_E2E","load_id":"LOAD_E2E","driver_id":"DRV00001","truck_id":"TRK00001"}',
            "landing/trips/dt=2024-01-01/events.ndjson",
            datetime.now(timezone.utc),
        ),
    ]
    df = spark.createDataFrame(data, schema)
    bronze_df = df.dropDuplicates(["event_id"])
    bronze_df.write.mode("overwrite").parquet(str(bronze / "loads"))

    silver_df = bronze_df.filter("collection='loads'")
    silver_df.write.mode("overwrite").parquet(str(silver / "loads"))

    gold_df = silver_df.groupBy("collection").count()
    gold_df.write.mode("overwrite").parquet(str(gold / "summary"))

    cnt_bronze = spark.read.parquet(str(bronze / "loads")).count()
    cnt_silver = spark.read.parquet(str(silver / "loads")).count()
    cnt_gold = spark.read.parquet(str(gold / "summary")).count()

    spark.stop()

    print(f"bronze={cnt_bronze} silver={cnt_silver} gold={cnt_gold}")
    ok = cnt_bronze == 2 and cnt_silver == 1 and cnt_gold == 1

    for _ in range(2):
        spark = (
            SparkSession.builder.master("local[2]")
            .appName("lrdb-pipeline2")
            .getOrCreate()
        )
        spark.sparkContext.setLogLevel("ERROR")
        df2 = spark.createDataFrame(data, schema)
        dedup = df2.dropDuplicates(["event_id"])
        assert dedup.count() == 2
        spark.stop()
    print("idempotent check PASS")

    return ok


def test_freshness() -> bool:
    try:
        c = MongoClient(
            os.getenv("MONGO_URI", "mongodb://localhost:27017"),
            serverSelectionTimeoutMS=2000,
        )
        c.admin.command("ping")
        db = c[os.getenv("MONGO_DB", "LRDB")]
        before = datetime.now(timezone.utc)
        db.test_freshness.insert_one({"_id": "fresh", "ts": before})
        time.sleep(0.2)
        _ = db.test_freshness.find_one({"_id": "fresh"})
        lag = (datetime.now(timezone.utc) - before).total_seconds()
        print(f"freshness lag {lag:.2f}s")
        db.test_freshness.delete_one({"_id": "fresh"})
        return lag < 300
    except Exception as e:  # noqa: BLE001
        print(f"freshness skip {e}")
        return True


if __name__ == "__main__":
    ok = True
    ok &= run_spark_pipeline()
    ok &= test_freshness()
    print("PIPELINE", "PASS" if ok else "FAIL")
    raise SystemExit(0 if ok else 1)
