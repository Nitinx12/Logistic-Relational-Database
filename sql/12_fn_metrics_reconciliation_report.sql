-- =====================================================================
-- Function: fn_metrics_reconciliation_report
-- Purpose : Compares live-computed monthly metrics (from trips/loads)
--           against the pre-aggregated driver_monthly_metrics or
--           truck_utilization_metrics tables, to catch drift/bugs
--           between the two sources. Dynamic like fn_sales_report:
--           one function, two entity types, chosen via p_entity_type.
--
-- Parameters:
--   p_entity_type    VARCHAR  - 'driver' or 'truck' (case-insensitive,
--                                required — no default). Anything else
--                                raises an exception.
--   p_start_month    DATE     - Only compare months on/after this date
--                                (compared at month granularity).
--                                NULL = no lower bound.
--   p_end_month      DATE     - Only compare months on/before this
--                                date. NULL = no upper bound.
--   p_tolerance_pct  NUMERIC  - Variance threshold (as a percentage,
--                                e.g. 5 = 5%). Any metric whose percent
--                                difference exceeds this in either
--                                direction sets
--                                has_significant_variance = TRUE.
--                                Defaults to 5.
--
-- Output  : one row per entity_id/month found in the pre-aggregated
--           metrics table, with the stored value, the computed value,
--           and a variance percentage side by side for trips, miles,
--           revenue, and average MPG, plus a single boolean flag for
--           "does anything here look off."
--
-- How to call it:
--   -- 1) All drivers, all months, default 5% tolerance
--   SELECT * FROM fn_metrics_reconciliation_report('driver');
--
--   -- 2) Trucks for 2024 with a tighter 2% tolerance
--   SELECT * FROM fn_metrics_reconciliation_report(
--       'truck', '2024-01-01', '2024-12-31', 2
--   );
--
--   -- 3) Only show drivers/months that actually look wrong
--   SELECT * FROM fn_metrics_reconciliation_report('driver')
--   WHERE has_significant_variance = TRUE
--   ORDER BY ABS(revenue_variance_pct) DESC;
--
--   -- 4) Invalid entity type — demonstrates the error handling
--   SELECT * FROM fn_metrics_reconciliation_report('trailer');
--   -- ERROR: Invalid p_entity_type value: "trailer".
--   --        Must be one of: driver, truck
--
-- Notes:
--   * "Computed" values come from trips (joined to loads for revenue),
--     grouped by entity_id and calendar month of dispatch_date.
--     computed_avg_mpg is a weighted total_miles/total_fuel_gallons,
--     matching the same approach used in the drivers/trucks reports —
--     it may legitimately differ slightly from a stored simple average
--     of per-trip MPG values, so don't assume every variance is a bug.
--   * Rows only appear for entity/month combinations present in the
--     pre-aggregated table. If trips exist for a month with no
--     corresponding pre-aggregated row, they won't show up here —
--     this checks "is the stored snapshot accurate," not "did we
--     forget to aggregate a month."
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_metrics_reconciliation_report(
    p_entity_type    VARCHAR,
    p_start_month    DATE    DEFAULT NULL,
    p_end_month      DATE    DEFAULT NULL,
    p_tolerance_pct  NUMERIC DEFAULT 5
)
RETURNS TABLE(
    entity_id                   VARCHAR,
    month                       DATE,
    stored_trips                NUMERIC,
    computed_trips              NUMERIC,
    trips_diff                  NUMERIC,
    stored_miles                NUMERIC,
    computed_miles              NUMERIC,
    miles_variance_pct          NUMERIC,
    stored_revenue              NUMERIC,
    computed_revenue            NUMERIC,
    revenue_variance_pct        NUMERIC,
    stored_avg_mpg              NUMERIC,
    computed_avg_mpg            NUMERIC,
    mpg_variance_pct            NUMERIC,
    has_significant_variance    BOOLEAN
)
LANGUAGE plpgsql
AS $$

DECLARE
    v_entity_type      VARCHAR;
    v_entity_column    VARCHAR;
    v_metrics_table    VARCHAR;
    v_start_month      DATE := p_start_month;
    v_end_month        DATE := p_end_month;
    v_sql              TEXT;

BEGIN
    -- ---- Input validation -------------------------------------------------
    v_entity_type := LOWER(TRIM(p_entity_type));

    IF v_entity_type NOT IN ('driver', 'truck') THEN
        RAISE EXCEPTION 'Invalid p_entity_type value: "%". Must be one of: driver, truck',
            p_entity_type;
    END IF;

    IF v_start_month IS NOT NULL AND v_end_month IS NOT NULL AND v_start_month > v_end_month THEN
        RAISE EXCEPTION 'p_start_month (%) cannot be after p_end_month (%)', 
            v_start_month, 
            v_end_month;
    END IF;

    IF p_tolerance_pct IS NULL OR p_tolerance_pct < 0 THEN
        RAISE EXCEPTION 'p_tolerance_pct cannot be NULL or negative (got %)', 
            p_tolerance_pct;
    END IF;

    v_entity_column := CASE v_entity_type WHEN 'driver' THEN 'driver_id' WHEN 'truck' THEN 'truck_id' END;
    v_metrics_table  := CASE v_entity_type WHEN 'driver' THEN 'driver_monthly_metrics' WHEN 'truck' THEN 'truck_utilization_metrics' END;

    -- ---- Build and run the dynamic comparison query
    BEGIN
        v_sql := format($sql$
            WITH computed AS (
                SELECT
                    T.%I                                                      AS entity_id,
                    date_trunc('month', T.dispatch_date)::DATE                AS month,
                    COUNT(DISTINCT T.trip_id)::NUMERIC                        AS computed_trips,
                    COALESCE(SUM(T.actual_distance_miles), 0)::NUMERIC        AS computed_miles,
                    COALESCE(SUM(L.revenue), 0)::NUMERIC                      AS computed_revenue,
                    CASE
                        WHEN COALESCE(SUM(T.fuel_gallons_used), 0) > 0
                        THEN ROUND(SUM(T.actual_distance_miles) / SUM(T.fuel_gallons_used), 2)
                        ELSE NULL
                    END                                                        AS computed_avg_mpg
                FROM trips AS T
                LEFT JOIN loads AS L
                    ON L.load_id = T.load_id
                WHERE T.%I IS NOT NULL
                  AND ($1 IS NULL OR date_trunc('month', T.dispatch_date)::DATE >= $1)
                  AND ($2 IS NULL OR date_trunc('month', T.dispatch_date)::DATE <= $2)
                GROUP BY T.%I, date_trunc('month', T.dispatch_date)
            ),
            variance_calc AS (
                SELECT
                    M.%I                                                            AS entity_id,
                    M.month                                                         AS month,
                    M.trips_completed::NUMERIC                                      AS stored_trips,
                    COALESCE(C.computed_trips, 0)                                   AS computed_trips,
                    COALESCE(C.computed_trips, 0) - M.trips_completed::NUMERIC      AS trips_diff,
                    M.total_miles::NUMERIC                                          AS stored_miles,
                    COALESCE(C.computed_miles, 0)                                   AS computed_miles,
                    CASE
                        WHEN M.total_miles > 0
                        THEN ROUND(100.0 * (COALESCE(C.computed_miles, 0) - M.total_miles) / M.total_miles, 2)
                        ELSE NULL
                    END                                                              AS miles_variance_pct,
                    M.total_revenue::NUMERIC                                         AS stored_revenue,
                    COALESCE(C.computed_revenue, 0)                                  AS computed_revenue,
                    CASE
                        WHEN M.total_revenue > 0
                        THEN ROUND(100.0 * (COALESCE(C.computed_revenue, 0) - M.total_revenue) / M.total_revenue, 2)
                        ELSE NULL
                    END                                                                     AS revenue_variance_pct,
                    M.average_mpg::NUMERIC                                                  AS stored_avg_mpg,
                    C.computed_avg_mpg                                                      AS computed_avg_mpg,
                    CASE
                        WHEN M.average_mpg > 0 AND C.computed_avg_mpg IS NOT NULL
                        THEN ROUND(100.0 * (C.computed_avg_mpg - M.average_mpg) / M.average_mpg, 2)
                        ELSE NULL
                    END                                                                     AS mpg_variance_pct
                FROM %I AS M
                LEFT JOIN computed AS C
                    ON C.entity_id = M.%I AND C.month = M.month
                WHERE ($1 IS NULL OR M.month >= $1)
                  AND ($2 IS NULL OR M.month <= $2)
            )
            SELECT
                VC.entity_id,
                VC.month,
                VC.stored_trips,
                VC.computed_trips,
                VC.trips_diff,
                VC.stored_miles,
                VC.computed_miles,
                VC.miles_variance_pct,
                VC.stored_revenue,
                VC.computed_revenue,
                VC.revenue_variance_pct,
                VC.stored_avg_mpg,
                VC.computed_avg_mpg,
                VC.mpg_variance_pct,
                (
                    (VC.miles_variance_pct   IS NOT NULL AND ABS(VC.miles_variance_pct)   > $3)
                    OR (VC.revenue_variance_pct IS NOT NULL AND ABS(VC.revenue_variance_pct) > $3)
                    OR (VC.mpg_variance_pct     IS NOT NULL AND ABS(VC.mpg_variance_pct)     > $3)
                )                                                                            AS has_significant_variance
            FROM variance_calc AS VC
            ORDER BY VC.entity_id, VC.month
        $sql$, v_entity_column, v_entity_column, v_entity_column, v_entity_column, v_metrics_table, v_entity_column);

        RETURN QUERY EXECUTE v_sql USING v_start_month, v_end_month, p_tolerance_pct;

    EXCEPTION
        WHEN division_by_zero THEN
            RAISE EXCEPTION 'fn_metrics_reconciliation_report: division by zero (entity_type=%): %',
                v_entity_type, SQLERRM;
        WHEN OTHERS THEN
            RAISE EXCEPTION 'fn_metrics_reconciliation_report failed (entity_type=%, months=% to %, tolerance=%): % [SQLSTATE %]',
                v_entity_type, v_start_month, v_end_month, p_tolerance_pct, SQLERRM, SQLSTATE;
    END;

END;
$$;