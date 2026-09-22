"""DagBag import, no cycles, retry and SLA checks."""

from pathlib import Path

import pytest

try:
    from airflow.models import DagBag
except ImportError:
    DagBag = None  # type: ignore[assignment]


@pytest.mark.skipif(DagBag is None, reason="airflow not installed")
def test_dagbag_import():
    bag = DagBag(
        dag_folder=str(Path(__file__).resolve().parents[1] / "dags"),
        include_examples=False,
    )
    assert bag.import_errors == {}, f"import errors: {bag.import_errors}"
    assert len(bag.dags) >= 3
    for dag_id, dag in bag.dags.items():
        assert dag.catchup is False or dag_id == "pipeline_backfill"
        assert dag.max_active_runs == 1
        for task in dag.tasks:
            assert task.retries >= 1
            assert (
                task.sla is not None
                or "retries" in task.default_args
                or task.retries >= 1
            )


def test_no_cycles():
    if DagBag is None:
        pytest.skip("airflow not installed")
    bag = DagBag(
        dag_folder=str(Path(__file__).resolve().parents[1] / "dags"),
        include_examples=False,
    )
    for dag in bag.dags.values():
        assert dag.test_cycle() is None
