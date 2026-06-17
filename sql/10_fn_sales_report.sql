-- =====================================================================
-- Function: fn_sales_report
-- Purpose : Dynamic sales report aggregating loads.revenue (plus fuel
--           surcharge and accessorial charges) into daily, weekly, or
--           monthly buckets, chosen at call time via p_granularity.
--           This is the "dynamic" piece — the same function reshapes
--           its grouping/output based on that one input parameter,
--           via dynamic SQL (EXECUTE format(...)), rather than needing
--           three separate functions for three time grains.
--
-- Parameters (all optional except p_granularity has a default):
--   p_start_date     DATE     - Only include loads on/after this date
--                                (loads.load_date). NULL = no lower
--                                bound.
--   p_end_date       DATE     - Only include loads on/before this date.
--                                NULL = no upper bound.
--   p_granularity    VARCHAR  - One of 'daily', 'weekly', 'monthly',
--                                'quarterly' (case-insensitive).
--                                Defaults to 'daily'. Anything else
--                                raises an exception — see error
--                                handling below.
--   p_customer_type  VARCHAR  - Restrict to one customers.customer_type
--                                value. NULL = include all types.
--   p_load_status    VARCHAR  - Restrict to one loads.load_status value
--                                (e.g. 'Delivered'). Case-sensitive
--                                exact match. NULL = include all
--                                statuses.
--
-- Output  : one row per time period (day/week/month) that has at
--           least one matching load. Empty periods are NOT padded in —
--           this reports actual sales activity, not a calendar grid.
--           period_label is human-readable: 'YYYY-MM-DD' for daily,
--           ISO 'YYYY-"W"WW' for weekly, 'YYYY-MM' for monthly, and
--           'YYYY-"Q"Q' (e.g. '2024-Q3') for quarterly.
--
-- How to call it:
--   -- 1) Daily sales, full history, no filters
--   SELECT * FROM fn_sales_report();
--
--   -- 2) Weekly sales for 2024
--   SELECT * FROM fn_sales_report('2024-01-01', '2024-12-31', 'weekly');
--
--   -- 3) Monthly sales for Contract customers only
--   SELECT * FROM fn_sales_report(NULL, NULL, 'monthly', 'Contract');
--
--   -- 4) Daily sales of only Delivered loads in Q1 2024
--   SELECT * FROM fn_sales_report(
--       '2024-01-01', '2024-03-31', 'daily', NULL, 'Delivered'
--   );
--
--   -- 5) Quarterly sales for the last two years
--   SELECT * FROM fn_sales_report('2024-01-01', '2025-12-31', 'quarterly');
--
--   -- 6) Invalid granularity — demonstrates the error handling
--   SELECT * FROM fn_sales_report(NULL, NULL, 'yearly');
--   -- ERROR: Invalid p_granularity value: "yearly".
--   --        Must be one of: daily, weekly, monthly, quarterly
--
-- Error handling:
--   * p_start_date > p_end_date                -> RAISE EXCEPTION
--   * p_granularity not in the allowed set      -> RAISE EXCEPTION,
--     listing the value that was actually passed in the message
--   * Any other unexpected error while building/running the dynamic
--     query is caught by the EXCEPTION block at the bottom and
--     re-raised with the granularity/date/filter context attached,
--     instead of surfacing a bare/cryptic Postgres error.
--   * If the filters/date range match zero rows, a RAISE NOTICE is
--     emitted (not an error) so you know the query ran fine but found
--     nothing, rather than silently wondering whether it worked.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_sales_report(
    p_start_date     DATE    DEFAULT NULL,
    p_end_date       DATE    DEFAULT NULL,
    p_granularity    VARCHAR DEFAULT 'daily',
    p_customer_type  VARCHAR DEFAULT NULL,
    p_load_status    VARCHAR DEFAULT NULL
)
RETURNS TABLE(
    period_start                 DATE,
    period_label                 VARCHAR,
    total_loads                  BIGINT,
    unique_customers             BIGINT,
    total_weight_lbs             NUMERIC,
    total_revenue                NUMERIC,
    total_fuel_surcharge         NUMERIC,
    total_accessorial_charges    NUMERIC,
    total_gross_revenue          NUMERIC,
    avg_revenue_per_load         NUMERIC
)
LANGUAGE plpgsql
AS $$

DECLARE
    v_start_date    DATE    := p_start_date;   -- NULL means "no bound"
    v_end_date      DATE    := p_end_date;
    v_granularity   VARCHAR;
    v_trunc_unit    VARCHAR;
    v_date_format   VARCHAR;
    v_sql           TEXT;
    v_row_count     INT;

BEGIN
    -- ---- Input validation -------------------------------------------------
    IF v_start_date IS NOT NULL 
        AND v_end_date IS NOT NULL 
        AND v_start_date > v_end_date THEN
        RAISE EXCEPTION 
            'p_start_date (%) cannot be after p_end_date (%)', 
             v_start_date, 
             v_end_date;
    END IF;

    v_granularity := LOWER(TRIM(COALESCE(p_granularity, 'daily')));

    IF v_granularity NOT IN ('daily', 'weekly', 'monthly', 'quarterly') THEN
        RAISE EXCEPTION 
            'Invalid p_granularity value: "%". Must be one of: 
             daily, 
             weekly, 
             monthly, 
             quarterly',
             p_granularity;
    END IF;

    -- Map the validated granularity to a date_trunc unit and a display format.
    -- Note: v_trunc_unit only ever holds one of these four hardcoded
    -- literals (never raw user input), so it's safe to splice into the
    -- dynamic query below with format(... %L ...).
    v_trunc_unit  := CASE v_granularity
                          WHEN 'daily'     THEN 'day'
                          WHEN 'weekly'    THEN 'week'
                          WHEN 'monthly'   THEN 'month'
                          WHEN 'quarterly' THEN 'quarter'
                      END;

    v_date_format := CASE v_trunc_unit
                          WHEN 'day'     THEN 'YYYY-MM-DD'
                          WHEN 'week'    THEN 'IYYY-"W"IW'
                          WHEN 'month'   THEN 'YYYY-MM'
                          WHEN 'quarter' THEN 'YYYY-"Q"Q'
                      END;

    -- ---- Build and run the dynamic aggregation query
    BEGIN
        v_sql := format($sql$
            SELECT
                date_trunc(%L, L.load_date)::DATE                                        AS period_start,
                to_char(date_trunc(%L, L.load_date), %L)::VARCHAR                        AS period_label,
                COUNT(DISTINCT L.load_id)                                                AS total_loads,
                COUNT(DISTINCT L.customer_id)                                            AS unique_customers,
                COALESCE(SUM(L.weight_lbs), 0)                                           AS total_weight_lbs,
                COALESCE(SUM(L.revenue), 0)                                              AS total_revenue,
                COALESCE(SUM(L.fuel_surcharge), 0)                                       AS total_fuel_surcharge,
                COALESCE(SUM(L.accessorial_charges), 0)                                  AS total_accessorial_charges,
                COALESCE(SUM(L.revenue + L.fuel_surcharge + L.accessorial_charges), 0)   AS total_gross_revenue,
                CASE
                    WHEN COUNT(DISTINCT L.load_id) > 0
                    THEN ROUND(COALESCE(SUM(L.revenue), 0) / COUNT(DISTINCT L.load_id), 2)
                    ELSE 0
                END                                                                      AS avg_revenue_per_load
            FROM loads AS L
            JOIN customers AS C
                ON C.customer_id = L.customer_id
            WHERE ($1 IS NULL OR L.load_date >= $1)
              AND ($2 IS NULL OR L.load_date <= $2)
              AND ($3 IS NULL OR C.customer_type = $3)
              AND ($4 IS NULL OR L.load_status = $4)
            GROUP BY date_trunc(%L, L.load_date)
            ORDER BY period_start
        $sql$, v_trunc_unit, v_trunc_unit, v_date_format, v_trunc_unit);

        RETURN QUERY 
            EXECUTE v_sql USING 
                v_start_date, 
                v_end_date, 
                p_customer_type, 
                p_load_status;

        GET DIAGNOSTICS v_row_count = ROW_COUNT;

        IF v_row_count = 0 THEN
            RAISE NOTICE 
                'fn_sales_report: no matching sales data found for granularity=%, 
                dates=% to %, 
                customer_type=%, 
                load_status=%',
                v_granularity, 
                v_start_date, 
                v_end_date, 
                p_customer_type, 
                p_load_status;
        END IF;

    EXCEPTION
        WHEN division_by_zero THEN
            RAISE EXCEPTION 
                'fn_sales_report: division by zero while computing averages (granularity=%): %',
                v_granularity, 
                SQLERRM;
        WHEN OTHERS THEN
            RAISE EXCEPTION 
                'fn_sales_report failed (granularity=%, dates=% to %, 
                 customer_type=%, 
                 load_status=%): % [SQLSTATE %]',
                v_granularity, 
                v_start_date, 
                v_end_date, 
                p_customer_type, 
                p_load_status, 
                SQLERRM, 
                SQLSTATE;
    END;

END;
$$;