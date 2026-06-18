-- ============================================================================
-- Procedure Name : proc_customer_data_quality
-- Purpose        : Validates customer master data quality rules and prevents
--                  downstream reporting and analytics issues.
--
-- Validation Rules
--   1. Customer ID cannot be NULL or blank
--   2. Customer ID must be unique
--   3. Customer Name cannot be NULL or blank
--   4. Customer Type cannot be NULL or blank
--   5. Account Status cannot be NULL or blank
--   6. Primary Freight Type cannot be NULL or blank
--   7. Credit Terms Days cannot be negative
--   8. Annual Revenue Potential cannot be negative
--   9. Contract Start Date cannot be in the future
--
-- Behavior
--   • Aggregates all validation failures into a single error message
--   • Raises an exception when one or more validations fail
--   • Raises a success notice when all validations pass
--
-- Target Table  : customers
-- Author        : Nitin
-- Created Date  : 2026-06-18
-- ============================================================================
CREATE OR REPLACE proc_customer_data_quality()
LANGUAGE plpgsql
AS $$

DECLARE
    v_errors TEXT := '';

    v_null_customer_id          BIGINT;
    v_duplicate_customer_id     BIGINT;
    v_null_customer_name        BIGINT;
    v_null_customer_type        BIGINT;
    v_null_account_status       BIGINT;
    v_null_freight_type         BIGINT;
    v_negative_credit_terms     BIGINT;
    v_negative_revenue          BIGINT;
    v_future_contracts          BIGINT;

BEGIN

    -- ===========================================================
    -- Null customer_id
    -- ===========================================================
    SELECT COUNT(*)
    INTO v_null_customer_id
    FROM customers
    WHERE 
        customer_id IS NULL
        OR TRIM(customer_id) = '';
    
    IF v_null_customer_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Null Customer ID: %s record(s)', v_null_customer_id);
    END IF;

    -- ============================================================
    -- Duplicate customer_id
    -- ============================================================
    SELECT COUNT(*)
    INTO v_duplicate_customer_id
    FROM(
        SELECT customer_id
        FROM customers
        WHERE customer_id IS NOT NULL
        GROUP BY customer_id
        HAVING COUNT(*) > 1
    ) d;

    IF v_duplicate_customer_id > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Duplicate Customer IDs: %s duplicate value(s)',
               v_duplicate_customer_id);
    END IF;

    -- ================================================================
    -- Null customer name
    -- ================================================================
    SELECT COUNT(*)
    INTO v_null_customer_name
    FROM customers
    WHERE 
        customer_name IS NULL
        OR TRIM(customer_name) = '';

    IF v_null_customer_name > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Customer Name: %s record(s)',
               v_null_customer_name);
    END IF;

    -- ================================================================
    -- Null Customer Type
    -- ================================================================
    SELECT COUNT(*)
    INTO v_null_customer_type
    FROM customers
    WHERE customer_type IS NULL
       OR TRIM(customer_type) = '';

    IF v_null_customer_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Customer Type: %s record(s)',
               v_null_customer_type);
    END IF;

    -- ================================================================
    -- Null account_status
    -- ================================================================
    SELECT COUNT(*)
    INTO v_null_account_status
    FROM customers
    WHERE account_status IS NULL
       OR TRIM(account_status) = '';

    IF v_null_account_status > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Account Status: %s record(s)',
               v_null_account_status);
    END IF;

    -- ================================================================
    -- Null Freight Type
    -- ================================================================
    SELECT COUNT(*)
    INTO v_null_freight_type
    FROM customers
    WHERE primary_freight_type IS NULL
       OR TRIM(primary_freight_type) = '';

    IF v_null_freight_type > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Missing Primary Freight Type: %s record(s)',
               v_null_freight_type);
    END IF;

    -- ================================================================
    -- Negative Credit Terms
    -- ================================================================
    SELECT COUNT(*)
    INTO v_negative_credit_terms
    FROM customers
    WHERE credit_terms_days < 0;

    IF v_negative_credit_terms > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Credit Terms: %s record(s)',
               v_negative_credit_terms);
    END IF;

    ------------------------------------------------------------------
    -- Negative Revenue Potential
    ------------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_negative_revenue
    FROM customers
    WHERE annual_revenue_potential < 0;

    IF v_negative_revenue > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Negative Revenue Potential: %s record(s)',
               v_negative_revenue);
    END IF;

    ------------------------------------------------------------------
    -- Future Contract Dates
    ------------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_future_contracts
    FROM customers
    WHERE contract_start_date > CURRENT_DATE;

    IF v_future_contracts > 0 THEN
        v_errors := v_errors ||
        format(E'\n[FAIL] Future Contract Start Date: %s record(s)',
               v_future_contracts);
    END IF;

    ------------------------------------------------------------------
    -- Final Result
    ------------------------------------------------------------------
    IF v_errors <> '' THEN
        RAISE EXCEPTION
        E'CUSTOMER DATA QUALITY VALIDATION FAILED\n%',

        v_errors;
    END IF;

    RAISE NOTICE 'CUSTOMER DATA QUALITY VALIDATION PASSED';

END;
$$;







