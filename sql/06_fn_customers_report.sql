-- =====================================================================
-- Function: fn_customers_report
-- Purpose : Customer-level performance report combining customer
--           master data with load volume, revenue, and delivery
--           performance metrics, optionally scoped to a date window.
--
-- Parameters (all optional — pass NULL or omit to skip a filter):
--   p_start_date      DATE     - Only include loads on/after this date.
--                                 NULL = no lower bound.
--   p_end_date        DATE     - Only include loads on/before this date.
--                                 NULL = no upper bound.
--   p_customer_type   VARCHAR  - Restrict to one customers.customer_type
--                                 value (e.g. 'Contract', 'Spot').
--                                 NULL = include all types.
--   p_account_status  VARCHAR  - Restrict to one customers.account_status
--                                 value (e.g. 'Active', 'Inactive').
--                                 NULL = include all statuses.
--   p_min_revenue     NUMERIC  - Only return customers whose total
--                                 revenue within the window is >= this
--                                 amount. NULL = no minimum.
--
-- Output  : one row per customer that matches the filters, with
--           aggregated load/revenue/delivery metrics for that window.
--           A customer with zero loads in the window still appears,
--           with 0 / NULL metric values (LEFT JOIN, not INNER JOIN).
--
-- How to call it:
--   -- 1) Everything, no filters — full customer base, full history
--   SELECT * FROM fn_customers_report();
--
--   -- 2) Scope to a specific year
--   SELECT * FROM fn_customers_report('2023-01-01', '2023-12-31');
--
--   -- 3) Only active customers, any date
--   SELECT * FROM fn_customers_report(NULL, NULL, NULL, 'Active');
--
--   -- 4) Active "Contract" customers in 2024 doing at least $50k revenue
--   SELECT * FROM fn_customers_report(
--       '2024-01-01', '2024-12-31', 'Contract', 'Active', 50000
--   );
--
--   -- 5) Top 10 customers by revenue, all-time
--   SELECT * FROM fn_customers_report()
--   ORDER BY total_revenue DESC
--   LIMIT 10;
--
-- Notes:
--   * Parameters are positional in the order shown above, but can also
--     be called with named arguments, e.g.:
--       SELECT * FROM fn_customers_report(p_account_status => 'Active');
--   * on_time_delivery_pct is NULL (not 0) for customers with zero
--     delivery_events rows in the window, so you can tell "no data"
--     apart from "0% on-time" in reporting/BI tools.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_customers_report(
    p_start_date       DATE    DEFAULT NULL,
    p_end_date         DATE    DEFAULT NULL,
    p_customer_type    VARCHAR DEFAULT NULL,
    p_account_status   VARCHAR DEFAULT NULL,
    p_min_revenue      NUMERIC DEFAULT NULL
)
RETURNS TABLE(
    customer_id                         VARCHAR,
    customer_name                       VARCHAR,
    customer_type                       VARCHAR,
    account_status                      VARCHAR,
    primary_freight_type                VARCHAR,
    credit_terms_days                   BIGINT,
    contract_start_date                 DATE,
    annual_revenue_potential            BIGINT,
    total_loads                         BIGINT,
    total_weight_lbs                    NUMERIC,
    total_revenue                       NUMERIC,
    total_fuel_surcharge                NUMERIC,
    total_accessorial_charges           NUMERIC,
    avg_revenue_per_load                NUMERIC,
    on_time_deliveries                  BIGINT,
    late_deliveries                     BIGINT,
    on_time_delivery_pct                NUMERIC,
    revenue_potential_utilization_pct   NUMERIC
)
LANGUAGE plpgsql
AS $$

DECLARE
    -- NULL means "no bound" — we no longer collapse NULL into a
    -- trailing-12-months default, since that silently excluded all
    -- historical data outside the last year.
    v_start_date    DATE := p_start_date;
    v_end_date      DATE := p_end_date;

BEGIN
    -- Basic input validation (only meaningful when both bounds are given)
    IF v_start_date IS NOT NULL AND v_end_date IS NOT NULL AND v_start_date > v_end_date THEN
        RAISE EXCEPTION 'p_start_date (%) cannot be after p_end_date (%)', v_start_date, v_end_date;
    END IF;

    IF p_min_revenue IS NOT NULL AND p_min_revenue < 0 THEN
        RAISE EXCEPTION 'p_min_revenue cannot be negative (got %)', p_min_revenue;
    END IF;

    RETURN QUERY

    SELECT
        C.customer_id,
        C.customer_name,
        C.customer_type,
        C.account_status,
        C.primary_freight_type,
        C.credit_terms_days,
        C.contract_start_date,
        C.annual_revenue_potential,
        COUNT(DISTINCT L.load_id)                                            AS total_loads,
        COALESCE(SUM(L.weight_lbs), 0)                                       AS total_weight_lbs,
        COALESCE(SUM(L.revenue), 0)                                          AS total_revenue,
        COALESCE(SUM(L.fuel_surcharge), 0)                                   AS total_fuel_surcharge,
        COALESCE(SUM(L.accessorial_charges), 0)                              AS total_accessorial_charges,
        CASE
            WHEN COUNT(DISTINCT L.load_id) > 0
            THEN ROUND(COALESCE(SUM(L.revenue), 0) / COUNT(DISTINCT L.load_id), 2)
            ELSE 0
        END                                                                  AS avg_revenue_per_load,
        COUNT(DISTINCT DE.event_id) FILTER (WHERE UPPER(DE.on_time_flag) = 'TRUE')  AS on_time_deliveries,
        COUNT(DISTINCT DE.event_id) FILTER (WHERE UPPER(DE.on_time_flag) = 'FALSE') AS late_deliveries,
        CASE
            WHEN COUNT(DISTINCT DE.event_id) > 0
            THEN ROUND(
                100.0 * COUNT(DISTINCT DE.event_id) FILTER (WHERE UPPER(DE.on_time_flag) = 'TRUE')
                / COUNT(DISTINCT DE.event_id), 2)
            ELSE NULL
        END                                                                  AS on_time_delivery_pct,
        CASE
            WHEN C.annual_revenue_potential > 0
            THEN ROUND(100.0 * COALESCE(SUM(L.revenue), 0) / C.annual_revenue_potential, 2)
            ELSE NULL
        END                                                                  AS revenue_potential_utilization_pct
    FROM customers AS C
    LEFT JOIN loads AS L
        ON L.customer_id = C.customer_id
       AND (v_start_date IS NULL OR L.load_date >= v_start_date)
       AND (v_end_date   IS NULL OR L.load_date <= v_end_date)
    LEFT JOIN delivery_events AS DE
        ON DE.load_id = L.load_id
    WHERE
        (p_customer_type IS NULL OR C.customer_type = p_customer_type)
        AND (p_account_status IS NULL OR C.account_status = p_account_status)
    GROUP BY
        C.customer_id,
        C.customer_name,
        C.customer_type,
        C.account_status,
        C.primary_freight_type,
        C.credit_terms_days,
        C.contract_start_date,
        C.annual_revenue_potential
    HAVING (
        p_min_revenue IS NULL OR COALESCE(SUM(L.revenue), 0) >= p_min_revenue
    )
    ORDER BY total_revenue DESC NULLS LAST;

END;
$$;