-- Creates least-privilege roles per arch 7.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'serving_writer') THEN
        CREATE ROLE serving_writer LOGIN PASSWORD 'serving_writer';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agent_reader') THEN
        CREATE ROLE agent_reader LOGIN PASSWORD 'agent_reader';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dashboard_reader') THEN
        CREATE ROLE dashboard_reader LOGIN PASSWORD 'dashboard_reader';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ops_rw') THEN
        CREATE ROLE ops_rw LOGIN PASSWORD 'ops_rw';
    END IF;
END $$;

GRANT USAGE ON SCHEMA gold TO serving_writer, agent_reader, dashboard_reader;
GRANT USAGE ON SCHEMA serving TO serving_writer;
GRANT USAGE ON SCHEMA agent_api TO agent_reader;
GRANT USAGE ON SCHEMA ops TO ops_rw;

GRANT SELECT,
INSERT,
UPDATE,
DELETE ON ALL TABLES IN SCHEMA gold TO serving_writer;
GRANT SELECT,
INSERT,
UPDATE,
DELETE ON ALL TABLES IN SCHEMA serving TO serving_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA gold TO dashboard_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA agent_api TO agent_reader;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ops TO ops_rw;

ALTER DEFAULT PRIVILEGES IN SCHEMA gold GRANT SELECT,
INSERT,
UPDATE,
DELETE ON TABLES TO serving_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA serving GRANT SELECT,
INSERT,
UPDATE,
DELETE ON TABLES TO serving_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA ops GRANT SELECT,
INSERT,
UPDATE,
DELETE ON TABLES TO ops_rw;

ALTER ROLE agent_reader SET statement_timeout = '5s';
ALTER ROLE dashboard_reader SET statement_timeout = '10s';
