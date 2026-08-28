CREATE OR REPLACE PROCEDURE proc_trip_data_quality()
LANGUAGE plpgsql
AS $$

DECLARE
    v_errors                       TEXT := '';
    v_warnings                     TEXT := '';

    v_null_trip_id                 BIGINT;
    v_duplicate_trip_id            BIGINT;

    v_null_load_id                 BIGINT;
    v_orphan_load_id               BIGINT;

    v_null_driver_id               BIGINT;
    v_orphan_driver_id             BIGINT;

    v_null_truck_id                BIGINT;
    v_orphan_truck_id              BIGINT;

    v_null_trailer_id              BIGINT;
    v_orphan_trailer_id            BIGINT;

    v_null_dispatch_date           BIGINT;
    v_future_dispatch_date         BIGINT;

    v_null_trip_status             BIGINT;
    v_invalid_trip_status          BIGINT;
    v_completed_missing_metrics    BIGINT;
    v_noncompleted_with_metrics    BIGINT;

    v_negative_distance            BIGINT;
    v_negative_duration            BIGINT;
    v_negative_fuel_gallons        BIGINT;
    v_negative_idle_hours          BIGINT;
    v_negative_avg_mpg             BIGINT;

    v_idle_exceeds_duration        BIGINT;

    v_zero_fuel_with_distance      BIGINT;
    v_mpg_mismatch                 BIGINT;
    v_excessive_avg_mpg            BIGINT;
    v_excessive_duration_hours     BIGINT;

    v_null_updated_at              BIGINT;
    v_future_updated_at            BIGINT;

BEGIN

    -- ===========================================================
    -- Null / empty trip_id
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_trip_id
    FROM trips
    WHERE trip_id IS NULL
       OR TRIM(trip_id) = '';

    IF v_null_trip_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Null/Empty Trip ID: %s record(s)', v_null_trip_id);
    END IF;

    -- ===========================================================
    -- Duplicate trip_id
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_duplicate_trip_id
    FROM (
        SELECT trip_id
        FROM trips
        WHERE trip_id IS NOT NULL
        GROUP BY trip_id
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_trip_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Trip IDs: %s duplicate value(s)', v_duplicate_trip_id);
    END IF;

    -- ===========================================================
    -- load_id: required + must reference a real load
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_load_id
    FROM trips
    WHERE load_id IS NULL OR TRIM(load_id) = '';

    IF v_null_load_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Load ID: %s record(s)', v_null_load_id);
    END IF;

    SELECT COUNT(*)
    INTO v_orphan_load_id
    FROM trips t
    WHERE t.load_id IS NOT NULL
      AND TRIM(t.load_id) <> ''
      AND NOT EXISTS (SELECT 1 FROM loads l WHERE l.load_id = t.load_id);

    IF v_orphan_load_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Orphan Load ID (no matching record in loads): %s record(s)', v_orphan_load_id);
    END IF;

    -- ===========================================================
    -- driver_id: required + must reference a real driver
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_driver_id
    FROM trips
    WHERE driver_id IS NULL OR TRIM(driver_id) = '';

    IF v_null_driver_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Driver ID: %s record(s)', v_null_driver_id);
    END IF;

    SELECT COUNT(*)
    INTO v_orphan_driver_id
    FROM trips t
    WHERE t.driver_id IS NOT NULL
      AND TRIM(t.driver_id) <> ''
      AND NOT EXISTS (SELECT 1 FROM drivers d WHERE d.driver_id = t.driver_id);

    IF v_orphan_driver_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Orphan Driver ID (no matching record in drivers): %s record(s)', v_orphan_driver_id);
    END IF;

    -- ===========================================================
    -- truck_id: required + must reference a real truck
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_truck_id
    FROM trips
    WHERE truck_id IS NULL OR TRIM(truck_id) = '';

    IF v_null_truck_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Truck ID: %s record(s)', v_null_truck_id);
    END IF;

    SELECT COUNT(*)
    INTO v_orphan_truck_id
    FROM trips t
    WHERE t.truck_id IS NOT NULL
      AND TRIM(t.truck_id) <> ''
      AND NOT EXISTS (SELECT 1 FROM trucks tr WHERE tr.truck_id = t.truck_id);

    IF v_orphan_truck_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Orphan Truck ID (no matching record in trucks): %s record(s)', v_orphan_truck_id);
    END IF;

    -- ===========================================================
    -- trailer_id: NOT assumed required (bobtail/no-trailer runs may be
    -- legitimate) -- missing is a warning. But a non-null value that
    -- doesn't match a real trailer is still corrupt data -- hard fail.
    -- If trailers are always required for your operation, move the
    -- null check up into v_errors.
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_trailer_id
    FROM trips
    WHERE trailer_id IS NULL OR TRIM(trailer_id) = '';

    IF v_null_trailer_id > 0 THEN
        v_warnings := v_warnings ||
        format(E'\n[WARN] Missing Trailer ID: %s record(s)', v_null_trailer_id);
    END IF;

    SELECT COUNT(*)
    INTO v_orphan_trailer_id
    FROM trips t
    WHERE t.trailer_id IS NOT NULL
      AND TRIM(t.trailer_id) <> ''
      AND NOT EXISTS (SELECT 1 FROM trailers tl WHERE tl.trailer_id = t.trailer_id);

    IF v_orphan_trailer_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Orphan Trailer ID (no matching record in trailers): %s record(s)', v_orphan_trailer_id);
    END IF;

    -- ===========================================================
    -- dispatch_date
    -- Assumes this table holds trips that have actually been dispatched
    -- (it stores actual_* outcome columns), so a future dispatch_date is
    -- treated as a hard error. If this table also holds not-yet-run
    -- scheduled trips, relax this to warn or condition it on trip_status.
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_dispatch_date
    FROM trips
    WHERE dispatch_date IS NULL;

    IF v_null_dispatch_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Dispatch Date: %s record(s)', v_null_dispatch_date);
    END IF;

    SELECT COUNT(*)
    INTO v_future_dispatch_date
    FROM trips
    WHERE dispatch_date > CURRENT_DATE;

    IF v_future_dispatch_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Dispatch Date: %s record(s)', v_future_dispatch_date);
    END IF;

    -- ===========================================================
    -- trip_status
    -- Adjust this allowed-value list to match your actual status values.
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_trip_status
    FROM trips
    WHERE trip_status IS NULL OR TRIM(trip_status) = '';

    IF v_null_trip_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Trip Status: %s record(s)', v_null_trip_status);
    END IF;

    SELECT COUNT(*)
    INTO v_invalid_trip_status
    FROM trips
    WHERE trip_status IS NOT NULL
      AND TRIM(trip_status) <> ''
      AND UPPER(TRIM(trip_status)) NOT IN ('SCHEDULED', 'DISPATCHED', 'IN TRANSIT', 'COMPLETED', 'CANCELLED', 'DELAYED');

    IF v_invalid_trip_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Trip Status Value: %s record(s)', v_invalid_trip_status);
    END IF;

    -- Status/metrics consistency: a completed trip should have its actual
    -- outcome recorded.
    SELECT COUNT(*)
    INTO v_completed_missing_metrics
    FROM trips
    WHERE UPPER(TRIM(trip_status)) = 'COMPLETED'
      AND (actual_distance_miles IS NULL OR actual_duration_hours IS NULL);

    IF v_completed_missing_metrics > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Status Completed but Missing Actual Distance/Duration: %s record(s)', v_completed_missing_metrics);
    END IF;

    -- A cancelled/scheduled trip having full actual outcomes recorded is
    -- unusual but not impossible (e.g. cancelled mid-route after partial
    -- distance was logged) -- warn rather than fail.
    SELECT COUNT(*)
    INTO v_noncompleted_with_metrics
    FROM trips
    WHERE UPPER(TRIM(trip_status)) IN ('SCHEDULED', 'CANCELLED')
      AND actual_distance_miles IS NOT NULL
      AND actual_distance_miles > 0;

    IF v_noncompleted_with_metrics > 0 THEN
        v_warnings := v_warnings ||
        format(E'\n[WARN] Scheduled/Cancelled Trip Has Actual Distance Recorded: %s record(s)', v_noncompleted_with_metrics);
    END IF;

    -- ===========================================================
    -- Negative numeric values -- structurally impossible regardless of
    -- business rules.
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_negative_distance
    FROM trips
    WHERE actual_distance_miles < 0;

    IF v_negative_distance > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Actual Distance Miles: %s record(s)', v_negative_distance);
    END IF;

    SELECT COUNT(*)
    INTO v_negative_duration
    FROM trips
    WHERE actual_duration_hours < 0;

    IF v_negative_duration > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Actual Duration Hours: %s record(s)', v_negative_duration);
    END IF;

    SELECT COUNT(*)
    INTO v_negative_fuel_gallons
    FROM trips
    WHERE fuel_gallons_used < 0;

    IF v_negative_fuel_gallons > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Fuel Gallons Used: %s record(s)', v_negative_fuel_gallons);
    END IF;

    SELECT COUNT(*)
    INTO v_negative_idle_hours
    FROM trips
    WHERE idle_time_hours < 0;

    IF v_negative_idle_hours > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Idle Time Hours: %s record(s)', v_negative_idle_hours);
    END IF;

    SELECT COUNT(*)
    INTO v_negative_avg_mpg
    FROM trips
    WHERE average_mpg < 0;

    IF v_negative_avg_mpg > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Average MPG: %s record(s)', v_negative_avg_mpg);
    END IF;

    -- ===========================================================
    -- Idle time can't exceed total trip duration -- a direct ordering
    -- violation between two fields recorded together, same category as
    -- "Termination Date Before Hire Date" on the drivers table -- hard fail.
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_idle_exceeds_duration
    FROM trips
    WHERE idle_time_hours IS NOT NULL
      AND actual_duration_hours IS NOT NULL
      AND idle_time_hours > actual_duration_hours;

    IF v_idle_exceeds_duration > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Idle Time Exceeds Total Trip Duration: %s record(s)', v_idle_exceeds_duration);
    END IF;

    -- ===========================================================
    -- average_mpg plausibility -- derived/statistical checks, warnings
    -- only. Lesson from fuel_purchases: compare computed vs. stored with
    -- a tolerance, not exact equality, since both sides are independently
    -- rounded and minor drift is expected, not corruption.
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_zero_fuel_with_distance
    FROM trips
    WHERE actual_distance_miles IS NOT NULL
      AND actual_distance_miles > 0
      AND (fuel_gallons_used IS NULL OR fuel_gallons_used = 0);

    IF v_zero_fuel_with_distance > 0 THEN
        v_warnings := v_warnings ||
        format(E'\n[WARN] Distance Recorded but Zero/Missing Fuel Gallons Used: %s record(s)', v_zero_fuel_with_distance);
    END IF;

    SELECT COUNT(*)
    INTO v_mpg_mismatch
    FROM trips
    WHERE average_mpg IS NOT NULL
      AND actual_distance_miles IS NOT NULL
      AND fuel_gallons_used IS NOT NULL
      AND fuel_gallons_used > 0
      AND ABS(average_mpg - (actual_distance_miles / fuel_gallons_used)) > GREATEST(1.0, (actual_distance_miles / fuel_gallons_used) * 0.10);

    IF v_mpg_mismatch > 0 THEN
        v_warnings := v_warnings ||
        format(E'\n[WARN] Average MPG Inconsistent with Distance/Fuel (beyond 10%% tolerance): %s record(s)', v_mpg_mismatch);
    END IF;

    -- Adjust threshold to whatever's realistic for your fleet (heavy
    -- trucks rarely exceed ~10-12 mpg even under ideal conditions).
    SELECT COUNT(*)
    INTO v_excessive_avg_mpg
    FROM trips
    WHERE average_mpg > 12;

    IF v_excessive_avg_mpg > 0 THEN
        v_warnings := v_warnings ||
        format(E'\n[WARN] Unrealistic Average MPG (over 12): %s record(s)', v_excessive_avg_mpg);
    END IF;

    -- Adjust threshold -- flags a single trip lasting over a week.
    SELECT COUNT(*)
    INTO v_excessive_duration_hours
    FROM trips
    WHERE actual_duration_hours > 168;

    IF v_excessive_duration_hours > 0 THEN
        v_warnings := v_warnings ||
        format(E'\n[WARN] Unrealistic Trip Duration (over 168 hours / 1 week): %s record(s)', v_excessive_duration_hours);
    END IF;

    -- ===========================================================
    -- updated_at
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_updated_at
    FROM trips
    WHERE updated_at IS NULL;

    IF v_null_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Updated At Timestamp: %s record(s)', v_null_updated_at);
    END IF;

    SELECT COUNT(*)
    INTO v_future_updated_at
    FROM trips
    WHERE updated_at > CURRENT_TIMESTAMP;

    IF v_future_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Updated At Timestamp: %s record(s)', v_future_updated_at);
    END IF;

    ------------------------------------------------------------------
    -- Final Result
    -- Hard failures (v_errors): structural corruption -- nulls on
    -- required fields, duplicate/orphan keys, impossible orderings,
    -- invalid enums. These abort the procedure.
    --
    -- Warnings (v_warnings): statistical/plausibility outliers on
    -- derived fields. Surfaced via RAISE WARNING, non-blocking.
    ------------------------------------------------------------------
    IF v_errors <> '' THEN
        IF v_warnings <> '' THEN
            v_errors := v_errors || E'\n\n-- Warnings (non-blocking) --' || v_warnings;
        END IF;
        RAISE EXCEPTION
        E'TRIP DATA QUALITY VALIDATION FAILED\n%',
        v_errors;
    END IF;

    IF v_warnings <> '' THEN
        RAISE WARNING
        E'TRIP DATA QUALITY VALIDATION PASSED WITH WARNINGS\n%',
        v_warnings;
    ELSE
        RAISE NOTICE 'TRIP DATA QUALITY VALIDATION PASSED';
    END IF;

END;
$$;