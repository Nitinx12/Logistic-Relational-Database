-- ================================================================
--  OPERATIONAL FEEDBACK LOOP  –  Trucking & Logistics
--
--  HOW IT WORKS:
--  1. Creates two support tables: operational_alerts & kpi_thresholds
--  2. Individual CHECK procedures per domain (driver, fleet,
--     safety, delivery, fuel, maintenance)
--  3. One master procedure  run_feedback_loop()  calls them all
--  4. A summary VIEW surfaces open alerts ranked by severity
--
--  RUN:  CALL run_feedback_loop();
--        SELECT * FROM v_open_alerts;
-- ================================================================


-- ────────────────────────────────────────────────────────────────
-- 1.  SUPPORT TABLES
-- ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS kpi_thresholds (
    threshold_id       SERIAL       PRIMARY KEY,
    category           VARCHAR(50),
    kpi_name           VARCHAR(100),
    warning_threshold  NUMERIC,
    critical_threshold NUMERIC,
    direction          VARCHAR(5)   CHECK (direction IN ('ABOVE','BELOW')),
    unit               VARCHAR(20),
    description        TEXT
);

CREATE TABLE IF NOT EXISTS operational_alerts (
    alert_id        SERIAL        PRIMARY KEY,
    alert_category  VARCHAR(50)   NOT NULL,
    alert_level     VARCHAR(20)   NOT NULL CHECK (alert_level IN ('WARNING','CRITICAL')),
    entity_type     VARCHAR(50),
    entity_id       VARCHAR(100),
    entity_name     VARCHAR(200),
    kpi_name        VARCHAR(100),
    kpi_value       NUMERIC,
    threshold_value NUMERIC,
    alert_message   TEXT,
    created_at      TIMESTAMP     DEFAULT NOW(),
    resolved_at     TIMESTAMP,
    is_resolved     BOOLEAN       DEFAULT FALSE
);

-- ────────────────────────────────────────────────────────────────
-- 2.  SEED KPI THRESHOLDS
-- ────────────────────────────────────────────────────────────────

INSERT INTO kpi_thresholds
      (category, kpi_name, warning_threshold, critical_threshold, direction, unit, description)
VALUES
  ('DRIVER',      'on_time_delivery_rate',   85,    75,    'BELOW', '%',    'Monthly on-time delivery rate per driver'),
  ('DRIVER',      'average_mpg',             6.0,   5.5,   'BELOW', 'mpg',  'Monthly average fuel efficiency per driver'),
  ('DRIVER',      'average_idle_hours',      3.0,   5.0,   'ABOVE', 'hrs',  'Monthly average idle hours per driver'),
  ('FLEET',       'utilization_rate',        70,    50,    'BELOW', '%',    'Monthly truck utilization rate'),
  ('FLEET',       'maintenance_cost_ratio',  15,    25,    'ABOVE', '%',    'Maintenance cost as % of revenue'),
  ('FLEET',       'downtime_hours',          24,    48,    'ABOVE', 'hrs',  'Total downtime hours in period'),
  ('SAFETY',      'incident_count_90d',      1,     3,     'ABOVE', 'cnt',  'Safety incidents per driver in last 90 days'),
  ('SAFETY',      'preventable_ratio',       25,    50,    'ABOVE', '%',    '% of incidents flagged preventable'),
  ('DELIVERY',    'avg_detention_minutes',   60,    120,   'ABOVE', 'min',  'Average detention at a facility'),
  ('DELIVERY',    'facility_on_time_rate',   90,    80,    'BELOW', '%',    'On-time delivery rate at a facility'),
  ('FUEL',        'price_vs_avg_pct',        5,     10,    'ABOVE', '%',    'Price paid vs fleet monthly average'),
  ('MAINTENANCE', 'event_downtime_hours',    8,     24,    'ABOVE', 'hrs',  'Downtime hours per maintenance event')
ON CONFLICT DO NOTHING;


-- ────────────────────────────────────────────────────────────────
-- 3.  HELPER – log_alert()
--     Inserts a new alert only if no identical open alert exists
--     for the same entity + KPI in the last 24 hours
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION log_alert (
    p_category    VARCHAR,
    p_level       VARCHAR,
    p_entity_type VARCHAR,
    p_entity_id   VARCHAR,
    p_entity_name VARCHAR,
    p_kpi_name    VARCHAR,
    p_kpi_value   NUMERIC,
    p_threshold   NUMERIC,
    p_message     TEXT
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   operational_alerts
        WHERE  entity_id    = p_entity_id
          AND  kpi_name     = p_kpi_name
          AND  is_resolved  = FALSE
          AND  created_at  >= NOW() - INTERVAL '24 hours'
    ) THEN
        INSERT INTO operational_alerts (
            alert_category, alert_level,
            entity_type,    entity_id,  entity_name,
            kpi_name,       kpi_value,  threshold_value,
            alert_message
        ) VALUES (
            p_category,    p_level,
            p_entity_type, p_entity_id, p_entity_name,
            p_kpi_name,    p_kpi_value, p_threshold,
            p_message
        );
    END IF;
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 4.  CHECK PROCEDURE – Drivers
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE check_driver_kpis (p_months_back INT DEFAULT 1)
LANGUAGE plpgsql AS $$
DECLARE
    rec     RECORD;
    v_level VARCHAR(20);
BEGIN
    RAISE NOTICE '[DRIVER] Starting driver KPI checks...';

    FOR rec IN
        SELECT
            d.driver_id,
            d.first_name || ' ' || d.last_name   AS driver_name,
            AVG(m.on_time_delivery_rate)          AS avg_otr,
            AVG(m.average_mpg)                    AS avg_mpg,
            AVG(m.average_idle_hours)             AS avg_idle
        FROM   driver_monthly_metrics m
        JOIN   drivers d ON d.driver_id = m.driver_id
        WHERE  m.month            >= DATE_TRUNC('month', NOW())
                                   - (p_months_back || ' months')::INTERVAL
          AND  d.employment_status = 'Active'
        GROUP  BY d.driver_id, driver_name
    LOOP

        -- ── On-time delivery rate ────────────────────────────
        v_level := CASE
            WHEN rec.avg_otr < 75 THEN 'CRITICAL'
            WHEN rec.avg_otr < 85 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'DRIVER', v_level, 'driver',
                rec.driver_id, rec.driver_name,
                'on_time_delivery_rate',
                ROUND(rec.avg_otr, 1),
                CASE v_level WHEN 'CRITICAL' THEN 75 ELSE 85 END,
                FORMAT('Driver %s on-time rate is %.1f%% (threshold %s%%)',
                       rec.driver_name, rec.avg_otr,
                       CASE v_level WHEN 'CRITICAL' THEN '75' ELSE '85' END)
            );
        END IF;

        -- ── Average MPG ──────────────────────────────────────
        v_level := CASE
            WHEN rec.avg_mpg < 5.5 THEN 'CRITICAL'
            WHEN rec.avg_mpg < 6.0 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'DRIVER', v_level, 'driver',
                rec.driver_id, rec.driver_name,
                'average_mpg',
                ROUND(rec.avg_mpg, 2),
                CASE v_level WHEN 'CRITICAL' THEN 5.5 ELSE 6.0 END,
                FORMAT('Driver %s averaging %.2f MPG (threshold %s MPG)',
                       rec.driver_name, rec.avg_mpg,
                       CASE v_level WHEN 'CRITICAL' THEN '5.5' ELSE '6.0' END)
            );
        END IF;

        -- ── Idle hours ───────────────────────────────────────
        v_level := CASE
            WHEN rec.avg_idle > 5.0 THEN 'CRITICAL'
            WHEN rec.avg_idle > 3.0 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'DRIVER', v_level, 'driver',
                rec.driver_id, rec.driver_name,
                'average_idle_hours',
                ROUND(rec.avg_idle, 1),
                CASE v_level WHEN 'CRITICAL' THEN 5.0 ELSE 3.0 END,
                FORMAT('Driver %s avg idle %.1f hrs (threshold %s hrs)',
                       rec.driver_name, rec.avg_idle,
                       CASE v_level WHEN 'CRITICAL' THEN '5' ELSE '3' END)
            );
        END IF;

    END LOOP;

    RAISE NOTICE '[DRIVER] Done.';
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 5.  CHECK PROCEDURE – Fleet / Trucks
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE check_fleet_kpis (p_months_back INT DEFAULT 1)
LANGUAGE plpgsql AS $$
DECLARE
    rec          RECORD;
    v_level      VARCHAR(20);
    v_cost_ratio NUMERIC;
BEGIN
    RAISE NOTICE '[FLEET] Starting fleet KPI checks...';

    FOR rec IN
        SELECT
            t.truck_id,
            'Unit #' || t.unit_number::TEXT || ' – ' || t.make  AS truck_name,
            AVG(m.utilization_rate)   AS avg_util,
            SUM(m.downtime_hours)     AS total_downtime,
            SUM(m.maintenance_cost)   AS total_maint,
            SUM(m.total_revenue)      AS total_rev
        FROM   truck_utilization_metrics m
        JOIN   trucks t ON t.truck_id = m.truck_id
        WHERE  m.month    >= DATE_TRUNC('month', NOW())
                           - (p_months_back || ' months')::INTERVAL
          AND  t.status    = 'Active'
        GROUP  BY t.truck_id, truck_name
    LOOP

        -- ── Utilization rate ─────────────────────────────────
        v_level := CASE
            WHEN rec.avg_util < 50 THEN 'CRITICAL'
            WHEN rec.avg_util < 70 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'FLEET', v_level, 'truck',
                rec.truck_id, rec.truck_name,
                'utilization_rate',
                ROUND(rec.avg_util, 1),
                CASE v_level WHEN 'CRITICAL' THEN 50 ELSE 70 END,
                FORMAT('%s utilization %.1f%% (threshold %s%%)',
                       rec.truck_name, rec.avg_util,
                       CASE v_level WHEN 'CRITICAL' THEN '50' ELSE '70' END)
            );
        END IF;

        -- ── Maintenance cost ratio ───────────────────────────
        IF COALESCE(rec.total_rev, 0) > 0 THEN
            v_cost_ratio := (rec.total_maint / rec.total_rev) * 100;
            v_level := CASE
                WHEN v_cost_ratio > 25 THEN 'CRITICAL'
                WHEN v_cost_ratio > 15 THEN 'WARNING'
                ELSE NULL
            END;
            IF v_level IS NOT NULL THEN
                PERFORM log_alert(
                    'FLEET', v_level, 'truck',
                    rec.truck_id, rec.truck_name,
                    'maintenance_cost_ratio',
                    ROUND(v_cost_ratio, 1),
                    CASE v_level WHEN 'CRITICAL' THEN 25 ELSE 15 END,
                    FORMAT('%s maint cost = %.1f%% of revenue (threshold %s%%)',
                           rec.truck_name, v_cost_ratio,
                           CASE v_level WHEN 'CRITICAL' THEN '25' ELSE '15' END)
                );
            END IF;
        END IF;

        -- ── Downtime hours ───────────────────────────────────
        v_level := CASE
            WHEN rec.total_downtime > 48 THEN 'CRITICAL'
            WHEN rec.total_downtime > 24 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'FLEET', v_level, 'truck',
                rec.truck_id, rec.truck_name,
                'downtime_hours',
                rec.total_downtime,
                CASE v_level WHEN 'CRITICAL' THEN 48 ELSE 24 END,
                FORMAT('%s downtime = %s hrs this period (threshold %s hrs)',
                       rec.truck_name, rec.total_downtime,
                       CASE v_level WHEN 'CRITICAL' THEN '48' ELSE '24' END)
            );
        END IF;

    END LOOP;

    RAISE NOTICE '[FLEET] Done.';
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 6.  CHECK PROCEDURE – Safety
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE check_safety_kpis (p_days_back INT DEFAULT 90)
LANGUAGE plpgsql AS $$
DECLARE
    rec     RECORD;
    v_level VARCHAR(20);
BEGIN
    RAISE NOTICE '[SAFETY] Starting safety KPI checks...';

    FOR rec IN
        SELECT
            d.driver_id,
            d.first_name || ' ' || d.last_name                  AS driver_name,
            COUNT(*)                                             AS incident_count,
            ROUND(
                100.0 * COUNT(*) FILTER (WHERE si.preventable_flag = 'Y')
                / NULLIF(COUNT(*), 0), 1
            )                                                    AS preventable_pct
        FROM   safety_incidents si
        JOIN   drivers d ON d.driver_id = si.driver_id
        WHERE  si.incident_date >= CURRENT_DATE - p_days_back
        GROUP  BY d.driver_id, driver_name
        HAVING COUNT(*) > 0
    LOOP

        -- ── Incident count ───────────────────────────────────
        v_level := CASE
            WHEN rec.incident_count >= 3 THEN 'CRITICAL'
            WHEN rec.incident_count >= 1 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'SAFETY', v_level, 'driver',
                rec.driver_id, rec.driver_name,
                'incident_count_90d',
                rec.incident_count,
                CASE v_level WHEN 'CRITICAL' THEN 3 ELSE 1 END,
                FORMAT('Driver %s has %s safety incident(s) in last %s days',
                       rec.driver_name, rec.incident_count, p_days_back)
            );
        END IF;

        -- ── Preventable ratio ────────────────────────────────
        v_level := CASE
            WHEN rec.preventable_pct > 50 THEN 'CRITICAL'
            WHEN rec.preventable_pct > 25 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'SAFETY', v_level, 'driver',
                rec.driver_id, rec.driver_name,
                'preventable_ratio',
                rec.preventable_pct,
                CASE v_level WHEN 'CRITICAL' THEN 50 ELSE 25 END,
                FORMAT('Driver %s preventable incident rate = %.1f%% (threshold %s%%)',
                       rec.driver_name, rec.preventable_pct,
                       CASE v_level WHEN 'CRITICAL' THEN '50' ELSE '25' END)
            );
        END IF;

    END LOOP;

    RAISE NOTICE '[SAFETY] Done.';
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 7.  CHECK PROCEDURE – Delivery / Facilities
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE check_delivery_kpis (p_days_back INT DEFAULT 30)
LANGUAGE plpgsql AS $$
DECLARE
    rec     RECORD;
    v_level VARCHAR(20);
BEGIN
    RAISE NOTICE '[DELIVERY] Starting delivery KPI checks...';

    FOR rec IN
        SELECT
            de.facility_id,
            COALESCE(f.facility_name, de.facility_id)           AS facility_name,
            AVG(de.detention_minutes)                           AS avg_detention,
            ROUND(
                100.0 * COUNT(*) FILTER (WHERE de.on_time_flag = 'Y')
                / NULLIF(COUNT(*), 0), 1
            )                                                   AS on_time_pct
        FROM   delivery_events de
        LEFT   JOIN facilities f ON f.facility_id = de.facility_id
        WHERE  de.scheduled_datetime >= NOW() - (p_days_back || ' days')::INTERVAL
        GROUP  BY de.facility_id, facility_name
    LOOP

        -- ── Average detention ────────────────────────────────
        v_level := CASE
            WHEN rec.avg_detention > 120 THEN 'CRITICAL'
            WHEN rec.avg_detention > 60  THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'DELIVERY', v_level, 'facility',
                rec.facility_id, rec.facility_name,
                'avg_detention_minutes',
                ROUND(rec.avg_detention, 0),
                CASE v_level WHEN 'CRITICAL' THEN 120 ELSE 60 END,
                FORMAT('Facility "%s" avg detention = %s min (threshold %s min)',
                       rec.facility_name, ROUND(rec.avg_detention),
                       CASE v_level WHEN 'CRITICAL' THEN '120' ELSE '60' END)
            );
        END IF;

        -- ── On-time delivery rate ────────────────────────────
        v_level := CASE
            WHEN rec.on_time_pct < 80 THEN 'CRITICAL'
            WHEN rec.on_time_pct < 90 THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'DELIVERY', v_level, 'facility',
                rec.facility_id, rec.facility_name,
                'facility_on_time_rate',
                rec.on_time_pct,
                CASE v_level WHEN 'CRITICAL' THEN 80 ELSE 90 END,
                FORMAT('Facility "%s" on-time rate = %.1f%% (threshold %s%%)',
                       rec.facility_name, rec.on_time_pct,
                       CASE v_level WHEN 'CRITICAL' THEN '80' ELSE '90' END)
            );
        END IF;

    END LOOP;

    RAISE NOTICE '[DELIVERY] Done.';
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 8.  CHECK PROCEDURE – Fuel
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE check_fuel_kpis (p_days_back INT DEFAULT 30)
LANGUAGE plpgsql AS $$
DECLARE
    rec          RECORD;
    v_fleet_avg  NUMERIC;
    v_pct_above  NUMERIC;
    v_level      VARCHAR(20);
BEGIN
    RAISE NOTICE '[FUEL] Starting fuel KPI checks...';

    -- Fleet-wide average price per gallon this period
    SELECT AVG(price_per_gallon)
    INTO   v_fleet_avg
    FROM   fuel_purchases
    WHERE  purchase_date >= CURRENT_DATE - p_days_back;

    IF v_fleet_avg IS NULL OR v_fleet_avg = 0 THEN
        RAISE NOTICE '[FUEL] No fuel data found – skipping.';
        RETURN;
    END IF;

    FOR rec IN
        SELECT
            fp.driver_id,
            d.first_name || ' ' || d.last_name  AS driver_name,
            AVG(fp.price_per_gallon)             AS avg_price,
            SUM(fp.total_cost)                   AS total_spend,
            COUNT(*)                             AS purchase_count
        FROM   fuel_purchases fp
        JOIN   drivers d ON d.driver_id = fp.driver_id
        WHERE  fp.purchase_date >= CURRENT_DATE - p_days_back
        GROUP  BY fp.driver_id, driver_name
        HAVING COUNT(*) >= 3          -- only flag drivers with meaningful sample
    LOOP
        v_pct_above := ((rec.avg_price - v_fleet_avg) / v_fleet_avg) * 100;

        v_level := CASE
            WHEN v_pct_above > 10 THEN 'CRITICAL'
            WHEN v_pct_above > 5  THEN 'WARNING'
            ELSE NULL
        END;

        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'FUEL', v_level, 'driver',
                rec.driver_id, rec.driver_name,
                'price_vs_avg_pct',
                ROUND(v_pct_above, 1),
                CASE v_level WHEN 'CRITICAL' THEN 10 ELSE 5 END,
                FORMAT('Driver %s paying $%.3f/gal = %.1f%% above fleet avg $%.3f (threshold %s%%)',
                       rec.driver_name, rec.avg_price, v_pct_above, v_fleet_avg,
                       CASE v_level WHEN 'CRITICAL' THEN '10' ELSE '5' END)
            );
        END IF;
    END LOOP;

    RAISE NOTICE '[FUEL] Done.';
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 9.  CHECK PROCEDURE – Maintenance
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE check_maintenance_kpis (p_days_back INT DEFAULT 30)
LANGUAGE plpgsql AS $$
DECLARE
    rec     RECORD;
    v_level VARCHAR(20);
BEGIN
    RAISE NOTICE '[MAINTENANCE] Starting maintenance KPI checks...';

    FOR rec IN
        SELECT
            mr.truck_id,
            'Unit #' || t.unit_number::TEXT || ' – ' || t.make  AS truck_name,
            mr.maintenance_id,
            mr.maintenance_type,
            mr.downtime_hours,
            mr.total_cost,
            mr.maintenance_date
        FROM   maintenance_records mr
        JOIN   trucks t ON t.truck_id = mr.truck_id
        WHERE  mr.maintenance_date >= CURRENT_DATE - p_days_back
    LOOP

        -- ── Per-event downtime ───────────────────────────────
        v_level := CASE
            WHEN rec.downtime_hours > 24 THEN 'CRITICAL'
            WHEN rec.downtime_hours > 8  THEN 'WARNING'
            ELSE NULL
        END;
        IF v_level IS NOT NULL THEN
            PERFORM log_alert(
                'MAINTENANCE', v_level, 'truck',
                rec.truck_id, rec.truck_name,
                'event_downtime_hours',
                rec.downtime_hours,
                CASE v_level WHEN 'CRITICAL' THEN 24 ELSE 8 END,
                FORMAT('%s – %s event on %s caused %s hrs downtime (threshold %s hrs)',
                       rec.truck_name, rec.maintenance_type,
                       rec.maintenance_date, rec.downtime_hours,
                       CASE v_level WHEN 'CRITICAL' THEN '24' ELSE '8' END)
            );
        END IF;

    END LOOP;

    RAISE NOTICE '[MAINTENANCE] Done.';
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 10. MASTER PROCEDURE – run_feedback_loop()
--     Calls every domain check in sequence
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE PROCEDURE run_feedback_loop (
    p_months_back      INT DEFAULT 1,
    p_safety_days      INT DEFAULT 90,
    p_delivery_days    INT DEFAULT 30,
    p_fuel_days        INT DEFAULT 30,
    p_maintenance_days INT DEFAULT 30
)
LANGUAGE plpgsql AS $$
DECLARE
    v_start      TIMESTAMP := NOW();
    v_alert_cnt  INT;
BEGIN
    RAISE NOTICE '=================================================';
    RAISE NOTICE ' OPERATIONAL FEEDBACK LOOP – started at %', v_start;
    RAISE NOTICE '=================================================';

    CALL check_driver_kpis      (p_months_back);
    CALL check_fleet_kpis       (p_months_back);
    CALL check_safety_kpis      (p_safety_days);
    CALL check_delivery_kpis    (p_delivery_days);
    CALL check_fuel_kpis        (p_fuel_days);
    CALL check_maintenance_kpis (p_maintenance_days);

    SELECT COUNT(*) INTO v_alert_cnt
    FROM   operational_alerts
    WHERE  is_resolved = FALSE;

    RAISE NOTICE '=================================================';
    RAISE NOTICE ' Loop complete in % ms  |  Open alerts: %',
                 EXTRACT(MILLISECOND FROM NOW() - v_start)::INT,
                 v_alert_cnt;
    RAISE NOTICE '=================================================';
END;
$$;


-- ────────────────────────────────────────────────────────────────
-- 11. SUMMARY VIEW  –  v_open_alerts
--     Shows all unresolved alerts, most severe first
-- ────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_open_alerts AS
SELECT
    alert_id,
    alert_level,
    alert_category,
    entity_type,
    entity_name,
    kpi_name,
    kpi_value,
    threshold_value,
    alert_message,
    created_at,
    EXTRACT(HOUR FROM NOW() - created_at)::INT AS age_hours
FROM   operational_alerts
WHERE  is_resolved = FALSE
ORDER  BY
    CASE alert_level WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 END,
    alert_category,
    created_at DESC;


-- ────────────────────────────────────────────────────────────────
-- 12. OPTIONAL – auto-schedule with pg_cron (uncomment to use)
--     Runs the full loop every day at 06:00
-- ────────────────────────────────────────────────────────────────
-- SELECT cron.schedule(
--     'daily_feedback_loop',
--     '0 6 * * *',
--     $$ CALL run_feedback_loop(); $$
-- );


-- ────────────────────────────────────────────────────────────────
-- USAGE
--
--  Run loop:
--      CALL run_feedback_loop();
--
--  View open alerts:
--      SELECT * FROM v_open_alerts;
--
--  Resolve an alert:
--      UPDATE operational_alerts
--      SET is_resolved = TRUE, resolved_at = NOW()
--      WHERE alert_id = <id>;
--
--  Resolve all for an entity:
--      UPDATE operational_alerts
--      SET is_resolved = TRUE, resolved_at = NOW()
--      WHERE entity_id = '<driver_id>' AND is_resolved = FALSE;
--
--  Tune a threshold:
--      UPDATE kpi_thresholds
--      SET warning_threshold = 80
--      WHERE kpi_name = 'on_time_delivery_rate';
-- ────────────────────────────────────────────────────────────────gi