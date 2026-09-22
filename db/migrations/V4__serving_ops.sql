-- Creates serving, ops extensions and silver rejects per arch 6.3-6.6.
CREATE SCHEMA IF NOT EXISTS serving;
CREATE SCHEMA IF NOT EXISTS ops;

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS serving.load_facts_stg (
    LIKE gold.load_facts INCLUDING ALL
);
CREATE TABLE IF NOT EXISTS serving.customer_summary_stg (
    LIKE gold.customer_summary INCLUDING ALL
);
CREATE TABLE IF NOT EXISTS serving.route_metrics_daily_stg (
    LIKE gold.route_metrics_daily INCLUDING ALL
);

CREATE TABLE IF NOT EXISTS serving.doc_chunks (
    chunk_id TEXT PRIMARY KEY,
    source TEXT NOT NULL, -- noqa: RF04
    content TEXT NOT NULL, -- noqa: RF04
    content_hash TEXT NOT NULL,
    embedding VECTOR(384), -- noqa: CP05
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_doc_chunks_embedding -- noqa: LT05
ON serving.doc_chunks USING hnsw (
    embedding vector_l2_ops
);

CREATE TABLE IF NOT EXISTS ops.silver_rejects (
    reject_id TEXT PRIMARY KEY,
    collection TEXT NOT NULL,
    doc_id TEXT NOT NULL,
    reason_code TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ops.dq_results (
    run_id TEXT PRIMARY KEY,
    table_name TEXT NOT NULL,
    passed BOOLEAN NOT NULL,
    null_rate NUMERIC(5, 4),
    duplicate_count BIGINT,
    reject_ratio NUMERIC(5, 4),
    row_count BIGINT,
    checked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE ops.load_runs ADD COLUMN IF NOT EXISTS table_name TEXT;
