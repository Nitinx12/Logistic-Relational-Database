-- ======================================================================
-- proc_routes_data_quality
--
-- Table: routes
--   route_id, origin_city, origin_state, destination_city,
--   destination_state, typical_distance_miles, base_rate_per_mile,
--   fuel_surcharge_rate, typical_transit_days, updated_at
--
-- As with the other procedures in this set, checks that rest on a
-- clear universal rule (nulls, negative numbers, malformed state
-- codes, duplicate keys, future timestamps) are hard FAILs. Checks
-- that rest on a business-rule assumption not yet confirmed against
-- your data (zero distance/rate/transit days, an origin identical to
-- the destination, unusually long distance or transit time, the same
-- origin/destination pair appearing under multiple route_ids) are
-- RAISE NOTICE warnings instead, so a first run won't false-fail on
-- something that turns out to be normal for your network. Promote
-- any of these into v_errors once you've confirmed the assumption.
-- ======================================================================

CREATE OR REPLACE PROCEDURE proc_routes_data_quality()
LANGUAGE plpgsql
AS $$

DECLARE
    v_errors TEXT := '';

    v_null_route_id                 BIGINT;
    v_duplicate_route_id            BIGINT;

    v_null_origin_city              BIGINT;
    v_null_origin_state             BIGINT;
    v_invalid_origin_state          BIGINT;

    v_null_destination_city         BIGINT;
    v_null_destination_state        BIGINT;
    v_invalid_destination_state     BIGINT;

    v_origin_equals_destination     BIGINT;
    v_duplicate_lane                BIGINT;

    v_null_distance                 BIGINT;
    v_negative_distance             BIGINT;
    v_zero_distance                 BIGINT;
    v_excessive_distance            BIGINT;

    v_null_base_rate                BIGINT;
    v_negative_base_rate            BIGINT;
    v_zero_base_rate                BIGINT;

    v_null_fuel_surcharge_rate      BIGINT;
    v_negative_fuel_surcharge_rate  BIGINT;

    v_null_transit_days             BIGINT;
    v_negative_transit_days         BIGINT;
    v_zero_transit_days             BIGINT;
    v_excessive_transit_days        BIGINT;

    v_null_updated_at               BIGINT;
    v_future_updated_at             BIGINT;

BEGIN

    -- ===========================================================
    -- Null / empty route_id
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_route_id
    FROM routes
    WHERE route_id IS NULL OR TRIM(route_id) = '';

    IF v_null_route_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Route ID: %s record(s)', v_null_route_id);
    END IF;

    -- ===========================================================
    -- Duplicate route_id
    -- ===========================================================
    SELECT COUNT(*) INTO v_duplicate_route_id
    FROM (
        SELECT route_id
        FROM routes
        WHERE route_id IS NOT NULL
        GROUP BY route_id
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_route_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Route IDs: %s duplicate value(s)', v_duplicate_route_id);
    END IF;

    -- ===========================================================
    -- origin_city / origin_state
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_origin_city
    FROM routes
    WHERE origin_city IS NULL OR TRIM(origin_city) = '';

    IF v_null_origin_city > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Origin City: %s record(s)', v_null_origin_city);
    END IF;

    SELECT COUNT(*) INTO v_null_origin_state
    FROM routes
    WHERE origin_state IS NULL OR TRIM(origin_state) = '';

    IF v_null_origin_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Origin State: %s record(s)', v_null_origin_state);
    END IF;

    SELECT COUNT(*) INTO v_invalid_origin_state
    FROM routes
    WHERE origin_state IS NOT NULL
      AND TRIM(origin_state) <> ''
      AND origin_state !~ '^[A-Za-z]{2}$';

    IF v_invalid_origin_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Origin State Format (expected 2-letter code): %s record(s)', v_invalid_origin_state);
    END IF;

    -- ===========================================================
    -- destination_city / destination_state
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_destination_city
    FROM routes
    WHERE destination_city IS NULL OR TRIM(destination_city) = '';

    IF v_null_destination_city > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Destination City: %s record(s)', v_null_destination_city);
    END IF;

    SELECT COUNT(*) INTO v_null_destination_state
    FROM routes
    WHERE destination_state IS NULL OR TRIM(destination_state) = '';

    IF v_null_destination_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Destination State: %s record(s)', v_null_destination_state);
    END IF;

    SELECT COUNT(*) INTO v_invalid_destination_state
    FROM routes
    WHERE destination_state IS NOT NULL
      AND TRIM(destination_state) <> ''
      AND destination_state !~ '^[A-Za-z]{2}$';

    IF v_invalid_destination_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Destination State Format (expected 2-letter code): %s record(s)', v_invalid_destination_state);
    END IF;

    -- ===========================================================
    -- Origin / destination relationship checks (WARNING -- confirm before promoting)
    -- ===========================================================
    SELECT COUNT(*) INTO v_origin_equals_destination
    FROM routes
    WHERE UPPER(TRIM(origin_city)) = UPPER(TRIM(destination_city))
      AND UPPER(TRIM(origin_state)) = UPPER(TRIM(destination_state));

    IF v_origin_equals_destination > 0 THEN
        RAISE NOTICE '[WARN] Origin Identical to Destination: % record(s)', v_origin_equals_destination;
    END IF;

    -- Same city/state pair logged under more than one route_id (could be intentional
    -- multi-lane pricing, or could be a duplicate route entry)
    SELECT COUNT(*) INTO v_duplicate_lane
    FROM (
        SELECT origin_city, origin_state, destination_city, destination_state
        FROM routes
        WHERE origin_city IS NOT NULL
          AND origin_state IS NOT NULL
          AND destination_city IS NOT NULL
          AND destination_state IS NOT NULL
        GROUP BY origin_city, origin_state, destination_city, destination_state
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_lane > 0 THEN
        RAISE NOTICE '[WARN] Same Origin/Destination Pair Appears Under Multiple Route IDs: % lane(s)', v_duplicate_lane;
    END IF;

    -- ===========================================================
    -- typical_distance_miles
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_distance
    FROM routes
    WHERE typical_distance_miles IS NULL;

    IF v_null_distance > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Typical Distance (miles): %s record(s)', v_null_distance);
    END IF;

    SELECT COUNT(*) INTO v_negative_distance
    FROM routes
    WHERE typical_distance_miles < 0;

    IF v_negative_distance > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Typical Distance (miles): %s record(s)', v_negative_distance);
    END IF;

    -- WARNING: assumes zero distance is invalid; confirm before promoting to FAIL
    SELECT COUNT(*) INTO v_zero_distance
    FROM routes
    WHERE typical_distance_miles = 0;

    IF v_zero_distance > 0 THEN
        RAISE NOTICE '[WARN] Zero Typical Distance (miles): % record(s)', v_zero_distance;
    END IF;

    -- WARNING: assumes 3,500 miles as a sanity ceiling for a single route
    SELECT COUNT(*) INTO v_excessive_distance
    FROM routes
    WHERE typical_distance_miles > 3500;

    IF v_excessive_distance > 0 THEN
        RAISE NOTICE '[WARN] Excessive Typical Distance (over 3,500 miles): % record(s)', v_excessive_distance;
    END IF;

    -- ===========================================================
    -- base_rate_per_mile
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_base_rate
    FROM routes
    WHERE base_rate_per_mile IS NULL;

    IF v_null_base_rate > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Base Rate Per Mile: %s record(s)', v_null_base_rate);
    END IF;

    SELECT COUNT(*) INTO v_negative_base_rate
    FROM routes
    WHERE base_rate_per_mile < 0;

    IF v_negative_base_rate > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Base Rate Per Mile: %s record(s)', v_negative_base_rate);
    END IF;

    -- WARNING: assumes zero rate is invalid; confirm before promoting to FAIL
    SELECT COUNT(*) INTO v_zero_base_rate
    FROM routes
    WHERE base_rate_per_mile = 0;

    IF v_zero_base_rate > 0 THEN
        RAISE NOTICE '[WARN] Zero Base Rate Per Mile: % record(s)', v_zero_base_rate;
    END IF;

    -- ===========================================================
    -- fuel_surcharge_rate
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_fuel_surcharge_rate
    FROM routes
    WHERE fuel_surcharge_rate IS NULL;

    IF v_null_fuel_surcharge_rate > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Fuel Surcharge Rate: %s record(s)', v_null_fuel_surcharge_rate);
    END IF;

    SELECT COUNT(*) INTO v_negative_fuel_surcharge_rate
    FROM routes
    WHERE fuel_surcharge_rate < 0;

    IF v_negative_fuel_surcharge_rate > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Fuel Surcharge Rate: %s record(s)', v_negative_fuel_surcharge_rate);
    END IF;

    -- ===========================================================
    -- typical_transit_days
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_transit_days
    FROM routes
    WHERE typical_transit_days IS NULL;

    IF v_null_transit_days > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Typical Transit Days: %s record(s)', v_null_transit_days);
    END IF;

    SELECT COUNT(*) INTO v_negative_transit_days
    FROM routes
    WHERE typical_transit_days < 0;

    IF v_negative_transit_days > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Typical Transit Days: %s record(s)', v_negative_transit_days);
    END IF;

    -- WARNING: assumes zero transit days is invalid (i.e. not a same-day-only lane); confirm before promoting
    SELECT COUNT(*) INTO v_zero_transit_days
    FROM routes
    WHERE typical_transit_days = 0;

    IF v_zero_transit_days > 0 THEN
        RAISE NOTICE '[WARN] Zero Typical Transit Days: % record(s)', v_zero_transit_days;
    END IF;

    -- WARNING: assumes 14 days as a sanity ceiling for typical transit time
    SELECT COUNT(*) INTO v_excessive_transit_days
    FROM routes
    WHERE typical_transit_days > 14;

    IF v_excessive_transit_days > 0 THEN
        RAISE NOTICE '[WARN] Excessive Typical Transit Days (over 14): % record(s)', v_excessive_transit_days;
    END IF;

    -- ===========================================================
    -- updated_at
    -- ===========================================================
    SELECT COUNT(*) INTO v_null_updated_at
    FROM routes
    WHERE updated_at IS NULL;

    IF v_null_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Updated At Timestamp: %s record(s)', v_null_updated_at);
    END IF;

    SELECT COUNT(*) INTO v_future_updated_at
    FROM routes
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
        E'ROUTES DATA QUALITY VALIDATION FAILED\n%',
        v_errors;
    END IF;

    RAISE NOTICE 'ROUTES DATA QUALITY VALIDATION PASSED';

END;
$$;