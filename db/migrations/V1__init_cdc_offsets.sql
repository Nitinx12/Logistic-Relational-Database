-- Adds ops.cdc_offsets for CDC resume tokens.
CREATE SCHEMA IF NOT EXISTS ops;
CREATE TABLE IF NOT EXISTS ops.cdc_offsets (
    collection TEXT PRIMARY KEY,
    resume_token TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
