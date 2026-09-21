-- Adds ops.load_runs for pipeline load tracking.
CREATE TABLE IF NOT EXISTS ops.load_runs (
    run_id TEXT PRIMARY KEY,
    table_name TEXT NOT NULL,
    row_count BIGINT NOT NULL,
    source_max_cluster_time TIMESTAMPTZ,
    finished_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
