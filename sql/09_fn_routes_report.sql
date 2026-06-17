-- =====================================================================
-- Function: fn_routes_report
-- Purpose : Route/lane-level performance report combining route master
--           data (planned distance, rate, transit days) with actual
--           load revenue/volume, actual trip distance/duration, and
--           delivery on-time performance, optionally scoped to a date
--           window.
--
-- Design note: loads, trips, and delivery_events are joined per load
-- (one trip per load, one-or-more delivery events per load), but the
-- load-level and delivery-level aggregations are computed in separate
-- CTEs *before* being joined onto the route list. This keeps the
-- delivery_events fan-out (a load can have multiple events) from
-- inflating load/trip-level SUMs like total_revenue or total_weight_lbs
-- — same pattern used in fn_customers_report, fn_drivers_report, and
-- fn_trucks_report.
--
-- Parameters (all optional — pass NULL or omit to skip a filter):
--   p_start_date         DATE     - Only include loads/trips/delivery
--                                    events for loads dispatched
--                                    (by loads.load_date) on/after this
--                                    date. NULL = no lower bound.
--   p_end_date           DATE     - Only include the above on/before
--                                    this date. NULL = no upper bound.
--   p_origin_state       VARCHAR  - Restrict to one routes.origin_state
--                                    value (2-letter state code).
--                                    NULL = include all origin states.
--   p_destination_state  VARCHAR  - Restrict to one
--                                    routes.destination_state value.
--                                    NULL = include all destination
--                                    states.
--   p_min_loads          BIGINT   - Only return routes with at least
--                                    this many loads in the window.
--                                    NULL = no minimum.
--
-- Output  : one row per route matching the filters. Routes with no
--           loads in the window still appear (via LEFT JOIN), with
--           0 / NULL metric values rather than being dropped.
--
-- How to call it:
--   -- 1) Everything, no filters — every route, full history
--   SELECT * FROM fn_routes_report();
--
--   -- 2) Scope to a specific year
--   SELECT * FROM fn_routes_report('2023-01-01', '2023-12-31');
--
--   -- 3) Only routes originating in Texas
--   SELECT * FROM fn_routes_report(NULL, NULL, 'TX');
--
--   -- 4) TX -> CA lanes in 2024 with at least 20 loads
--   SELECT * FROM fn_routes_report(
--       '2024-01-01', '2024-12-31', 'TX', 'CA', 20
--   );
--
--   -- 5) Lanes running noticeably longer than their planned distance
--   SELECT * FROM fn_routes_report()
--   WHERE total_trips > 0
--   ORDER BY miles_variance_pct DESC;
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_routes_report(
    p_start_date         DATE    DEFAULT NULL,
    p_end_date           DATE    DEFAULT NULL,
    p_origin_state       VARCHAR DEFAULT NULL,
    p_destination_state  VARCHAR DEFAULT NULL,
    p_min_loads          BIGINT  DEFAULT NULL
)
RETURNS TABLE(
    route_id                  VARCHAR,
    origin_city               VARCHAR,
    origin_state              VARCHAR,
    destination_city          VARCHAR,
    destination_state         VARCHAR,
    typical_distance_miles    BIGINT,
    base_rate_per_mile        NUMERIC,
    fuel_surcharge_rate       NUMERIC,
    typical_transit_days      BIGINT,
    total_loads               BIGINT,
    total_weight_lbs          NUMERIC,
    total_revenue             NUMERIC,
    total_fuel_surcharge      NUMERIC,
    total_accessorial_charges NUMERIC,
    avg_revenue_per_load      NUMERIC,
    total_trips               BIGINT,
    avg_actual_distance_miles NUMERIC,
    avg_actual_duration_hours NUMERIC,
    miles_variance_pct        NUMERIC,
    revenue_per_mile          NUMERIC,
    total_delivery_events     BIGINT,
    on_time_deliveries        BIGINT,
    late_deliveries           BIGINT,
    on_time_delivery_pct      NUMERIC,
    avg_detention_minutes     NUMERIC
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

    IF p_min_loads IS NOT NULL AND p_min_loads < 0 THEN
        RAISE EXCEPTION 
            'p_min_loads cannot be negative (got %)', 
            p_min_loads;
    END IF;

    RETURN QUERY

    WITH load_agg AS (
        SELECT
            L.route_id,
            COUNT(DISTINCT L.load_id)                    AS total_loads,
            COALESCE(SUM(L.weight_lbs), 0)               AS total_weight_lbs,
            COALESCE(SUM(L.revenue), 0)                  AS total_revenue,
            COALESCE(SUM(L.fuel_surcharge), 0)           AS total_fuel_surcharge,
            COALESCE(SUM(L.accessorial_charges), 0)      AS total_accessorial_charges,
            COUNT(DISTINCT T.trip_id)                    AS total_trips,
            COALESCE(SUM(T.actual_distance_miles), 0)    AS total_actual_miles,
            COALESCE(SUM(T.actual_duration_hours), 0)    AS total_actual_duration_hours
        FROM loads AS L
        LEFT JOIN trips AS T
            ON T.load_id = L.load_id
        WHERE (v_start_date IS NULL OR L.load_date >= v_start_date)
          AND (v_end_date   IS NULL OR L.load_date <= v_end_date)
        GROUP BY L.route_id
    ),
    delivery_agg AS (
        SELECT
            L.route_id,
            COUNT(DISTINCT DE.event_id)                           AS total_delivery_events,
            COUNT(DISTINCT DE.event_id) 
                FILTER (WHERE UPPER(DE.on_time_flag) = 'TRUE')    AS on_time_deliveries,
            COUNT(DISTINCT DE.event_id) 
                FILTER (WHERE UPPER(DE.on_time_flag) = 'FALSE')   AS late_deliveries,
            COALESCE(SUM(DE.detention_minutes), 0)                AS total_detention_minutes
        FROM delivery_events AS DE
        JOIN loads AS L
            ON L.load_id = DE.load_id
        WHERE (v_start_date IS NULL OR L.load_date >= v_start_date)
          AND (v_end_date   IS NULL OR L.load_date <= v_end_date)
        GROUP BY L.route_id
    )
    SELECT
        R.route_id,
        R.origin_city,
        R.origin_state,
        R.destination_city,
        R.destination_state,
        R.typical_distance_miles,
        R.base_rate_per_mile,
        R.fuel_surcharge_rate,
        R.typical_transit_days,
        COALESCE(LA.total_loads, 0)                                          AS total_loads,
        COALESCE(LA.total_weight_lbs, 0)                                     AS total_weight_lbs,
        COALESCE(LA.total_revenue, 0)                                        AS total_revenue,
        COALESCE(LA.total_fuel_surcharge, 0)                                 AS total_fuel_surcharge,
        COALESCE(LA.total_accessorial_charges, 0)                            AS total_accessorial_charges,
        CASE
            WHEN COALESCE(LA.total_loads, 0) > 0
            THEN ROUND(LA.total_revenue / LA.total_loads, 2)
            ELSE 0
        END                                                                  AS avg_revenue_per_load,
        COALESCE(LA.total_trips, 0)                                          AS total_trips,
        CASE
            WHEN COALESCE(LA.total_trips, 0) > 0
            THEN ROUND(LA.total_actual_miles / LA.total_trips, 2)
            ELSE NULL
        END                                                                  AS avg_actual_distance_miles,
        CASE
            WHEN COALESCE(LA.total_trips, 0) > 0
            THEN ROUND(LA.total_actual_duration_hours / LA.total_trips, 2)
            ELSE NULL
        END                                                                  AS avg_actual_duration_hours,
        CASE
            WHEN COALESCE(LA.total_trips, 0) > 0
                 AND R.typical_distance_miles IS NOT NULL
                 AND R.typical_distance_miles > 0
            THEN ROUND(
                    100.0 * ((LA.total_actual_miles / LA.total_trips) - R.typical_distance_miles)
                    / R.typical_distance_miles, 2)
            ELSE NULL
        END                                                                  AS miles_variance_pct,
        CASE
            WHEN COALESCE(LA.total_actual_miles, 0) > 0
            THEN ROUND(LA.total_revenue / LA.total_actual_miles, 2)
            ELSE NULL
        END                                                                  AS revenue_per_mile,
        COALESCE(DA.total_delivery_events, 0)                                AS total_delivery_events,
        COALESCE(DA.on_time_deliveries, 0)                                   AS on_time_deliveries,
        COALESCE(DA.late_deliveries, 0)                                      AS late_deliveries,
        CASE
            WHEN COALESCE(DA.total_delivery_events, 0) > 0
            THEN ROUND(100.0 * DA.on_time_deliveries / DA.total_delivery_events, 2)
            ELSE NULL
        END                                                                  AS on_time_delivery_pct,
        CASE
            WHEN COALESCE(DA.total_delivery_events, 0) > 0
            THEN ROUND(DA.total_detention_minutes / DA.total_delivery_events, 2)
            ELSE NULL
        END                                                                  AS avg_detention_minutes
    FROM routes AS R
    LEFT JOIN load_agg AS LA
        ON LA.route_id = R.route_id
    LEFT JOIN delivery_agg AS DA
        ON DA.route_id = R.route_id
    WHERE
        (p_origin_state      IS NULL OR R.origin_state      = p_origin_state)
        AND (p_destination_state IS NULL OR R.destination_state = p_destination_state)
        AND (p_min_loads         IS NULL OR COALESCE(LA.total_loads, 0) >= p_min_loads)
    ORDER BY total_revenue DESC NULLS LAST;

END;
$$;