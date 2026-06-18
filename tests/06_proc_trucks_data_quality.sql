-- ======================================================================
-- proc_trucks_data_quality
--
-- Table: trucks
--   truck_id, unit_number, make, model_year, vin, acquisition_date,
--   acquisition_mileage, fuel_type, tank_capacity_gallons, status,
--   home_terminal, updated_at
--
-- status is enum-locked to the 3 confirmed values: Active, Inactive,
-- Maintenance.
--
-- fuel_type is enum-locked to 'Diesel', the only value currently
-- present (120/120 rows). If the fleet later adds other fuel types
-- (CNG, electric, hybrid), this list will need to be expanded.
--
-- make and home_terminal are left as free-text (null check only).
--
-- As with the other procedures: clear universal rules (nulls,
-- negatives, malformed VIN/format, duplicate keys, future dates) are
-- hard FAILs. Business-rule-assumption checks (zero/low/high tank
-- capacity, model_year edge cases, acquisition_date vs model_year)
-- are RAISE NOTICE warnings -- promote to v_errors once confirmed.
-- ======================================================================

CREATE OR REPLACE PROCEDURE proc_trucks_data_quality()
LANGUAGE plpgsql
AS $$

DECLARE
    v_errors TEXT := '';

    v_null_truck_id                 BIGINT;
    v_duplicate_truck_id            BIGINT;

    v_null_unit_number              BIGINT;
    v_negative_unit_number          BIGINT;
    v_duplicate_unit_number         BIGINT;

    v_null_make                     BIGINT;

    v_null_model_year               BIGINT;
    v_model_year_too_old            BIGINT;
    v_model_year_too_new            BIGINT;

    v_null_vin                      BIGINT;
    v_invalid_vin_format            BIGINT;
    v_duplicate_vin                 BIGINT;

    v_null_acquisition_date         BIGINT;
    v_future_acquisition_date       BIGINT;
    v_acquisition_before_model_year BIGINT;

    v_negative_acquisition_mileage  BIGINT;

    v_null_fuel_type                BIGINT;
    v_invalid_fuel_type             BIGINT;

    v_null_tank_capacity            BIGINT;
    v_negative_tank_capacity        BIGINT;
    v_zero_tank_capacity            BIGINT;
    v_excessive_tank_capacity       BIGINT;

    v_null_status                   BIGINT;
    v_invalid_status                BIGINT;

    v_null_home_terminal            BIGINT;

    v_null_updated_at               BIGINT;
    v_future_updated_at             BIGINT;

BEGIN

    -- ===========================================================
    -- Null / empty truck_id
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_truck_id
    FROM trucks
    WHERE truck_id IS NULL OR TRIM(truck_id) = '';

    IF v_null_truck_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Truck ID: %s record(s)', v_null_truck_id);
    END IF;

    -- ===========================================================
    -- Duplicate truck_id
    -- ===========================================================
    SELECT COUNT(*) INTO v_duplicate_truck_id
    FROM (
        SELECT truck_id
        FROM trucks
        WHERE truck_id IS NOT NULL
        GROUP BY truck_id
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_truck_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Truck IDs: %s duplicate value(s)', v_duplicate_truck_id);
    END IF;

    -- ===========================================================
    -- unit_number
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_unit_number
    FROM trucks
    WHERE unit_number IS NULL;

    IF v_null_unit_number > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Unit Number: %s record(s)', v_null_unit_number);
    END IF;

    SELECT COUNT(*) INTO v_negative_unit_number
    FROM trucks
    WHERE unit_number < 0;

    IF v_negative_unit_number > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Unit Number: %s record(s)', v_negative_unit_number);
    END IF;

    SELECT COUNT(*) INTO v_duplicate_unit_number
    FROM (
        SELECT unit_number
        FROM trucks
        WHERE unit_number IS NOT NULL
        GROUP BY unit_number
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_unit_number > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Unit Numbers: %s duplicate value(s)', v_duplicate_unit_number);
    END IF;

    -- ===========================================================
    -- make
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_make
    FROM trucks
    WHERE make IS NULL OR TRIM(make) = '';

    IF v_null_make > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Make: %s record(s)', v_null_make);
    END IF;

    -- ===========================================================
    -- model_year
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_model_year
    FROM trucks
    WHERE model_year IS NULL;

    IF v_null_model_year > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Model Year: %s record(s)', v_null_model_year);
    END IF;

    SELECT COUNT(*) INTO v_model_year_too_old
    FROM trucks
    WHERE model_year IS NOT NULL
      AND model_year < 1980;

    IF v_model_year_too_old > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Model Year Before 1980: %s record(s)', v_model_year_too_old);
    END IF;

    -- Manufacturers release next year's models early, so allow up to 1 year ahead
    SELECT COUNT(*) INTO v_model_year_too_new
    FROM trucks
    WHERE model_year IS NOT NULL
      AND model_year > EXTRACT(YEAR FROM CURRENT_DATE) + 1;

    IF v_model_year_too_new > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Model Year More Than 1 Year Ahead of Current Year: %s record(s)', v_model_year_too_new);
    END IF;

    -- ===========================================================
    -- vin
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_vin
    FROM trucks
    WHERE vin IS NULL OR TRIM(vin) = '';

    IF v_null_vin > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing VIN: %s record(s)', v_null_vin);
    END IF;

    -- VIN format in this dataset: 18 characters, alphanumeric, excluding I, O, Q
    SELECT COUNT(*) INTO v_invalid_vin_format
    FROM trucks
    WHERE vin IS NOT NULL
      AND TRIM(vin) <> ''
      AND vin !~ '^[A-HJ-NPR-Z0-9]{18}$';

    IF v_invalid_vin_format > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid VIN Format (expected 18 alphanumeric chars, no I/O/Q): %s record(s)', v_invalid_vin_format);
    END IF;

    SELECT COUNT(*) INTO v_duplicate_vin
    FROM (
        SELECT vin
        FROM trucks
        WHERE vin IS NOT NULL
        GROUP BY vin
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_vin > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate VINs: %s duplicate value(s)', v_duplicate_vin);
    END IF;

    -- ===========================================================
    -- acquisition_date
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_acquisition_date
    FROM trucks
    WHERE acquisition_date IS NULL;

    IF v_null_acquisition_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Acquisition Date: %s record(s)', v_null_acquisition_date);
    END IF;

    SELECT COUNT(*) INTO v_future_acquisition_date
    FROM trucks
    WHERE acquisition_date > CURRENT_DATE;

    IF v_future_acquisition_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Acquisition Date: %s record(s)', v_future_acquisition_date);
    END IF;

    -- WARNING: assumes a truck can't be acquired before its model year began;
    -- confirm before promoting, since dealers sometimes acquire next year's
    -- model in the fall of the prior calendar year
    SELECT COUNT(*) INTO v_acquisition_before_model_year
    FROM trucks
    WHERE acquisition_date IS NOT NULL
      AND model_year IS NOT NULL
      AND EXTRACT(YEAR FROM acquisition_date) < model_year - 1;

    IF v_acquisition_before_model_year > 0 THEN
        RAISE NOTICE '[WARN] Acquisition Date More Than 1 Year Before Model Year: % record(s)', v_acquisition_before_model_year;
    END IF;

    -- ===========================================================
    -- acquisition_mileage
    -- ===========================================================
    SELECT COUNT(*) INTO v_negative_acquisition_mileage
    FROM trucks
    WHERE acquisition_mileage < 0;

    IF v_negative_acquisition_mileage > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Acquisition Mileage: %s record(s)', v_negative_acquisition_mileage);
    END IF;

    -- ===========================================================
    -- fuel_type (locked to 'Diesel' -- 100% of current fleet)
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_fuel_type
    FROM trucks
    WHERE fuel_type IS NULL OR TRIM(fuel_type) = '';

    IF v_null_fuel_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Fuel Type: %s record(s)', v_null_fuel_type);
    END IF;

    SELECT COUNT(*) INTO v_invalid_fuel_type
    FROM trucks
    WHERE fuel_type IS NOT NULL
      AND TRIM(fuel_type) <> ''
      AND UPPER(TRIM(fuel_type)) NOT IN ('DIESEL');

    IF v_invalid_fuel_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Fuel Type Value (expected Diesel): %s record(s)', v_invalid_fuel_type);
    END IF;

    -- ===========================================================
    -- tank_capacity_gallons
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_tank_capacity
    FROM trucks
    WHERE tank_capacity_gallons IS NULL;

    IF v_null_tank_capacity > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Tank Capacity (gallons): %s record(s)', v_null_tank_capacity);
    END IF;

    SELECT COUNT(*) INTO v_negative_tank_capacity
    FROM trucks
    WHERE tank_capacity_gallons < 0;

    IF v_negative_tank_capacity > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Tank Capacity (gallons): %s record(s)', v_negative_tank_capacity);
    END IF;

    -- WARNING: assumes zero tank capacity is invalid; confirm before promoting to FAIL
    SELECT COUNT(*) INTO v_zero_tank_capacity
    FROM trucks
    WHERE tank_capacity_gallons = 0;

    IF v_zero_tank_capacity > 0 THEN
        RAISE NOTICE '[WARN] Zero Tank Capacity (gallons): % record(s)', v_zero_tank_capacity;
    END IF;

    -- WARNING: assumes 300 gallons as a sanity ceiling (typical dual-tank semi max)
    SELECT COUNT(*) INTO v_excessive_tank_capacity
    FROM trucks
    WHERE tank_capacity_gallons > 300;

    IF v_excessive_tank_capacity > 0 THEN
        RAISE NOTICE '[WARN] Excessive Tank Capacity (over 300 gallons): % record(s)', v_excessive_tank_capacity;
    END IF;

    -- ===========================================================
    -- status (enum-locked to confirmed values)
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_status
    FROM trucks
    WHERE status IS NULL OR TRIM(status) = '';

    IF v_null_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Status: %s record(s)', v_null_status);
    END IF;

    SELECT COUNT(*) INTO v_invalid_status
    FROM trucks
    WHERE status IS NOT NULL
      AND TRIM(status) <> ''
      AND UPPER(TRIM(status)) NOT IN ('ACTIVE', 'INACTIVE', 'MAINTENANCE');

    IF v_invalid_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Status Value: %s record(s)', v_invalid_status);
    END IF;

    -- ===========================================================
    -- home_terminal (free text -- null check only)
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_home_terminal
    FROM trucks
    WHERE home_terminal IS NULL OR TRIM(home_terminal) = '';

    IF v_null_home_terminal > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Home Terminal: %s record(s)', v_null_home_terminal);
    END IF;

    -- ===========================================================
    -- updated_at
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_updated_at
    FROM trucks
    WHERE updated_at IS NULL;

    IF v_null_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Updated At Timestamp: %s record(s)', v_null_updated_at);
    END IF;

    SELECT COUNT(*) INTO v_future_updated_at
    FROM trucks
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
        E'TRUCKS DATA QUALITY VALIDATION FAILED\n%',
        v_errors;
    END IF;

    RAISE NOTICE 'TRUCKS DATA QUALITY VALIDATION PASSED';

END;
$$;