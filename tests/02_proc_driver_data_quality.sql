
CREATE OR REPLACE PROCEDURE proc_driver_data_quality()
LANGUAGE plpgsql
AS $$

DECLARE
    v_errors TEXT := '';

    v_null_driver_id              BIGINT;
    v_duplicate_driver_id         BIGINT;
    v_null_first_name             BIGINT;
    v_null_last_name              BIGINT;

    v_null_hire_date              BIGINT;
    v_future_hire_date            BIGINT;

    v_null_dob                    BIGINT;
    v_future_dob                  BIGINT;
    v_unrealistic_dob             BIGINT;
    v_underage_at_hire            BIGINT;

    v_termination_before_hire     BIGINT;
    v_future_termination          BIGINT;
    v_terminated_missing_date     BIGINT;
    v_active_with_term_date       BIGINT;

    v_null_license_number         BIGINT;
    v_duplicate_license           BIGINT;
    v_null_license_state          BIGINT;
    v_invalid_license_state       BIGINT;

    v_null_home_terminal          BIGINT;

    v_null_employment_status      BIGINT;
    v_invalid_employment_status   BIGINT;

    v_null_cdl_class              BIGINT;
    v_invalid_cdl_class           BIGINT;

    v_negative_years_experience   BIGINT;
    v_excessive_years_experience  BIGINT;
    v_experience_exceeds_age      BIGINT;

    v_null_updated_at             BIGINT;
    v_future_updated_at           BIGINT;

BEGIN

    -- ===========================================================
    -- Null / empty driver_id
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_driver_id
    FROM drivers
    WHERE driver_id IS NULL
       OR TRIM(driver_id) = '';

    IF v_null_driver_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Null/Empty Driver ID: %s record(s)', v_null_driver_id);
    END IF;

    -- ===========================================================
    -- Duplicate driver_id
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_duplicate_driver_id
    FROM (
        SELECT driver_id
        FROM drivers
        WHERE driver_id IS NOT NULL
        GROUP BY driver_id
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_driver_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Driver IDs: %s duplicate value(s)', v_duplicate_driver_id);
    END IF;

    -- ===========================================================
    -- Null / empty first_name, last_name
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_first_name
    FROM drivers
    WHERE first_name IS NULL OR TRIM(first_name) = '';

    IF v_null_first_name > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing First Name: %s record(s)', v_null_first_name);
    END IF;

    SELECT COUNT(*) 
    INTO v_null_last_name
    FROM drivers
    WHERE last_name IS NULL OR TRIM(last_name) = '';

    IF v_null_last_name > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Last Name: %s record(s)', v_null_last_name);
    END IF;

    -- ===========================================================
    -- hire_date checks
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_hire_date
    FROM drivers
    WHERE hire_date IS NULL;

    IF v_null_hire_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Hire Date: %s record(s)', v_null_hire_date);
    END IF;

    SELECT COUNT(*) 
    INTO v_future_hire_date
    FROM drivers
    WHERE hire_date > CURRENT_DATE;

    IF v_future_hire_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Hire Date: %s record(s)', v_future_hire_date);
    END IF;

    -- ===========================================================
    -- date_of_birth checks
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_dob
    FROM drivers
    WHERE date_of_birth IS NULL;

    IF v_null_dob > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Date of Birth: %s record(s)', v_null_dob);
    END IF;

    SELECT COUNT(*) 
    INTO v_future_dob
    FROM drivers
    WHERE date_of_birth > CURRENT_DATE;

    IF v_future_dob > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Date of Birth: %s record(s)', v_future_dob);
    END IF;

    -- Unrealistic age: born more than 100 years ago
    SELECT COUNT(*) 
    INTO v_unrealistic_dob
    FROM drivers
    WHERE date_of_birth IS NOT NULL
      AND date_of_birth < CURRENT_DATE - INTERVAL '100 years';

    IF v_unrealistic_dob > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Unrealistic Date of Birth (over 100 years old): %s record(s)', v_unrealistic_dob);
    END IF;

    -- Underage at hire: minimum hiring age assumed to be 18
    -- (interstate CDL minimum is typically 21 -- adjust threshold if needed)
    SELECT COUNT(*) 
    INTO v_underage_at_hire
    FROM drivers
    WHERE date_of_birth IS NOT NULL
      AND hire_date IS NOT NULL
      AND EXTRACT(YEAR FROM AGE(hire_date, date_of_birth)) < 18;

    IF v_underage_at_hire > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Driver Under Minimum Hiring Age (18) at Hire Date: %s record(s)', v_underage_at_hire);
    END IF;

    -- ===========================================================
    -- termination_date checks
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_termination_before_hire
    FROM drivers
    WHERE termination_date IS NOT NULL
      AND hire_date IS NOT NULL
      AND termination_date < hire_date;

    IF v_termination_before_hire > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Termination Date Before Hire Date: %s record(s)', v_termination_before_hire);
    END IF;

    SELECT COUNT(*) 
    INTO v_future_termination
    FROM drivers
    WHERE termination_date > CURRENT_DATE;

    IF v_future_termination > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Termination Date: %s record(s)', v_future_termination);
    END IF;

    -- Status/date consistency: status says terminated but no termination_date
    -- (assumes employment_status uses the value 'Terminated' -- adjust if different)
    SELECT COUNT(*) 
    INTO v_terminated_missing_date
    FROM drivers
    WHERE UPPER(TRIM(employment_status)) = 'TERMINATED'
      AND termination_date IS NULL;

    IF v_terminated_missing_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Status Terminated but Missing Termination Date: %s record(s)', v_terminated_missing_date);
    END IF;

    -- Status/date consistency: status says active but a termination_date exists
    SELECT COUNT(*) 
    INTO v_active_with_term_date
    FROM drivers
    WHERE UPPER(TRIM(employment_status)) = 'ACTIVE'
      AND termination_date IS NOT NULL;

    IF v_active_with_term_date > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Status Active but Termination Date Present: %s record(s)', v_active_with_term_date);
    END IF;

    -- ===========================================================
    -- license_number checks
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_license_number
    FROM drivers
    WHERE license_number IS NULL OR TRIM(license_number) = '';

    IF v_null_license_number > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing License Number: %s record(s)', v_null_license_number);
    END IF;

    -- Duplicate license (same number + same issuing state)
    SELECT COUNT(*) 
    INTO v_duplicate_license
    FROM (
        SELECT license_number, license_state
        FROM drivers
        WHERE license_number IS NOT NULL
          AND license_state IS NOT NULL
        GROUP BY license_number, license_state
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_license > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate License Number + State Combination: %s duplicate value(s)', v_duplicate_license);
    END IF;

    -- ===========================================================
    -- license_state checks
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_license_state
    FROM drivers
    WHERE license_state IS NULL OR TRIM(license_state) = '';

    IF v_null_license_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing License State: %s record(s)', v_null_license_state);
    END IF;

    -- Must be a 2-letter state/province code
    SELECT COUNT(*) 
    INTO v_invalid_license_state
    FROM drivers
    WHERE license_state IS NOT NULL
      AND TRIM(license_state) <> ''
      AND license_state !~ '^[A-Za-z]{2}$';

    IF v_invalid_license_state > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid License State Format (expected 2-letter code): %s record(s)', v_invalid_license_state);
    END IF;

    -- ===========================================================
    -- home_terminal
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_home_terminal
    FROM drivers
    WHERE home_terminal IS NULL OR TRIM(home_terminal) = '';

    IF v_null_home_terminal > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Home Terminal: %s record(s)', v_null_home_terminal);
    END IF;

    -- ===========================================================
    -- employment_status
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_employment_status
    FROM drivers
    WHERE employment_status IS NULL OR TRIM(employment_status) = '';

    IF v_null_employment_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Employment Status: %s record(s)', v_null_employment_status);
    END IF;

    -- Adjust this allowed-value list to match your actual status values
    SELECT COUNT(*) 
    INTO v_invalid_employment_status
    FROM drivers
    WHERE employment_status IS NOT NULL
      AND TRIM(employment_status) <> ''
      AND UPPER(TRIM(employment_status)) NOT IN ('ACTIVE', 'TERMINATED', 'ON LEAVE', 'SUSPENDED', 'INACTIVE');

    IF v_invalid_employment_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid Employment Status Value: %s record(s)', v_invalid_employment_status);
    END IF;

    -- ===========================================================
    -- cdl_class
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_cdl_class
    FROM drivers
    WHERE cdl_class IS NULL OR TRIM(cdl_class) = '';

    IF v_null_cdl_class > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing CDL Class: %s record(s)', v_null_cdl_class);
    END IF;

    -- Adjust this allowed-value list to match your actual CDL class codes
    SELECT COUNT(*) 
    INTO v_invalid_cdl_class
    FROM drivers
    WHERE cdl_class IS NOT NULL
      AND TRIM(cdl_class) <> ''
      AND UPPER(TRIM(cdl_class)) NOT IN ('A', 'B', 'C', 'NON-CDL', 'NONE');

    IF v_invalid_cdl_class > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Invalid CDL Class Value: %s record(s)', v_invalid_cdl_class);
    END IF;

    -- ===========================================================
    -- years_experience
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_negative_years_experience
    FROM drivers
    WHERE years_experience < 0;

    IF v_negative_years_experience > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Years of Experience: %s record(s)', v_negative_years_experience);
    END IF;

    -- Flag unrealistically high experience (over 60 years)
    SELECT COUNT(*) 
    INTO v_excessive_years_experience
    FROM drivers
    WHERE years_experience > 60;

    IF v_excessive_years_experience > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Unrealistic Years of Experience (over 60): %s record(s)', v_excessive_years_experience);
    END IF;

    -- Experience can't exceed (current age - 16), assuming earliest possible driving age of 16
    SELECT COUNT(*) 
    INTO v_experience_exceeds_age
    FROM drivers
    WHERE years_experience IS NOT NULL
      AND date_of_birth IS NOT NULL
      AND years_experience > (EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_of_birth)) - 16);

    IF v_experience_exceeds_age > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Years of Experience Exceeds Plausible Driving Years for Age: %s record(s)', v_experience_exceeds_age);
    END IF;

    -- ===========================================================
    -- updated_at
    -- ===========================================================
    SELECT COUNT(*) 
    INTO v_null_updated_at
    FROM drivers
    WHERE updated_at IS NULL;

    IF v_null_updated_at > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Updated At Timestamp: %s record(s)', v_null_updated_at);
    END IF;

    SELECT COUNT(*) INTO v_future_updated_at
    FROM drivers
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
        E'DRIVER DATA QUALITY VALIDATION FAILED\n%',
        v_errors;
    END IF;

    RAISE NOTICE 'DRIVER DATA QUALITY VALIDATION PASSED';

END;
$$;