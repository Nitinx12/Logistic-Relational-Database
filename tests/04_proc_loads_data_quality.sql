-- ======================================================================
-- proc_loads_data_quality
--
-- Table: loads
--   load_id, customer_id, route_id, load_date, load_type, weight_lbs,
--   pieces, revenue, fuel_surcharge, accessorial_charges, load_status,
--   booking_type, updated_at
--
-- load_type and booking_type allowed-value lists below are confirmed
-- against real data:
--   load_type    -> 'DRY VAN', 'REFRIGERATED'
--   booking_type -> 'CONTRACT', 'DEDICATED', 'SPOT'
--   load_status  -> 'COMPLETED' (this table holds historical/completed loads only)
--
-- A handful of checks below are flagged WARNING (RAISE NOTICE) rather
-- than hard failures, because they rest on business-rule assumptions
-- that haven't been confirmed against your data yet (e.g. whether a
-- zero-revenue completed load or a future load_date is ever valid).
-- Promote any of these to a hard FAIL (move into v_errors) once
-- you've confirmed the assumption holds.
-- ======================================================================

CREATE OR REPLACE PROCEDURE proc_loads_data_quality()
LANGUAGE plpgsql
AS $$

DECLARE
    v_errors TEXT := '';

    v_null_load_id                 BIGINT;
    v_duplicate_load_id            BIGINT;
    v_null_customer_id             BIGINT;
    v_null_route_id                BIGINT;

    v_null_load_date               BIGINT;
    v_future_load_date             BIGINT;

    v_null_load_type                BIGINT;
    v_invalid_load_type             BIGINT;

    v_negative_weight               BIGINT;
    v_zero_weight                   BIGINT;
    v_excessive_weight              BIGINT;

    v_negative_pieces               BIGINT;
    v_zero_pieces                   BIGINT;

    v_negative_revenue              BIGINT;
    v_zero_revenue_completed        BIGINT;

    v_negative_fuel_surcharge       BIGINT;
    v_negative_accessorial_charges  BIGINT;

    v_null_load_status              BIGINT;
    v_invalid_load_status           BIGINT;

    v_null_booking_type             BIGINT;
    v_invalid_booking_type          BIGINT;

    v_null_updated_at               BIGINT;
    v_future_updated_at             BIGINT;

BEGIN

    -- ===========================================================
    -- Null / empty load_id
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_load_id
    FROM loads
    WHERE load_id IS NULL OR TRIM(load_id) = '';

    IF v_null_load_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Load ID: %s record(s)', v_null_load_id);
    END IF;

    -- ===========================================================
    -- Duplicate load_id
    -- ===========================================================
    SELECT COUNT(*) INTO v_duplicate_load_id
    FROM (
        SELECT load_id
        FROM loads
        WHERE load_id IS NOT NULL
        GROUP BY load_id
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_load_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Load IDs: %s duplicate value(s)', v_duplicate_load_id);
    END IF;

    -- ===========================================================
    -- Null / empty customer_id, route_id
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_customer_id
    FROM loads
    WHERE customer_id IS NULL OR TRIM(customer_id) = '';

    IF v_null_customer_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Customer ID: %s record(s)', v_null_customer_id);
    END IF;

    SELECT COUNT(*) INTO v_null_route_id
    FROM loads
    WHERE route_id IS NULL OR TRIM(route_id) = '';

    IF v_null_route_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Route ID: %s record(s)', v_null_route_id);
    END IF;

    -- ===========================================================
    -- load_date
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_load_date
    FROM loads
    WHERE load_date IS NULL;

    IF v_null_load_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Load Date: %s record(s)', v_null_load_date);
    END IF;

    -- WARNING: assumes a future load_date is unexpected; confirm before promoting to FAIL
    SELECT COUNT(*) INTO v_future_load_date
    FROM loads
    WHERE load_date > CURRENT_DATE;

    IF v_future_load_date > 0 THEN
        RAISE NOTICE '[WARN] Future Load Date: % record(s)', v_future_load_date;
    END IF;

    -- ===========================================================
    -- load_type
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_load_type
    FROM loads
    WHERE load_type IS NULL OR TRIM(load_type) = '';

    IF v_null_load_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Load Type: %s record(s)', v_null_load_type);
    END IF;

    SELECT COUNT(*) INTO v_invalid_load_type
    FROM loads
    WHERE load_type IS NOT NULL
      AND TRIM(load_type) <> ''
      AND UPPER(TRIM(load_type)) NOT IN ('DRY VAN', 'REFRIGERATED');

    IF v_invalid_load_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Load Type Value: %s record(s)', v_invalid_load_type);
    END IF;

    -- ===========================================================
    -- weight_lbs
    -- ===========================================================
    SELECT COUNT(*) INTO v_negative_weight
    FROM loads
    WHERE weight_lbs < 0;

    IF v_negative_weight > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Weight (lbs): %s record(s)', v_negative_weight);
    END IF;

    -- WARNING: assumes zero weight is invalid for a load; confirm before promoting to FAIL
    SELECT COUNT(*) INTO v_zero_weight
    FROM loads
    WHERE weight_lbs = 0;

    IF v_zero_weight > 0 THEN
        RAISE NOTICE '[WARN] Zero Weight (lbs): % record(s)', v_zero_weight;
    END IF;

    -- WARNING: assumes 80,000 lbs (typical US gross vehicle weight limit) as a sanity ceiling
    SELECT COUNT(*) INTO v_excessive_weight
    FROM loads
    WHERE weight_lbs > 80000;

    IF v_excessive_weight > 0 THEN
        RAISE NOTICE '[WARN] Excessive Weight (over 80,000 lbs): % record(s)', v_excessive_weight;
    END IF;

    -- ===========================================================
    -- pieces
    -- ===========================================================
    SELECT COUNT(*) INTO v_negative_pieces
    FROM loads
    WHERE pieces < 0;

    IF v_negative_pieces > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Pieces: %s record(s)', v_negative_pieces);
    END IF;

    -- WARNING: assumes zero pieces is invalid for a load; confirm before promoting to FAIL
    SELECT COUNT(*) INTO v_zero_pieces
    FROM loads
    WHERE pieces = 0;

    IF v_zero_pieces > 0 THEN
        RAISE NOTICE '[WARN] Zero Pieces: % record(s)', v_zero_pieces;
    END IF;

    -- ===========================================================
    -- revenue
    -- ===========================================================
    SELECT COUNT(*) INTO v_negative_revenue
    FROM loads
    WHERE revenue < 0;

    IF v_negative_revenue > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Revenue: %s record(s)', v_negative_revenue);
    END IF;

    -- WARNING: assumes a Completed load should have nonzero revenue; confirm before promoting to FAIL
    SELECT COUNT(*) INTO v_zero_revenue_completed
    FROM loads
    WHERE revenue = 0
      AND UPPER(TRIM(load_status)) = 'COMPLETED';

    IF v_zero_revenue_completed > 0 THEN
        RAISE NOTICE '[WARN] Zero Revenue on Completed Load: % record(s)', v_zero_revenue_completed;
    END IF;

    -- ===========================================================
    -- fuel_surcharge / accessorial_charges
    -- ===========================================================
    SELECT COUNT(*) INTO v_negative_fuel_surcharge
    FROM loads
    WHERE fuel_surcharge < 0;

    IF v_negative_fuel_surcharge > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Fuel Surcharge: %s record(s)', v_negative_fuel_surcharge);
    END IF;

    SELECT COUNT(*) INTO v_negative_accessorial_charges
    FROM loads
    WHERE accessorial_charges < 0;

    IF v_negative_accessorial_charges > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Accessorial Charges: %s record(s)', v_negative_accessorial_charges);
    END IF;

    -- ===========================================================
    -- load_status (locked to 'Completed' -- this is a historical/completed-loads table)
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_load_status
    FROM loads
    WHERE load_status IS NULL OR TRIM(load_status) = '';

    IF v_null_load_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Load Status: %s record(s)', v_null_load_status);
    END IF;

    SELECT COUNT(*) INTO v_invalid_load_status
    FROM loads
    WHERE load_status IS NOT NULL
      AND TRIM(load_status) <> ''
      AND UPPER(TRIM(load_status)) NOT IN ('COMPLETED');

    IF v_invalid_load_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Load Status Value (expected Completed): %s record(s)', v_invalid_load_status);
    END IF;

    -- ===========================================================
    -- booking_type
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_booking_type
    FROM loads
    WHERE booking_type IS NULL OR TRIM(booking_type) = '';

    IF v_null_booking_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Booking Type: %s record(s)', v_null_booking_type);
    END IF;

    SELECT COUNT(*) INTO v_invalid_booking_type
    FROM loads
    WHERE booking_type IS NOT NULL
      AND TRIM(booking_type) <> ''
      AND UPPER(TRIM(booking_type)) NOT IN ('CONTRACT', 'DEDICATED', 'SPOT');

    IF v_invalid_booking_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Booking Type Value: %s record(s)', v_invalid_booking_type);
    END IF;

    -- ===========================================================
    -- updated_at
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_updated_at
    FROM loads
    WHERE updated_at IS NULL;

    IF v_null_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Updated At Timestamp: %s record(s)', v_null_updated_at);
    END IF;

    SELECT COUNT(*) INTO v_future_updated_at
    FROM loads
    WHERE updated_at > CURRENT_TIMESTAMP;

    IF v_future_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Updated At Timestamp: %s record(s)', v_future_updated_at);
    END IF;

    ------------------------------------------------------------------
    -- Final Result
    ------------------------------------------------------------------
    IF v_errors <> '' THEN
        RAISE EXCEPTION
        E'LOADS DATA QUALITY VALIDATION FAILED\n%',
        v_errors;
    END IF;

    RAISE NOTICE 'LOADS DATA QUALITY VALIDATION PASSED';

END;
$$;