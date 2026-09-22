-- Exposes read-only views for agent-service per arch 7.
CREATE SCHEMA IF NOT EXISTS agent_api;

CREATE OR REPLACE VIEW agent_api.customer_summary AS
SELECT
    customer_id,
    customer_name,
    customer_type,
    account_status,
    total_loads,
    total_revenue,
    last_load_date
FROM gold.customer_summary;

CREATE OR REPLACE VIEW agent_api.load_facts AS
SELECT
    load_id,
    customer_id,
    route_id,
    load_date,
    load_type,
    weight_lbs,
    pieces,
    revenue,
    load_status,
    booking_type,
    trip_id,
    driver_id
FROM gold.load_facts;

CREATE OR REPLACE VIEW agent_api.route_metrics AS
SELECT
    route_id,
    metric_date,
    loads_count,
    total_revenue,
    avg_revenue
FROM gold.route_metrics_daily;

CREATE OR REPLACE VIEW agent_api.driver_performance AS
SELECT
    driver_id,
    month,
    trips_completed,
    total_miles,
    total_revenue,
    on_time_delivery_rate
FROM gold.driver_performance_monthly;

CREATE OR REPLACE VIEW agent_api.recent_loads AS
SELECT
    load_id,
    customer_id,
    load_date,
    revenue,
    load_status
FROM gold.load_facts
ORDER BY load_date DESC
LIMIT 1000;
