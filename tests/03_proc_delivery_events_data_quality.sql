-- ======================================================================
-- proc_delivery_events_data_quality
--
-- Table: delivery_events
--   event_id, load_id, trip_id, event_type, facility_id,
--   scheduled_datetime, actual_datetime, detention_minutes,
--   on_time_flag, location_city, location_state, updated_at
--
-- A few thresholds/allowed-value lists below encode business-rule
-- assumptions (allowed event_type values, allowed on_time_flag values,
-- the on-time grace period, the detention_minutes cap). Adjust the
-- constants/lists in those sections to match your real rules.
-- ======================================================================

CREATE OR REPLACE PROCEDURE proc_delivery_events_data_quality()
LANGUAGE plpgsql
AS $$

DECLARE
    v_errors TEXT := '';

    v_null_event_id                BIGINT;
    v_duplicate_event_id           BIGINT;
    v_null_load_id                 BIGINT;
    v_null_trip_id                 BIGINT;

    v_null_event_type              BIGINT;
    v_invalid_event_type           BIGINT;

    v_null_facility_id             BIGINT;

    v_null_scheduled_datetime      BIGINT;
    v_null_actual_datetime_pastdue BIGINT;
    v_future_actual_datetime       BIGINT;
    v_actual_far_before_scheduled  BIGINT;

    v_negative_detention           BIGINT;
    v_excessive_detention          BIGINT;
    v_detention_no_actual_time     BIGINT;

    v_null_on_time_flag            BIGINT;
    v_invalid_on_time_flag         BIGINT;
    v_on_time_flag_mismatch        BIGINT;

    v_null_location_city           BIGINT;
    v_null_location_state          BIGINT;
    v_invalid_location_state       BIGINT;

    v_null_updated_at              BIGINT;
    v_future_updated_at            BIGINT;

    v_duplicate_event_signature    BIGINT;

BEGIN

    -- ===========================================================
    -- Null / empty event_id
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_event_id
    FROM delivery_events
    WHERE event_id IS NULL OR TRIM(event_id) = '';

    IF v_null_event_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Event ID: %s record(s)', v_null_event_id);
    END IF;

    -- ===========================================================
    -- Duplicate event_id
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_duplicate_event_id
    FROM (
        SELECT event_id
        FROM delivery_events
        WHERE event_id IS NOT NULL
        GROUP BY event_id
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_event_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Event IDs: %s duplicate value(s)', v_duplicate_event_id);
    END IF;

    -- ===========================================================
    -- Null / empty load_id, trip_id
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_load_id
    FROM delivery_events
    WHERE load_id IS NULL OR TRIM(load_id) = '';

    IF v_null_load_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Load ID: %s record(s)', v_null_load_id);
    END IF;

    SELECT COUNT(*) 
    INTO v_null_trip_id
    FROM delivery_events
    WHERE trip_id IS NULL OR TRIM(trip_id) = '';

    IF v_null_trip_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Trip ID: %s record(s)', v_null_trip_id);
    END IF;

    -- ===========================================================
    -- event_type
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_event_type
    FROM delivery_events
    WHERE event_type IS NULL OR TRIM(event_type) = '';

    IF v_null_event_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Event Type: %s record(s)', v_null_event_type);
    END IF;

    -- Adjust this allowed-value list to match your actual event types
    SELECT COUNT(*) 
    INTO v_invalid_event_type
    FROM delivery_events
    WHERE event_type IS NOT NULL
      AND TRIM(event_type) <> ''
      AND UPPER(TRIM(event_type)) NOT IN ('PICKUP', 'DELIVERY', 'STOP', 'ARRIVAL', 'DEPARTURE');

    IF v_invalid_event_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Event Type Value: %s record(s)', v_invalid_event_type);
    END IF;

    -- ===========================================================
    -- facility_id
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_facility_id
    FROM delivery_events
    WHERE facility_id IS NULL OR TRIM(facility_id) = '';

    IF v_null_facility_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Facility ID: %s record(s)', v_null_facility_id);
    END IF;

    -- ===========================================================
    -- scheduled_datetime / actual_datetime
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_scheduled_datetime
    FROM delivery_events
    WHERE scheduled_datetime IS NULL;

    IF v_null_scheduled_datetime > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Scheduled Datetime: %s record(s)', v_null_scheduled_datetime);
    END IF;

    -- Events scheduled in the past should have an actual_datetime recorded by now
    SELECT COUNT(*) 
    INTO v_null_actual_datetime_pastdue
    FROM delivery_events
    WHERE actual_datetime IS NULL
      AND scheduled_datetime IS NOT NULL
      AND scheduled_datetime < CURRENT_TIMESTAMP;

    IF v_null_actual_datetime_pastdue > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Past-Due Event Missing Actual Datetime: %s record(s)', v_null_actual_datetime_pastdue);
    END IF;

    -- An event can't have actually happened in the future
    SELECT COUNT(*) 
    INTO v_future_actual_datetime
    FROM delivery_events
    WHERE actual_datetime > CURRENT_TIMESTAMP;

    IF v_future_actual_datetime > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Actual Datetime: %s record(s)', v_future_actual_datetime);
    END IF;

    -- Flag actual_datetime more than 7 days earlier than scheduled_datetime
    -- (likely data entry error rather than a genuinely early arrival)
    SELECT COUNT(*) 
    INTO v_actual_far_before_scheduled
    FROM delivery_events
    WHERE actual_datetime IS NOT NULL
      AND scheduled_datetime IS NOT NULL
      AND actual_datetime < scheduled_datetime - INTERVAL '7 days';

    IF v_actual_far_before_scheduled > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Actual Datetime More Than 7 Days Before Scheduled Datetime: %s record(s)', v_actual_far_before_scheduled);
    END IF;

    -- ===========================================================
    -- detention_minutes
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_negative_detention
    FROM delivery_events
    WHERE detention_minutes < 0;

    IF v_negative_detention > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Detention Minutes: %s record(s)', v_negative_detention);
    END IF;

    -- Flag detention over 48 hours (2880 minutes) as suspicious
    SELECT COUNT(*) 
    INTO v_excessive_detention
    FROM delivery_events
    WHERE detention_minutes > 2880;

    IF v_excessive_detention > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Excessive Detention Minutes (over 48 hours): %s record(s)', v_excessive_detention);
    END IF;

    -- detention_minutes recorded but no actual_datetime to measure it from
    SELECT COUNT(*) 
    INTO v_detention_no_actual_time
    FROM delivery_events
    WHERE detention_minutes IS NOT NULL
      AND detention_minutes > 0
      AND actual_datetime IS NULL;

    IF v_detention_no_actual_time > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Detention Minutes Recorded Without an Actual Datetime: %s record(s)', v_detention_no_actual_time);
    END IF;

    -- ===========================================================
    -- on_time_flag
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_on_time_flag
    FROM delivery_events
    WHERE on_time_flag IS NULL OR TRIM(on_time_flag) = '';

    IF v_null_on_time_flag > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing On-Time Flag: %s record(s)', v_null_on_time_flag);
    END IF;

    -- Adjust this allowed-value list to match your actual flag values
    SELECT COUNT(*) 
    INTO v_invalid_on_time_flag
    FROM delivery_events
    WHERE on_time_flag IS NOT NULL
      AND TRIM(on_time_flag) <> ''
      AND UPPER(TRIM(on_time_flag)) NOT IN ('TRUE', 'FALSE');

    IF v_invalid_on_time_flag > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid On-Time Flag Value: %s record(s)', v_invalid_on_time_flag);
    END IF;

    -- Cross-check stored flag against actual vs. scheduled time.
    -- Business rule (derived from observed data): "on time" means actual_datetime
    -- falls within +/- 120 minutes of scheduled_datetime, in either direction.
    SELECT COUNT(*) 
    INTO v_on_time_flag_mismatch
    FROM delivery_events
    WHERE scheduled_datetime IS NOT NULL
      AND actual_datetime IS NOT NULL
      AND on_time_flag IS NOT NULL
      AND (
            (
                UPPER(TRIM(on_time_flag)) = 'TRUE'
                AND (
                        actual_datetime < scheduled_datetime - INTERVAL '120 minutes'
                     OR actual_datetime > scheduled_datetime + INTERVAL '120 minutes'
                    )
            )
         OR (
                UPPER(TRIM(on_time_flag)) = 'FALSE'
                AND actual_datetime BETWEEN scheduled_datetime - INTERVAL '120 minutes'
                                         AND scheduled_datetime + INTERVAL '120 minutes'
            )
          );

    IF v_on_time_flag_mismatch > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] On-Time Flag Inconsistent With Scheduled/Actual Datetime: %s record(s)', v_on_time_flag_mismatch);
    END IF;

    -- ===========================================================
    -- location_city / location_state
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_location_city
    FROM delivery_events
    WHERE location_city IS NULL OR TRIM(location_city) = '';

    IF v_null_location_city > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Location City: %s record(s)', v_null_location_city);
    END IF;

    SELECT COUNT(*) 
    INTO v_null_location_state
    FROM delivery_events
    WHERE location_state IS NULL OR TRIM(location_state) = '';

    IF v_null_location_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Location State: %s record(s)', v_null_location_state);
    END IF;

    -- Must be a 2-letter state/province code
    SELECT COUNT(*) 
    INTO v_invalid_location_state
    FROM delivery_events
    WHERE location_state IS NOT NULL
      AND TRIM(location_state) <> ''
      AND location_state !~ '^[A-Za-z]{2}$';

    IF v_invalid_location_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Location State Format (expected 2-letter code): %s record(s)', v_invalid_location_state);
    END IF;

    -- ===========================================================
    -- updated_at
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_updated_at
    FROM delivery_events
    WHERE updated_at IS NULL;

    IF v_null_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Updated At Timestamp: %s record(s)', v_null_updated_at);
    END IF;

    SELECT COUNT(*) 
    INTO v_future_updated_at
    FROM delivery_events
    WHERE updated_at > CURRENT_TIMESTAMP;

    IF v_future_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Updated At Timestamp: %s record(s)', v_future_updated_at);
    END IF;

    -- ===========================================================
    -- Duplicate event signature (same load, type, and scheduled time
    -- logged more than once under different event_id values)
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_duplicate_event_signature
    FROM (
        SELECT load_id, event_type, scheduled_datetime
        FROM delivery_events
        WHERE load_id IS NOT NULL
          AND event_type IS NOT NULL
          AND scheduled_datetime IS NOT NULL
        GROUP BY load_id, event_type, scheduled_datetime
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_event_signature > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Event (Same Load + Type + Scheduled Time): %s duplicate value(s)', v_duplicate_event_signature);
    END IF;

    ------------------------------------------------------------------
    -- Final Result
    ------------------------------------------------------------------
    IF v_errors <> '' THEN
        RAISE EXCEPTION
        E'DELIVERY EVENTS DATA QUALITY VALIDATION FAILED\n%',
        v_errors;
    END IF;

    RAISE NOTICE 'DELIVERY EVENTS DATA QUALITY VALIDATION PASSED';

END;
$$;