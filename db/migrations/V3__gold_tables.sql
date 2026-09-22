-- Creates gold schema and core business tables derived from EDA.
CREATE SCHEMA IF NOT EXISTS gold;

CREATE TABLE IF NOT EXISTS gold.load_facts (
    load_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL REFERENCES gold.customer_summary (
        customer_id
    ) DEFERRABLE,
    route_id TEXT NOT NULL,
    load_date DATE NOT NULL,
    load_type TEXT NOT NULL,
    weight_lbs INTEGER NOT NULL CHECK (weight_lbs > 0),
    pieces INTEGER NOT NULL CHECK (pieces > 0),
    revenue NUMERIC(12, 2) NOT NULL,
    fuel_surcharge NUMERIC(12, 2) NOT NULL,
    accessorial_charges NUMERIC(12, 2) NOT NULL DEFAULT 0,
    load_status TEXT NOT NULL,
    booking_type TEXT NOT NULL,
    trip_id TEXT,
    driver_id TEXT,
    truck_id TEXT,
    trailer_id TEXT,
    actual_distance_miles NUMERIC(10, 2),
    actual_duration_hours NUMERIC(10, 2),
    fuel_gallons_used NUMERIC(10, 2),
    average_mpg NUMERIC(6, 2),
    origin_city TEXT,
    origin_state TEXT,
    destination_city TEXT,
    destination_state TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gold.customer_summary (
    customer_id TEXT PRIMARY KEY,
    customer_name TEXT NOT NULL,
    customer_type TEXT NOT NULL,
    account_status TEXT NOT NULL,
    annual_revenue_potential NUMERIC(14, 2),
    total_loads BIGINT NOT NULL DEFAULT 0,
    total_revenue NUMERIC(14, 2) NOT NULL DEFAULT 0,
    last_load_date DATE,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gold.route_metrics_daily (
    route_id TEXT NOT NULL,
    metric_date DATE NOT NULL,
    loads_count BIGINT NOT NULL DEFAULT 0,
    total_revenue NUMERIC(14, 2) NOT NULL DEFAULT 0,
    avg_weight_lbs NUMERIC(10, 2),
    avg_revenue NUMERIC(12, 2),
    PRIMARY KEY (route_id, metric_date)
);

CREATE TABLE IF NOT EXISTS gold.driver_performance_monthly (
    driver_id TEXT NOT NULL,
    metric_month DATE NOT NULL,
    trips_completed INTEGER NOT NULL DEFAULT 0,
    total_miles NUMERIC(12, 2) NOT NULL DEFAULT 0,
    total_revenue NUMERIC(14, 2) NOT NULL DEFAULT 0,
    on_time_delivery_rate NUMERIC(5, 4),
    avg_mpg NUMERIC(5, 2),
    PRIMARY KEY (driver_id, metric_month)
);

CREATE TABLE IF NOT EXISTS gold.facility_metrics (
    facility_id TEXT PRIMARY KEY,
    facility_name TEXT NOT NULL,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    facility_type TEXT NOT NULL,
    total_deliveries BIGINT NOT NULL DEFAULT 0,
    avg_detention_minutes NUMERIC(8, 2),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_load_facts_customer ON gold.load_facts (
    customer_id
);
CREATE INDEX IF NOT EXISTS idx_load_facts_route ON gold.load_facts (route_id);
CREATE INDEX IF NOT EXISTS idx_load_facts_date ON gold.load_facts (load_date);
