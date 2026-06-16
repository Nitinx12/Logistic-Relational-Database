-- ============================================================
--  FUNCTION: get_customer_report
--  Returns a full JSONB report for one customer.
--
--  Parameters:
--    p_customer_id  VARCHAR  – required, target customer
--    p_start_date   DATE     – optional, defaults to contract_start_date
--    p_end_date     DATE     – optional, defaults to CURRENT_DATE
--
--  Usage examples:
--    SELECT get_customer_report('CUST-001');
--    SELECT get_customer_report('CUST-001', '2024-01-01', '2024-12-31');
-- ============================================================

CREATE OR REPLACE FUNCTION get_customer_report(
    p_customer_id  VARCHAR,
    p_start_date   DATE    DEFAULT NULL,
    p_end_date     DATE    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    -- ── customer ──────────────────────────────────────────
    v_customer              RECORD;

    -- ── resolved date window ──────────────────────────────
    v_start_date            DATE;
    v_end_date              DATE;

    -- ── financial summary ─────────────────────────────────
    v_total_loads           INTEGER;
    v_total_revenue         NUMERIC;
    v_total_fuel_surcharge  NUMERIC;
    v_total_accessorial     NUMERIC;
    v_total_weight          BIGINT;
    v_total_pieces          BIGINT;
    v_avg_revenue_per_load  NUMERIC;

    -- ── load-type breakdown ───────────────────────────────
    v_load_type_breakdown   JSONB;

    -- ── load-status breakdown ─────────────────────────────
    v_load_status_breakdown JSONB;

    -- ── delivery performance ──────────────────────────────
    v_on_time_rate          NUMERIC;
    v_total_detention_min   BIGINT;
    v_avg_detention_min     NUMERIC;
    v_late_deliveries       INTEGER;
    v_total_deliveries      INTEGER;

    -- ── top routes ────────────────────────────────────────
    v_top_routes            JSONB;

    -- ── trip / operational metrics ────────────────────────
    v_total_trips           INTEGER;
    v_total_distance        BIGINT;
    v_avg_mpg               NUMERIC;
    v_total_fuel_gallons    NUMERIC;
    v_avg_idle_hours        NUMERIC;

    -- ── safety ────────────────────────────────────────────
    v_safety_summary        JSONB;

    -- ── monthly revenue trend ─────────────────────────────
    v_monthly_trend         JSONB;

    -- ── final output ──────────────────────────────────────
    v_report                JSONB;

BEGIN

    -- ════════════════════════════════════════════════════════
    --  1. INPUT VALIDATION
    -- ════════════════════════════════════════════════════════

    -- 1a. customer_id must be supplied and non-blank
    IF p_customer_id IS NULL OR TRIM(p_customer_id) = '' THEN
        RAISE EXCEPTION 'customer_id cannot be NULL or empty.'
            USING ERRCODE = 'invalid_parameter_value',
                  HINT    = 'Pass a valid customer_id string, e.g. ''CUST-001''.';
    END IF;

    -- 1b. future end_date is meaningless for a historical report
    IF p_end_date IS NOT NULL AND p_end_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'p_end_date (%) is in the future. Maximum allowed value is today (%).',
                        p_end_date, CURRENT_DATE
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- 1c. start must precede end when both are provided
    IF p_start_date IS NOT NULL
       AND p_end_date IS NOT NULL
       AND p_start_date > p_end_date THEN
        RAISE EXCEPTION 'p_start_date (%) must not be after p_end_date (%).',
                        p_start_date, p_end_date
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- ════════════════════════════════════════════════════════
    --  2. FETCH CUSTOMER — raise clearly if missing
    -- ════════════════════════════════════════════════════════

    SELECT * INTO STRICT v_customer
    FROM   customers
    WHERE  customer_id = p_customer_id;

    -- ════════════════════════════════════════════════════════
    --  3. RESOLVE DATE WINDOW
    -- ════════════════════════════════════════════════════════

    -- Default start  → contract start date (or epoch fallback)
    v_start_date := COALESCE(p_start_date,
                             v_customer.contract_start_date,
                             '2000-01-01'::DATE);

    -- Default end    → today
    v_end_date   := COALESCE(p_end_date, CURRENT_DATE);

    -- Sanity-check resolved window (e.g. contract_start_date in future)
    IF v_start_date > v_end_date THEN
        RAISE EXCEPTION
            'Resolved date window is invalid: start=% is after end=%. '
            'Check the customer contract_start_date or supply explicit dates.',
            v_start_date, v_end_date
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Soft warning for inactive accounts
    IF v_customer.account_status NOT IN ('active', 'Active', 'ACTIVE') THEN
        RAISE WARNING 'Customer "%" (ID: %) has account_status = "%". '
                      'Report data may be limited.',
                      v_customer.customer_name,
                      p_customer_id,
                      v_customer.account_status;
    END IF;

    -- ════════════════════════════════════════════════════════
    --  4. FINANCIAL SUMMARY
    -- ════════════════════════════════════════════════════════

    SELECT
        COUNT(*)::INTEGER,
        COALESCE(SUM(revenue),              0),
        COALESCE(SUM(fuel_surcharge),       0),
        COALESCE(SUM(accessorial_charges),  0),
        COALESCE(SUM(weight_lbs),           0),
        COALESCE(SUM(pieces),               0),
        COALESCE(AVG(revenue),              0)
    INTO
        v_total_loads,
        v_total_revenue,
        v_total_fuel_surcharge,
        v_total_accessorial,
        v_total_weight,
        v_total_pieces,
        v_avg_revenue_per_load
    FROM  loads
    WHERE customer_id = p_customer_id
      AND load_date  BETWEEN v_start_date AND v_end_date;

    -- ════════════════════════════════════════════════════════
    --  5. LOAD-TYPE BREAKDOWN
    -- ════════════════════════════════════════════════════════

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'load_type',           load_type,
                'load_count',          cnt,
                'total_revenue',       ROUND(total_rev, 2),
                'avg_revenue',         ROUND(avg_rev,   2),
                'pct_of_total_loads',  ROUND(cnt::NUMERIC / NULLIF(v_total_loads, 0) * 100, 2)
            )
            ORDER BY cnt DESC
        ),
        '[]'::JSONB
    )
    INTO v_load_type_breakdown
    FROM (
        SELECT load_type,
               COUNT(*)     AS cnt,
               SUM(revenue) AS total_rev,
               AVG(revenue) AS avg_rev
        FROM   loads
        WHERE  customer_id = p_customer_id
          AND  load_date   BETWEEN v_start_date AND v_end_date
        GROUP  BY load_type
    ) lt;

    -- ════════════════════════════════════════════════════════
    --  6. LOAD-STATUS BREAKDOWN
    -- ════════════════════════════════════════════════════════

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'status',        load_status,
                'count',         cnt,
                'total_revenue', ROUND(total_rev, 2)
            )
            ORDER BY cnt DESC
        ),
        '[]'::JSONB
    )
    INTO v_load_status_breakdown
    FROM (
        SELECT load_status,
               COUNT(*)     AS cnt,
               SUM(revenue) AS total_rev
        FROM   loads
        WHERE  customer_id = p_customer_id
          AND  load_date   BETWEEN v_start_date AND v_end_date
        GROUP  BY load_status
    ) ls;

    -- ════════════════════════════════════════════════════════
    --  7. DELIVERY PERFORMANCE
    -- ════════════════════════════════════════════════════════

    SELECT
        COUNT(*)::INTEGER,
        COUNT(*) FILTER (WHERE de.on_time_flag = 'Y')::INTEGER,
        COUNT(*) FILTER (WHERE de.on_time_flag = 'N')::INTEGER,
        ROUND(
            COUNT(*) FILTER (WHERE de.on_time_flag = 'Y')::NUMERIC
            / NULLIF(COUNT(*), 0) * 100, 2
        ),
        COALESCE(SUM(de.detention_minutes),  0),
        COALESCE(ROUND(AVG(de.detention_minutes), 2), 0)
    INTO
        v_total_deliveries,
        v_on_time_rate,       -- reused as on-time count temporarily
        v_late_deliveries,
        v_on_time_rate,
        v_total_detention_min,
        v_avg_detention_min
    FROM  delivery_events de
    JOIN  loads           l  ON de.load_id = l.load_id
    WHERE l.customer_id  = p_customer_id
      AND l.load_date    BETWEEN v_start_date AND v_end_date
      AND de.event_type  = 'DELIVERY';

    -- ════════════════════════════════════════════════════════
    --  8. TOP 5 ROUTES
    -- ════════════════════════════════════════════════════════

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'route',                  origin_city || ', ' || origin_state
                                          || ' → '
                                          || destination_city || ', ' || destination_state,
                'load_count',             load_count,
                'total_revenue',          ROUND(route_revenue, 2),
                'avg_revenue_per_load',   ROUND(avg_route_revenue, 2),
                'typical_distance_miles', route_miles,
                'typical_transit_days',   transit_days
            )
            ORDER BY load_count DESC
        ),
        '[]'::JSONB
    )
    INTO v_top_routes
    FROM (
        SELECT r.origin_city,
               r.origin_state,
               r.destination_city,
               r.destination_state,
               r.typical_distance_miles AS route_miles,
               r.typical_transit_days   AS transit_days,
               COUNT(l.load_id)         AS load_count,
               SUM(l.revenue)           AS route_revenue,
               AVG(l.revenue)           AS avg_route_revenue
        FROM   loads  l
        JOIN   routes r ON l.route_id = r.route_id
        WHERE  l.customer_id = p_customer_id
          AND  l.load_date   BETWEEN v_start_date AND v_end_date
        GROUP  BY r.origin_city, r.origin_state,
                  r.destination_city, r.destination_state,
                  r.typical_distance_miles, r.typical_transit_days
        ORDER  BY load_count DESC
        LIMIT  5
    ) tr;

    -- ════════════════════════════════════════════════════════
    --  9. TRIP / OPERATIONAL METRICS
    -- ════════════════════════════════════════════════════════

    SELECT
        COUNT(DISTINCT t.trip_id)::INTEGER,
        COALESCE(SUM(t.actual_distance_miles), 0),
        COALESCE(ROUND(AVG(t.average_mpg),       2), 0),
        COALESCE(SUM(t.fuel_gallons_used),       0),
        COALESCE(ROUND(AVG(t.idle_time_hours),   2), 0)
    INTO
        v_total_trips,
        v_total_distance,
        v_avg_mpg,
        v_total_fuel_gallons,
        v_avg_idle_hours
    FROM  trips t
    JOIN  loads l ON t.load_id = l.load_id
    WHERE l.customer_id = p_customer_id
      AND l.load_date   BETWEEN v_start_date AND v_end_date;

    -- ════════════════════════════════════════════════════════
    --  10. SAFETY INCIDENTS LINKED TO CUSTOMER LOADS
    -- ════════════════════════════════════════════════════════

    SELECT COALESCE(
        jsonb_build_object(
            'total_incidents',          total_inc,
            'at_fault_incidents',       at_fault,
            'preventable_incidents',    preventable,
            'injury_incidents',         injuries,
            'total_vehicle_damage',     ROUND(COALESCE(veh_dmg, 0),   2),
            'total_cargo_damage',       ROUND(COALESCE(cargo_dmg, 0), 2),
            'total_claim_amount',       ROUND(COALESCE(claims, 0),    2)
        ),
        '{}'::JSONB
    )
    INTO v_safety_summary
    FROM (
        SELECT
            COUNT(*)::INTEGER                                              AS total_inc,
            COUNT(*) FILTER (WHERE si.at_fault_flag     = 'Y')::INTEGER   AS at_fault,
            COUNT(*) FILTER (WHERE si.preventable_flag  = 'Y')::INTEGER   AS preventable,
            COUNT(*) FILTER (WHERE si.injury_flag       = 'Y')::INTEGER   AS injuries,
            SUM(si.vehicle_damage_cost)                                    AS veh_dmg,
            SUM(si.cargo_damage_cost)                                      AS cargo_dmg,
            SUM(si.claim_amount)                                           AS claims
        FROM  safety_incidents si
        JOIN  trips            t  ON si.trip_id   = t.trip_id
        JOIN  loads            l  ON t.load_id    = l.load_id
        WHERE l.customer_id  = p_customer_id
          AND l.load_date    BETWEEN v_start_date AND v_end_date
    ) s;

    -- ════════════════════════════════════════════════════════
    --  11. MONTHLY REVENUE TREND
    -- ════════════════════════════════════════════════════════

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'month',          TO_CHAR(month, 'YYYY-MM'),
                'load_count',     cnt,
                'total_revenue',  ROUND(total_rev, 2),
                'total_weight',   total_wt
            )
            ORDER BY month
        ),
        '[]'::JSONB
    )
    INTO v_monthly_trend
    FROM (
        SELECT DATE_TRUNC('month', load_date) AS month,
               COUNT(*)                        AS cnt,
               SUM(revenue)                    AS total_rev,
               SUM(weight_lbs)                 AS total_wt
        FROM   loads
        WHERE  customer_id = p_customer_id
          AND  load_date   BETWEEN v_start_date AND v_end_date
        GROUP  BY DATE_TRUNC('month', load_date)
    ) mt;

    -- ════════════════════════════════════════════════════════
    --  12. ASSEMBLE FINAL REPORT
    -- ════════════════════════════════════════════════════════

    v_report := jsonb_build_object(

        'report_generated_at', NOW(),

        'report_period', jsonb_build_object(
            'start_date', v_start_date,
            'end_date',   v_end_date
        ),

        -- ── Customer Profile ──────────────────────────────
        'customer_profile', jsonb_build_object(
            'customer_id',               v_customer.customer_id,
            'customer_name',             v_customer.customer_name,
            'customer_type',             v_customer.customer_type,
            'account_status',            v_customer.account_status,
            'primary_freight_type',      v_customer.primary_freight_type,
            'credit_terms_days',         v_customer.credit_terms_days,
            'contract_start_date',       v_customer.contract_start_date,
            'annual_revenue_potential',  v_customer.annual_revenue_potential
        ),

        -- ── Financial Summary ─────────────────────────────
        'financial_summary', jsonb_build_object(
            'total_loads',                 v_total_loads,
            'total_revenue',               ROUND(v_total_revenue, 2),
            'total_fuel_surcharge',        ROUND(v_total_fuel_surcharge, 2),
            'total_accessorial_charges',   v_total_accessorial,
            'grand_total_billed',          ROUND(v_total_revenue
                                               + v_total_fuel_surcharge
                                               + v_total_accessorial, 2),
            'avg_revenue_per_load',        ROUND(v_avg_revenue_per_load, 2),
            'total_weight_lbs',            v_total_weight,
            'total_pieces',                v_total_pieces,
            'revenue_vs_potential_pct',    ROUND(
                                               v_total_revenue
                                               / NULLIF(v_customer.annual_revenue_potential, 0)
                                               * 100, 2
                                           )
        ),

        -- ── Breakdowns ────────────────────────────────────
        'load_type_breakdown',   v_load_type_breakdown,
        'load_status_breakdown', v_load_status_breakdown,

        -- ── Delivery Performance ──────────────────────────
        'delivery_performance', jsonb_build_object(
            'total_delivery_events',          COALESCE(v_total_deliveries,   0),
            'on_time_delivery_rate_pct',      COALESCE(v_on_time_rate,       0),
            'late_deliveries',                COALESCE(v_late_deliveries,    0),
            'total_detention_minutes',        COALESCE(v_total_detention_min, 0),
            'avg_detention_per_stop_minutes', COALESCE(v_avg_detention_min,  0)
        ),

        -- ── Trip / Operational Metrics ────────────────────
        'trip_metrics', jsonb_build_object(
            'total_trips',              COALESCE(v_total_trips,        0),
            'total_distance_miles',     COALESCE(v_total_distance,     0),
            'avg_fuel_efficiency_mpg',  COALESCE(v_avg_mpg,            0),
            'total_fuel_gallons_used',  ROUND(COALESCE(v_total_fuel_gallons, 0), 2),
            'avg_idle_time_hours',      COALESCE(v_avg_idle_hours,     0)
        ),

        -- ── Top Routes ────────────────────────────────────
        'top_routes', v_top_routes,

        -- ── Safety ────────────────────────────────────────
        'safety_summary', v_safety_summary,

        -- ── Monthly Trend ─────────────────────────────────
        'monthly_revenue_trend', v_monthly_trend
    );

    RETURN v_report;

    -- ════════════════════════════════════════════════════════
    --  EXCEPTION HANDLING
    -- ════════════════════════════════════════════════════════

EXCEPTION
    -- Re-raise our own validation errors as-is
    WHEN invalid_parameter_value THEN
        RAISE;

    -- Re-raise NOT FOUND with a clear message
    WHEN NO_DATA_FOUND THEN
        RAISE EXCEPTION 'Customer "%" does not exist in the database.', p_customer_id
            USING ERRCODE = 'no_data_found',
                  HINT    = 'Verify the customer_id and try again.';

    -- Catch-all for unexpected DB errors
    WHEN OTHERS THEN
        RAISE EXCEPTION
            '[get_customer_report] Unexpected error for customer_id="%": % (SQLSTATE: %)',
            p_customer_id, SQLERRM, SQLSTATE
            USING ERRCODE = 'internal_error';

END;
$$;


-- ============================================================
--  QUICK USAGE REFERENCE
-- ============================================================
-- Full report, all time:
--   SELECT get_customer_report('CUST-001');
--
-- Report for a specific year:
--   SELECT get_customer_report('CUST-001', '2024-01-01', '2024-12-31');
--
-- Pretty-print in psql:
--   SELECT jsonb_pretty(get_customer_report('CUST-001'));
--
-- Extract a single section:
--   SELECT get_customer_report('CUST-001') -> 'financial_summary';
-- ============================================================