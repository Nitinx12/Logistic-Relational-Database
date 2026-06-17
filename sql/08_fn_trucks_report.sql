-- =====================================================================
-- Function: fn_trucks_report
-- Purpose : Truck-level fleet report combining truck master data with
--           trip/revenue/utilization, fuel purchase cost, and
--           maintenance history, optionally scoped to a date window.
--
-- Design note: trips, fuel_purchases, and maintenance_records are all
-- one-to-many against trucks. Each is pre-aggregated per truck in its
-- own CTE *before* being joined to the truck list, so none of them are
-- ever joined directly to each other — this avoids the join fan-out
-- problem that would otherwise inflate SUMs (same pattern used in
-- fn_customers_report and fn_drivers_report).
--
-- Parameters (all optional — pass NULL or omit to skip a filter):
--   p_start_date     DATE     - Only include trips (by dispatch_date),
--                                fuel purchases (by purchase_date), and
--                                maintenance (by maintenance_date)
--                                on/after this date. NULL = no lower
--                                bound.
--   p_end_date       DATE     - Only include the above on/before this
--                                date. NULL = no upper bound.
--   p_status         VARCHAR  - Restrict to one trucks.status value
--                                (e.g. 'Active', 'Out of Service').
--                                Case-sensitive exact match. NULL = all
--                                statuses.
--   p_home_terminal  VARCHAR  - Restrict to one trucks.home_terminal
--                                value. NULL = include all terminals.
--   p_min_miles      NUMERIC  - Only return trucks with at least this
--                                many total_miles in the window.
--                                NULL = no minimum.
--
-- Output  : one row per truck matching the filters. Trucks with no
--           trips, fuel purchases, or maintenance in the window still
--           appear (via LEFT JOIN), with 0 / NULL metric values rather
--           than being dropped.
--
-- How to call it:
--   -- 1) Everything, no filters — full fleet, full history
--   SELECT * FROM fn_trucks_report();
--
--   -- 2) Scope to a specific year
--   SELECT * FROM fn_trucks_report('2023-01-01', '2023-12-31');
--
--   -- 3) Only active trucks, any date
--   SELECT * FROM fn_trucks_report(NULL, NULL, 'Active');
--
--   -- 4) Active trucks at one terminal that ran at least 10k miles
--   SELECT * FROM fn_trucks_report(
--       '2024-01-01', '2024-12-31', 'Active', 'Dallas', 10000
--   );
--
--   -- 5) Highest cost-per-mile trucks (fuel + maintenance combined)
--   SELECT * FROM fn_trucks_report()
--   WHERE total_miles > 0
--   ORDER BY cost_per_mile DESC;
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_trucks_report(
    p_start_date     DATE    DEFAULT NULL,
    p_end_date       DATE    DEFAULT NULL,
    p_status         VARCHAR DEFAULT NULL,
    p_home_terminal  VARCHAR DEFAULT NULL,
    p_min_miles      NUMERIC DEFAULT NULL
)
RETURNS TABLE(
    truck_id                 VARCHAR,
    unit_number              BIGINT,
    make                     VARCHAR,
    model_year               BIGINT,
    fuel_type                VARCHAR,
    tank_capacity_gallons    BIGINT,
    status                   VARCHAR,
    home_terminal            VARCHAR,
    acquisition_date         DATE,
    acquisition_mileage      BIGINT,
    total_trips              BIGINT,
    total_miles              NUMERIC,
    total_revenue            NUMERIC,
    total_fuel_gallons_used  NUMERIC,
    avg_mpg                  NUMERIC,
    revenue_per_mile         NUMERIC,
    total_fuel_purchases     BIGINT,
    total_gallons_purchased  NUMERIC,
    total_fuel_cost          NUMERIC,
    avg_price_per_gallon     NUMERIC,
    total_maintenance_events BIGINT,
    total_labor_cost         NUMERIC,
    total_parts_cost         NUMERIC,
    total_maintenance_cost   NUMERIC,
    total_downtime_hours     NUMERIC,
    cost_per_mile            NUMERIC
)
LANGUAGE plpgsql
AS $$

DECLARE
    -- NULL means "no bound" — never collapsed into a default window.
    v_start_date DATE := p_start_date;
    v_end_date   DATE := p_end_date;

BEGIN
    IF v_start_date IS NOT NULL AND v_end_date IS NOT NULL AND v_start_date > v_end_date THEN
        RAISE EXCEPTION 
        'p_start_date (%) cannot be after p_end_date (%)', 
        v_start_date, 
        v_end_date;
    END IF;

    IF p_min_miles IS NOT NULL AND p_min_miles < 0 THEN
        RAISE EXCEPTION 
        'p_min_miles cannot be negative (got %)', 
        p_min_miles;
    END IF;

    RETURN QUERY

    WITH trip_agg AS (
        SELECT
            T.truck_id,
            COUNT(DISTINCT T.trip_id)                  AS total_trips,
            COALESCE(SUM(T.actual_distance_miles), 0)  AS total_miles,
            COALESCE(SUM(T.fuel_gallons_used), 0)      AS total_fuel_gallons_used,
            COALESCE(SUM(L.revenue), 0)                AS total_revenue
        FROM trips AS T
        LEFT JOIN loads AS L
            ON L.load_id = T.load_id
        WHERE (v_start_date IS NULL OR T.dispatch_date >= v_start_date)
          AND (v_end_date   IS NULL OR T.dispatch_date <= v_end_date)
        GROUP BY T.truck_id
    ),
    fuel_agg AS (
        SELECT
            FP.truck_id,
            COUNT(DISTINCT FP.fuel_purchase_id)   AS total_fuel_purchases,
            COALESCE(SUM(FP.gallons), 0)          AS total_gallons_purchased,
            COALESCE(SUM(FP.total_cost), 0)       AS total_fuel_cost
        FROM fuel_purchases AS FP
        WHERE (v_start_date IS NULL OR FP.purchase_date >= v_start_date)
          AND (v_end_date   IS NULL OR FP.purchase_date <= v_end_date)
        GROUP BY FP.truck_id
    ),
    maintenance_agg AS (
        SELECT
            M.truck_id,
            COUNT(DISTINCT M.maintenance_id)        AS total_maintenance_events,
            COALESCE(SUM(M.labor_cost), 0)          AS total_labor_cost,
            COALESCE(SUM(M.parts_cost), 0)          AS total_parts_cost,
            COALESCE(SUM(M.total_cost), 0)          AS total_maintenance_cost,
            COALESCE(SUM(M.downtime_hours), 0)      AS total_downtime_hours
        FROM maintenance_records AS M
        WHERE (v_start_date IS NULL OR M.maintenance_date >= v_start_date)
          AND (v_end_date   IS NULL OR M.maintenance_date <= v_end_date)
        GROUP BY M.truck_id
    )
    SELECT
        TR.truck_id,
        TR.unit_number,
        TR.make,
        TR.model_year,
        TR.fuel_type,
        TR.tank_capacity_gallons,
        TR.status,
        TR.home_terminal,
        TR.acquisition_date,
        TR.acquisition_mileage,
        COALESCE(TA.total_trips, 0)                                          AS total_trips,
        COALESCE(TA.total_miles, 0)                                          AS total_miles,
        COALESCE(TA.total_revenue, 0)                                        AS total_revenue,
        COALESCE(TA.total_fuel_gallons_used, 0)                              AS total_fuel_gallons_used,
        CASE
            WHEN COALESCE(TA.total_fuel_gallons_used, 0) > 0
            THEN ROUND(TA.total_miles / TA.total_fuel_gallons_used, 2)
            ELSE NULL
        END                                                                  AS avg_mpg,
        CASE
            WHEN COALESCE(TA.total_miles, 0) > 0
            THEN ROUND(TA.total_revenue / TA.total_miles, 2)
            ELSE NULL
        END                                                                  AS revenue_per_mile,
        COALESCE(FA.total_fuel_purchases, 0)                                 AS total_fuel_purchases,
        COALESCE(FA.total_gallons_purchased, 0)                              AS total_gallons_purchased,
        COALESCE(FA.total_fuel_cost, 0)                                      AS total_fuel_cost,
        CASE
            WHEN COALESCE(FA.total_gallons_purchased, 0) > 0
            THEN ROUND(FA.total_fuel_cost / FA.total_gallons_purchased, 4)
            ELSE NULL
        END                                                                  AS avg_price_per_gallon,
        COALESCE(MA.total_maintenance_events, 0)                             AS total_maintenance_events,
        COALESCE(MA.total_labor_cost, 0)                                     AS total_labor_cost,
        COALESCE(MA.total_parts_cost, 0)                                     AS total_parts_cost,
        COALESCE(MA.total_maintenance_cost, 0)                               AS total_maintenance_cost,
        COALESCE(MA.total_downtime_hours, 0)                                 AS total_downtime_hours,
        CASE
            WHEN COALESCE(TA.total_miles, 0) > 0
            THEN ROUND(
                    (COALESCE(FA.total_fuel_cost, 0) + COALESCE(MA.total_maintenance_cost, 0))
                    / TA.total_miles, 4)
            ELSE NULL
        END                                                                  AS cost_per_mile
    FROM trucks AS TR
    LEFT JOIN trip_agg AS TA
        ON TA.truck_id = TR.truck_id
    LEFT JOIN fuel_agg AS FA
        ON FA.truck_id = TR.truck_id
    LEFT JOIN maintenance_agg AS MA
        ON MA.truck_id = TR.truck_id
    WHERE
        (p_status        IS NULL OR TR.status        = p_status)
        AND (p_home_terminal IS NULL OR TR.home_terminal = p_home_terminal)
        AND (p_min_miles     IS NULL OR COALESCE(TA.total_miles, 0) >= p_min_miles)
    ORDER BY total_miles DESC NULLS LAST;

END;
$$;