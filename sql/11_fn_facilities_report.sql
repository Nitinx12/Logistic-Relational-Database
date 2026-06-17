-- =====================================================================
-- Function: fn_facilities_report
-- Purpose : Facility-level dock and detention performance report,
--           combining facility master data (dock doors, type, location)
--           with delivery_events activity, optionally scoped to a date
--           window.
--
-- Date filtering note: a delivery event may not have happened yet
-- (actual_datetime IS NULL for future-scheduled events), so the date
-- window filters on COALESCE(actual_datetime, scheduled_datetime) —
-- i.e. "when it actually happened, or when it was scheduled to happen
-- if it hasn't yet" — rather than dropping unfulfilled events entirely.
--
-- Parameters (all optional — pass NULL or omit to skip a filter):
--   p_start_date     DATE     - Only include delivery events on/after
--                                this date. NULL = no lower bound.
--   p_end_date       DATE     - Only include delivery events on/before
--                                this date. NULL = no upper bound.
--   p_facility_type  VARCHAR  - Restrict to one facilities.facility_type
--                                value (e.g. 'Distribution Center').
--                                Case-sensitive exact match. NULL = all
--                                types.
--   p_state          VARCHAR  - Restrict to one facilities.state value
--                                (2-letter code). NULL = all states.
--   p_min_events     BIGINT   - Only return facilities with at least
--                                this many delivery events in the
--                                window. NULL = no minimum.
--
-- Output  : one row per facility matching the filters. Facilities with
--           no delivery events in the window still appear (via LEFT
--           JOIN), with 0 / NULL metric values rather than being
--           dropped.
--
-- How to call it:
--   -- 1) Everything, no filters — every facility, full history
--   SELECT * FROM fn_facilities_report();
--
--   -- 2) Scope to a specific year
--   SELECT * FROM fn_facilities_report('2023-01-01', '2023-12-31');
--
--   -- 3) Only Distribution Centers
--   SELECT * FROM fn_facilities_report(NULL, NULL, 'Distribution Center');
--
--   -- 4) Texas facilities in 2024 with at least 50 events
--   SELECT * FROM fn_facilities_report(
--       '2024-01-01', '2024-12-31', NULL, 'TX', 50
--   );
--
--   -- 5) Worst dock congestion relative to capacity
--   SELECT * FROM fn_facilities_report()
--   WHERE total_events > 0
--   ORDER BY detention_minutes_per_dock_door DESC;
--
-- Notes:
--   * on_time_flag is character varying and compared case-insensitively
--     via UPPER(...) = 'TRUE'/'FALSE', consistent with the other
--     reports — verify with SELECT DISTINCT on_time_flag FROM
--     delivery_events; if results look off.
--   * events_per_dock_door and detention_minutes_per_dock_door
--     normalize raw activity/detention by each facility's dock_doors
--     count, so a 2-door cross-dock and a 20-door DC can be compared
--     fairly rather than just by raw totals.
--   * Breakdown by event_type (e.g. pickup vs. delivery) was left out
--     since the exact stored values for that column haven't been
--     confirmed yet — run SELECT DISTINCT event_type FROM
--     delivery_events; and this can be added as a follow-up.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_facilities_report(
    p_start_date     DATE    DEFAULT NULL,
    p_end_date       DATE    DEFAULT NULL,
    p_facility_type  VARCHAR DEFAULT NULL,
    p_state          VARCHAR DEFAULT NULL,
    p_min_events     BIGINT  DEFAULT NULL
)
RETURNS TABLE(
    facility_id                       VARCHAR,
    facility_name                     VARCHAR,
    facility_type                     VARCHAR,
    city                              VARCHAR,
    state                             VARCHAR,
    dock_doors                        BIGINT,
    operating_hours                   VARCHAR,
    total_events                      BIGINT,
    distinct_loads                    BIGINT,
    on_time_events                    BIGINT,
    late_events                       BIGINT,
    on_time_pct                       NUMERIC,
    total_detention_minutes           NUMERIC,
    avg_detention_minutes             NUMERIC,
    max_detention_minutes             BIGINT,
    events_per_dock_door              NUMERIC,
    detention_minutes_per_dock_door   NUMERIC
)
LANGUAGE plpgsql
AS $$

DECLARE
    -- NULL means "no bound" — never collapsed into a default window.
    v_start_date DATE := p_start_date;
    v_end_date   DATE := p_end_date;

BEGIN
    IF v_start_date IS NOT NULL 
        AND v_end_date IS NOT NULL 
        AND v_start_date > v_end_date THEN
            RAISE EXCEPTION 
                'p_start_date (%) cannot be after p_end_date (%)', 
                 v_start_date, 
                 v_end_date;
    END IF;

    IF p_min_events IS NOT NULL 
        AND p_min_events < 0 THEN
            RAISE EXCEPTION 
                'p_min_events cannot be negative (got %)', 
                 p_min_events;
    END IF;

    RETURN QUERY

    WITH event_agg AS (
        SELECT
            DE.facility_id,
            COUNT(DISTINCT DE.event_id)                                                 AS total_events,
            COUNT(DISTINCT DE.load_id)                                                  AS distinct_loads,
            COUNT(DISTINCT DE.event_id) 
                FILTER (WHERE UPPER(DE.on_time_flag) = 'TRUE')                          AS on_time_events,
            COUNT(DISTINCT DE.event_id) 
                FILTER (WHERE UPPER(DE.on_time_flag) = 'FALSE')                         AS late_events,
            COALESCE(SUM(DE.detention_minutes), 0)                                      AS total_detention_minutes,
            COALESCE(MAX(DE.detention_minutes), 0)                                      AS max_detention_minutes
        FROM delivery_events AS DE
        WHERE 
            (v_start_date IS NULL OR COALESCE(DE.actual_datetime, DE.scheduled_datetime)::DATE >= v_start_date)
           AND (v_end_date   IS NULL OR COALESCE(DE.actual_datetime, DE.scheduled_datetime)::DATE <= v_end_date)
        GROUP BY DE.facility_id
    )
    SELECT
        F.facility_id,
        F.facility_name,
        F.facility_type,
        F.city,
        F.state,
        F.dock_doors,
        F.operating_hours,
        COALESCE(EA.total_events, 0)                                         AS total_events,
        COALESCE(EA.distinct_loads, 0)                                       AS distinct_loads,
        COALESCE(EA.on_time_events, 0)                                       AS on_time_events,
        COALESCE(EA.late_events, 0)                                          AS late_events,
        CASE
            WHEN COALESCE(EA.total_events, 0) > 0
            THEN ROUND(100.0 * EA.on_time_events / EA.total_events, 2)
            ELSE NULL
        END                                                                  AS on_time_pct,
        COALESCE(EA.total_detention_minutes, 0)                              AS total_detention_minutes,
        CASE
            WHEN COALESCE(EA.total_events, 0) > 0
            THEN ROUND(EA.total_detention_minutes / EA.total_events, 2)
            ELSE NULL
        END                                                                  AS avg_detention_minutes,
        COALESCE(EA.max_detention_minutes, 0)                                AS max_detention_minutes,
        CASE
            WHEN F.dock_doors IS NOT NULL AND F.dock_doors > 0
            THEN ROUND(COALESCE(EA.total_events, 0)::NUMERIC / F.dock_doors, 2)
            ELSE NULL
        END                                                                  AS events_per_dock_door,
        CASE
            WHEN F.dock_doors IS NOT NULL AND F.dock_doors > 0
            THEN ROUND(COALESCE(EA.total_detention_minutes, 0) / F.dock_doors, 2)
            ELSE NULL
        END                                                                  AS detention_minutes_per_dock_door
    FROM facilities AS F
    LEFT JOIN event_agg AS EA
        ON EA.facility_id = F.facility_id
    WHERE
        (p_facility_type IS NULL OR F.facility_type = p_facility_type)
        AND (p_state         IS NULL OR F.state         = p_state)
        AND (p_min_events    IS NULL OR COALESCE(EA.total_events, 0) >= p_min_events)
    ORDER BY total_detention_minutes DESC NULLS LAST;

END;
$$;