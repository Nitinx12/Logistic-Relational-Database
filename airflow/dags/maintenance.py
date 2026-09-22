"""Nightly maintenance: Delta optimize vacuum and Postgres analyze."""

from datetime import datetime, timedelta, timezone

from airflow.operators.bash import BashOperator

from airflow import DAG

default_args = {
    "owner": "lrdb",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
    "sla": timedelta(minutes=30),
}

with DAG(
    dag_id="maintenance",
    start_date=datetime(2024, 1, 1, tzinfo=timezone.utc),
    schedule_interval="0 2 * * *",
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["lrdb", "maintenance"],
) as dag:
    optimize = BashOperator(
        task_id="delta_optimize",
        bash_command="spark-submit --class com.example.spark.Maintenance /opt/spark/jobs/spark-jobs.jar optimize",
    )

    vacuum = BashOperator(
        task_id="delta_vacuum",
        bash_command="spark-submit --class com.example.spark.Maintenance /opt/spark/jobs/spark-jobs.jar vacuum",
    )

    landing_retention = BashOperator(
        task_id="landing_retention",
        bash_command="find /landing -type f -mtime +7 -delete || echo 'no landing dir'",
    )

    vacuum_analyze = BashOperator(
        task_id="postgres_vacuum_analyze",
        bash_command="psql $POSTGRES_JDBC_URL -c 'VACUUM ANALYZE gold.load_facts; VACUUM ANALYZE gold.customer_summary;'",
    )

    reject_report = BashOperator(
        task_id="reject_report",
        bash_command="psql $POSTGRES_JDBC_URL -c 'SELECT reason_code, count(*) FROM ops.silver_rejects GROUP BY 1;'",
    )

    optimize >> vacuum >> landing_retention >> vacuum_analyze >> reject_report
