-- ============================================================
-- Financial Validation Triggers with Audit Logging
-- ============================================================
-- Pattern: BEFORE INSERT/UPDATE triggers that reject rows
-- violating financial rules, while persisting a record of the
-- rejected attempt to financial_validation_log.
--
-- IMPORTANT: Because the trigger raises an exception, the
-- transaction is rolled back -- including any plain INSERT into
-- the log table executed earlier in the same trigger function.
-- To make the log entry survive the rollback, we write it via
-- dblink, which opens its own autocommitted connection back to
-- the same database. This is the standard way to get "reject AND
-- log" behavior out of a single trigger in Postgres.
-- ============================================================

-- 0. Prerequisite extension (run once, needs sufficient privileges)
CREATE EXTENSION IF NOT EXISTS dblink;

-- 1. Audit log table
CREATE TABLE IF NOT EXISTS financial_validation_log (
    log_id          BIGSERIAL PRIMARY KEY,
    table_name      VARCHAR(50)  NOT NULL,
    record_id       VARCHAR(50)  NOT NULL,
    violation_type  VARCHAR(100) NOT NULL,
    expected_value  NUMERIC,
    actual_value    NUMERIC,
    attempted_by    VARCHAR(100) DEFAULT current_user,
    attempted_at    TIMESTAMP    NOT NULL DEFAULT now(),
    row_snapshot    JSONB
);

CREATE INDEX IF NOT EXISTS idx_fvl_table_time
    ON financial_validation_log (table_name, attempted_at);

-- 2. Autonomous logging helper
--    Adjust the connection string if your DB needs a specific
--    host/port/user (e.g. 'host=localhost dbname=mydb user=etl_user').
--    As written, it connects to the current database using the
--    server's default local auth.
CREATE OR REPLACE FUNCTION log_validation_violation(
    p_table_name   VARCHAR,
    p_record_id    VARCHAR,
    p_violation    VARCHAR,
    p_expected     NUMERIC,
    p_actual       NUMERIC,
    p_row_snapshot JSONB
) RETURNS VOID AS $$
BEGIN
    PERFORM dblink_exec(
        format('dbname=%s', current_database()),
        format(
            'INSERT INTO financial_validation_log
                (table_name, 
                record_id, 
                violation_type, 
                expected_value, 
                actual_value, 
                row_snapshot)
             VALUES (%L, %L, %L, %L, %L, %L)',
            p_table_name, 
            p_record_id, 
            p_violation, 
            p_expected, 
            p_actual, 
            p_row_snapshot
        )
    );
EXCEPTION WHEN OTHERS THEN
    -- If logging itself fails (e.g. dblink misconfigured), don't let
    -- that mask the real validation error -- just surface a warning.
    RAISE WARNING 'Could not write to financial_validation_log: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 3a. fuel_purchases: total_cost = gallons * price_per_gallon
-- ============================================================
CREATE OR REPLACE FUNCTION validate_fuel_purchase_cost()
RETURNS TRIGGER AS $$
DECLARE
    v_expected NUMERIC;
BEGIN
    IF NEW.gallons IS NOT NULL AND NEW.price_per_gallon IS NOT NULL AND NEW.total_cost IS NOT NULL THEN
        v_expected := ROUND(NEW.gallons * NEW.price_per_gallon, 2);
        IF v_expected <> ROUND(NEW.total_cost, 2) THEN
            PERFORM log_validation_violation(
                'fuel_purchases', NEW.fuel_purchase_id, 'total_cost_mismatch',
                v_expected, NEW.total_cost, to_jsonb(NEW)
            );
            RAISE EXCEPTION
                'fuel_purchases %: total_cost (%) does not match gallons * price_per_gallon (%)',
                NEW.fuel_purchase_id, NEW.total_cost, v_expected;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_fuel_purchase_cost ON fuel_purchases;
CREATE TRIGGER trg_validate_fuel_purchase_cost
BEFORE INSERT OR UPDATE ON fuel_purchases
FOR EACH ROW
EXECUTE FUNCTION validate_fuel_purchase_cost();

-- ============================================================
-- 3b. maintenance_records: total_cost = labor_cost + parts_cost
-- ============================================================
CREATE OR REPLACE FUNCTION validate_maintenance_cost()
RETURNS TRIGGER AS $$
DECLARE
    v_expected NUMERIC;
BEGIN
    IF NEW.labor_cost IS NOT NULL AND NEW.parts_cost IS NOT NULL AND NEW.total_cost IS NOT NULL THEN
        v_expected := ROUND(NEW.labor_cost + NEW.parts_cost, 2);
        IF v_expected <> ROUND(NEW.total_cost, 2) THEN
            PERFORM log_validation_violation(
                'maintenance_records', NEW.maintenance_id, 'total_cost_mismatch',
                v_expected, NEW.total_cost, to_jsonb(NEW)
            );
            RAISE EXCEPTION
                'maintenance_records %: total_cost (%) does not match labor_cost + parts_cost (%)',
                NEW.maintenance_id, NEW.total_cost, v_expected;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_maintenance_cost ON maintenance_records;
CREATE TRIGGER trg_validate_maintenance_cost
BEFORE INSERT OR UPDATE ON maintenance_records
FOR EACH ROW
EXECUTE FUNCTION validate_maintenance_cost();

-- ============================================================
-- 3c. loads: revenue / fuel_surcharge / accessorial_charges >= 0
-- ============================================================
CREATE OR REPLACE FUNCTION validate_load_financials()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.revenue IS NOT NULL AND NEW.revenue < 0 THEN
        PERFORM log_validation_violation('loads', NEW.load_id, 'negative_revenue', 0, NEW.revenue, to_jsonb(NEW));
        RAISE EXCEPTION 'loads %: revenue cannot be negative (%)', NEW.load_id, NEW.revenue;
    END IF;

    IF NEW.fuel_surcharge IS NOT NULL AND NEW.fuel_surcharge < 0 THEN
        PERFORM log_validation_violation('loads', NEW.load_id, 'negative_fuel_surcharge', 0, NEW.fuel_surcharge, to_jsonb(NEW));
        RAISE EXCEPTION 'loads %: fuel_surcharge cannot be negative (%)', NEW.load_id, NEW.fuel_surcharge;
    END IF;

    IF NEW.accessorial_charges IS NOT NULL AND NEW.accessorial_charges < 0 THEN
        PERFORM log_validation_violation('loads', NEW.load_id, 'negative_accessorial_charges', 0, NEW.accessorial_charges, to_jsonb(NEW));
        RAISE EXCEPTION 'loads %: accessorial_charges cannot be negative (%)', NEW.load_id, NEW.accessorial_charges;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_load_financials ON loads;
CREATE TRIGGER trg_validate_load_financials
BEFORE INSERT OR UPDATE ON loads
FOR EACH ROW
EXECUTE FUNCTION validate_load_financials();

-- ============================================================
-- 3d. safety_incidents: damage/claim amounts >= 0
-- ============================================================
CREATE OR REPLACE FUNCTION validate_safety_incident_financials()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.vehicle_damage_cost IS NOT NULL AND NEW.vehicle_damage_cost < 0 THEN
        PERFORM log_validation_violation('safety_incidents', NEW.incident_id, 'negative_vehicle_damage_cost', 0, NEW.vehicle_damage_cost, to_jsonb(NEW));
        RAISE EXCEPTION 'safety_incidents %: vehicle_damage_cost cannot be negative (%)', NEW.incident_id, NEW.vehicle_damage_cost;
    END IF;

    IF NEW.cargo_damage_cost IS NOT NULL AND NEW.cargo_damage_cost < 0 THEN
        PERFORM log_validation_violation('safety_incidents', NEW.incident_id, 'negative_cargo_damage_cost', 0, NEW.cargo_damage_cost, to_jsonb(NEW));
        RAISE EXCEPTION 'safety_incidents %: cargo_damage_cost cannot be negative (%)', NEW.incident_id, NEW.cargo_damage_cost;
    END IF;

    IF NEW.claim_amount IS NOT NULL AND NEW.claim_amount < 0 THEN
        PERFORM log_validation_violation('safety_incidents', NEW.incident_id, 'negative_claim_amount', 0, NEW.claim_amount, to_jsonb(NEW));
        RAISE EXCEPTION 'safety_incidents %: claim_amount cannot be negative (%)', NEW.incident_id, NEW.claim_amount;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_safety_incident_financials ON safety_incidents;
CREATE TRIGGER trg_validate_safety_incident_financials
BEFORE INSERT OR UPDATE ON safety_incidents
FOR EACH ROW
EXECUTE FUNCTION validate_safety_incident_financials();

-- ============================================================
-- Quick test queries (uncomment to verify behavior)
-- ============================================================
-- This should be rejected and logged:
-- INSERT INTO fuel_purchases (fuel_purchase_id, gallons, price_per_gallon, total_cost)
-- VALUES ('TEST001', 100, 3.50, 999.00);

-- Check the log:
-- SELECT * FROM financial_validation_log ORDER BY attempted_at DESC;