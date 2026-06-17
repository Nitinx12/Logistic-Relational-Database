-- =====================================================================
-- Function: fn_drivers_report
-- Purpose : Driver-level performance report combining driver master
--           data with trip/revenue/fuel metrics and safety incident
--           history, optionally scoped to a date window.
--
-- Design note: trips and safety_incidents both have a one-to-many
-- relationship with drivers (and incidents can be one-to-many against
-- trips too). To avoid inflating SUMs through join fan-out, trips and
-- incidents are each pre-aggregated per driver in their own CTE
-- *before* being joined onto the driver list — they are never joined
-- directly to each other.
--
-- Parameters (all optional — pass NULL or omit to skip a filter):
--   p_start_date         DATE     - Only include trips (by dispatch_date)
--                                    and incidents (by incident_date)
--                                    on/after this date. NULL = no
--                                    lower bound.
--   p_end_date           DATE     - Only include trips/incidents
--                                    on/before this date. NULL = no
--                                    upper bound.
--   p_employment_status  VARCHAR  - Restrict to one
--                                    drivers.employment_status value
--                                    (e.g. 'Active', 'Terminated').
--                                    NULL = include all statuses.
--   p_home_terminal      VARCHAR  - Restrict to one
--                                    drivers.home_terminal value.
--                                    NULL = include all terminals.
--   p_min_trips          BIGINT   - Only return drivers with at least
--                                    this many trips in the window.
--                                    NULL = no minimum.
--
-- Output  : one row per driver matching the filters. Drivers with no
--           trips or no incidents in the window still appear (via
--           LEFT JOIN), with 0 / NULL metric values rather than being
--           dropped.
--
-- How to call it:
--   -- 1) Everything, no filters — full driver roster, full history
--   SELECT * FROM fn_drivers_report();
--
--   -- 2) Scope to a specific year
--   SELECT * FROM fn_drivers_report('2023-01-01', '2023-12-31');
--
--   -- 3) Only active drivers, any date
--   SELECT * FROM fn_drivers_report(NULL, NULL, 'Active');
--
--   -- 4) Active drivers at a specific terminal with 50+ trips in 2024
--   SELECT * FROM fn_drivers_report(
--       '2024-01-01', '2024-12-31', 'Active', 'Dallas', 50
--   );
--
--   -- 5) Worst safety records: most incidents per 10k miles
--   SELECT * FROM fn_drivers_report()
--   WHERE total_safety_incidents > 0
--   ORDER BY incidents_per_10k_miles DESC;
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_drivers_report(
    p_start_date         DATE    DEFAULT NULL,
    p_end_date           DATE    DEFAULT NULL,
    p_employment_status  VARCHAR DEFAULT NULL,
    p_home_terminal      VARCHAR DEFAULT NULL,
    p_min_trips          BIGINT  DEFAULT NULL
)
RETURNS TABLE(
    driver_id                   VARCHAR,
    first_name                  VARCHAR,
    last_name                   VARCHAR,
    license_state               VARCHAR,
    home_terminal               VARCHAR,
    employment_status           VARCHAR,
    cdl_class                   VARCHAR,
    years_experience            BIGINT,
    hire_date                   DATE,
    termination_date            DATE,
    total_trips                 BIGINT,
    total_miles                 NUMERIC,
    total_revenue               NUMERIC,
    total_fuel_gallons          NUMERIC,
    avg_mpg                     NUMERIC,
    total_idle_hours            NUMERIC,
    avg_revenue_per_trip        NUMERIC,
    avg_revenue_per_mile        NUMERIC,
    total_safety_incidents      BIGINT,
    preventable_incidents       BIGINT,
    at_fault_incidents          BIGINT,
    injury_incidents            BIGINT,
    total_damage_cost           NUMERIC,
    total_claim_amount          NUMERIC,
    incidents_per_10k_miles     NUMERIC
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

    IF p_min_trips IS NOT NULL AND p_min_trips < 0 THEN
        RAISE EXCEPTION 
            'p_min_trips cannot be negative (got %)', 
             p_min_trips;
    END IF;

    RETURN QUERY

    WITH trip_agg AS (
        SELECT
            T.driver_id,
            COUNT(DISTINCT T.trip_id)                       AS total_trips,
            COALESCE(SUM(T.actual_distance_miles), 0)       AS total_miles,
            COALESCE(SUM(T.fuel_gallons_used), 0)            AS total_fuel_gallons,
            COALESCE(SUM(T.idle_time_hours), 0)               AS total_idle_hours,
            COALESCE(SUM(L.revenue), 0)                       AS total_revenue
        FROM trips AS T
        LEFT JOIN loads AS L
            ON L.load_id = T.load_id
        WHERE (v_start_date IS NULL OR T.dispatch_date >= v_start_date)
          AND (v_end_date   IS NULL OR T.dispatch_date <= v_end_date)
        GROUP BY T.driver_id
    ),
    incident_agg AS (
        SELECT
            SI.driver_id,
            COUNT(DISTINCT SI.incident_id)                                                  AS total_incidents,
            COUNT(DISTINCT SI.incident_id) FILTER (WHERE UPPER(SI.preventable_flag) = 'TRUE') AS preventable_incidents,
            COUNT(DISTINCT SI.incident_id) FILTER (WHERE UPPER(SI.at_fault_flag) = 'TRUE')     AS at_fault_incidents,
            COUNT(DISTINCT SI.incident_id) FILTER (WHERE UPPER(SI.injury_flag) = 'TRUE')       AS injury_incidents,
            COALESCE(SUM(SI.vehicle_damage_cost), 0) + COALESCE(SUM(SI.cargo_damage_cost), 0)  AS total_damage_cost,
            COALESCE(SUM(SI.claim_amount), 0)                                                  AS total_claim_amount
        FROM safety_incidents AS SI
        WHERE (v_start_date IS NULL OR SI.incident_date >= v_start_date)
          AND (v_end_date   IS NULL OR SI.incident_date <= v_end_date)
        GROUP BY SI.driver_id
    )
    SELECT
        D.driver_id,
        D.first_name,
        D.last_name,
        D.license_state,
        D.home_terminal,
        D.employment_status,
        D.cdl_class,
        D.years_experience,
        D.hire_date,
        D.termination_date,
        COALESCE(TA.total_trips, 0)                                          AS total_trips,
        COALESCE(TA.total_miles, 0)                                          AS total_miles,
        COALESCE(TA.total_revenue, 0)                                        AS total_revenue,
        COALESCE(TA.total_fuel_gallons, 0)                                   AS total_fuel_gallons,
        CASE
            WHEN COALESCE(TA.total_fuel_gallons, 0) > 0
            THEN ROUND(TA.total_miles / TA.total_fuel_gallons, 2)
            ELSE NULL
        END                                                                  AS avg_mpg,
        COALESCE(TA.total_idle_hours, 0)                                     AS total_idle_hours,
        CASE
            WHEN COALESCE(TA.total_trips, 0) > 0
            THEN ROUND(TA.total_revenue / TA.total_trips, 2)
            ELSE 0
        END                                                                  AS avg_revenue_per_trip,
        CASE
            WHEN COALESCE(TA.total_miles, 0) > 0
            THEN ROUND(TA.total_revenue / TA.total_miles, 2)
            ELSE NULL
        END                                                                  AS avg_revenue_per_mile,
        COALESCE(IA.total_incidents, 0)                                      AS total_safety_incidents,
        COALESCE(IA.preventable_incidents, 0)                                AS preventable_incidents,
        COALESCE(IA.at_fault_incidents, 0)                                   AS at_fault_incidents,
        COALESCE(IA.injury_incidents, 0)                                     AS injury_incidents,
        COALESCE(IA.total_damage_cost, 0)                                    AS total_damage_cost,
        COALESCE(IA.total_claim_amount, 0)                                   AS total_claim_amount,
        CASE
            WHEN COALESCE(TA.total_miles, 0) > 0
            THEN ROUND(COALESCE(IA.total_incidents, 0)::NUMERIC / TA.total_miles * 10000, 4)
            ELSE NULL
        END                                                                  AS incidents_per_10k_miles
    FROM drivers AS D
    LEFT JOIN trip_agg AS TA
        ON TA.driver_id = D.driver_id
    LEFT JOIN incident_agg AS IA
        ON IA.driver_id = D.driver_id
    WHERE
        (p_employment_status IS NULL OR D.employment_status = p_employment_status)
        AND (p_home_terminal IS NULL OR D.home_terminal = p_home_terminal)
        AND (p_min_trips IS NULL OR COALESCE(TA.total_trips, 0) >= p_min_trips)
    ORDER BY total_revenue DESC NULLS LAST;

END;
$$;