"""Manual backfill: snapshot Mongo collection to landing and full rebuild."""

from datetime import datetime, timedelta, timezone

from airflow import DAG
from airflow.operators.bash import BashOperator

default_args = {"owner": "lrdb", "retries": 1, "retry_delay": timedelta(minutes=1)}

with DAG(
    dag_id="pipeline_backfill",
    start_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
    schedule_interval=None,
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    params={"collection": "loads"},
    tags=["lrdb", "backfill"],
) as dag:
    snapshot = BashOperator(
        task_id="snapshot_collection",
        bash_command="echo snapshot {{ params.collection }} to landing/{{ params.collection }}/dt=$(date +%F)",
    )
    rebuild = BashOperator(
        task_id="rebuild_bronze_silver_gold",
        bash_command="spark-submit --class com.example.spark.Pipeline /opt/spark/jobs/spark-jobs.jar",
    )
    snapshot >> rebuild
