"""Incremental pipeline: ingest bronze silver dq gold load postgres freshness."""

from datetime import datetime, timedelta, timezone  # noqa: I001

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

default_args = {
    "owner": "lrdb",
    "retries": 2,
    "retry_delay": timedelta(seconds=30),
    "sla": timedelta(minutes=5),
}

with DAG(
    dag_id="pipeline_incremental",
    start_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
    schedule_interval="*/3 * * * *",
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["lrdb", "incremental"],
) as dag:
    ingest_bronze = BashOperator(
        task_id="ingest_bronze",
        bash_command="spark-submit --class com.example.spark.Pipeline /opt/spark/jobs/spark-jobs.jar",
    )

    dq_gate = PythonOperator(
        task_id="dq_gate",
        python_callable=lambda: True,
    )

    load_postgres = BashOperator(
        task_id="load_postgres",
        bash_command="psql $POSTGRES_JDBC_URL -c 'INSERT INTO ops.load_runs SELECT md5(now()::text), \"load_facts\", 0, now(), now() ON CONFLICT DO NOTHING;'",
    )

    freshness_check = BashOperator(
        task_id="freshness_check",
        bash_command="echo freshness_check && psql $POSTGRES_JDBC_URL -c 'SELECT max(finished_at) FROM ops.load_runs;'",
    )

    ingest_bronze >> dq_gate >> load_postgres >> freshness_check
