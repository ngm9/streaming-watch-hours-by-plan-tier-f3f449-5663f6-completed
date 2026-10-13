-- =============================================================================
-- SQL-ONLY VALIDATION SUITE
-- Run AFTER loading candidate_solution.sql.
-- Each check prints a PASS/FAIL row. All checks must PASS.
-- These checks assert observable behaviour only; they do not prescribe HOW.
-- =============================================================================
\pset footer off

-- Guard: the corrected view must exist.
SELECT
    'view_exists' AS check_name,
    CASE WHEN to_regclass('public.v_watch_hours_by_tier') IS NOT NULL
         THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check 1: exactly one row per plan_tier for the report month (no duplicate tier rows).
SELECT
    'one_row_per_tier' AS check_name,
    CASE WHEN NOT EXISTS (
        SELECT 1 FROM v_watch_hours_by_tier
        WHERE report_month = '2025-01'
        GROUP BY report_month, plan_tier
        HAVING COUNT(*) > 1
    ) THEN 'PASS' ELSE 'FAIL' END AS status;

-- Reconciliation reference values, computed independently of the candidate view.
-- Expected in-month sessions that HAVE a resolvable plan at their start time.
WITH resolved AS (
    SELECT DISTINCT ON (vs.session_id)
           vs.session_id
    FROM viewing_sessions vs
    JOIN subscription_plan_history h
           ON h.subscriber_id = vs.subscriber_id
          AND vs.started_at >= h.valid_from
          AND (h.valid_to IS NULL OR vs.started_at < h.valid_to)
    WHERE vs.started_at >= '2025-01-01T00:00:00Z'
      AND vs.started_at <  '2025-02-01T00:00:00Z'
    ORDER BY vs.session_id, h.valid_from DESC, h.recorded_at DESC, h.history_id DESC
)
SELECT
    'reconcile_session_count' AS check_name,
    CASE WHEN (
        SELECT COALESCE(SUM(session_count), 0)
        FROM v_watch_hours_by_tier
        WHERE report_month = '2025-01'
    ) = (SELECT COUNT(*) FROM resolved)
    THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check 3: total session_count must not exceed distinct in-month sessions
-- (i.e. no double counting), and must be positive.
SELECT
    'no_double_count' AS check_name,
    CASE WHEN (
        SELECT COALESCE(SUM(session_count), 0)
        FROM v_watch_hours_by_tier WHERE report_month = '2025-01'
    ) BETWEEN 1 AND (
        SELECT COUNT(*) FROM viewing_sessions
        WHERE started_at >= '2025-01-01T00:00:00Z'
          AND started_at <  '2025-02-01T00:00:00Z'
    )
    THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check 4: December sessions must not leak into the January report.
SELECT
    'no_out_of_month_leak' AS check_name,
    CASE WHEN NOT EXISTS (
        SELECT 1 FROM v_watch_hours_by_tier WHERE report_month <> '2025-01'
    ) THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check 5: subscriber 103's post-downgrade sessions (duplicated history rows)
-- must be counted once each, not twice. Cross-check the total watch hours for
-- the report is stable and matches an independent recomputation.
WITH attribution AS (
    SELECT DISTINCT ON (vs.session_id)
           vs.session_id,
           vs.watch_seconds,
           h.plan_id
    FROM viewing_sessions vs
    JOIN subscription_plan_history h
           ON h.subscriber_id = vs.subscriber_id
          AND vs.started_at >= h.valid_from
          AND (h.valid_to IS NULL OR vs.started_at < h.valid_to)
    WHERE vs.started_at >= '2025-01-01T00:00:00Z'
      AND vs.started_at <  '2025-02-01T00:00:00Z'
    ORDER BY vs.session_id, h.valid_from DESC, h.recorded_at DESC, h.history_id DESC
),
expected AS (
    SELECT ROUND(SUM(watch_seconds) / 3600.0, 4) AS total_hours
    FROM attribution
)
SELECT
    'reconcile_total_hours' AS check_name,
    CASE WHEN ABS(
        (SELECT COALESCE(SUM(total_watch_hours), 0)
         FROM v_watch_hours_by_tier WHERE report_month = '2025-01')
        - (SELECT total_hours FROM expected)
    ) < 0.01
    THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check 6: determinism -- running the view twice yields identical results.
WITH a AS (
    SELECT plan_tier, session_count, ROUND(total_watch_hours,4) AS wh
    FROM v_watch_hours_by_tier WHERE report_month = '2025-01'
),
b AS (
    SELECT plan_tier, session_count, ROUND(total_watch_hours,4) AS wh
    FROM v_watch_hours_by_tier WHERE report_month = '2025-01'
)
SELECT
    'deterministic' AS check_name,
    CASE WHEN NOT EXISTS (
        SELECT plan_tier, session_count, wh FROM a
        EXCEPT
        SELECT plan_tier, session_count, wh FROM b
    ) AND NOT EXISTS (
        SELECT plan_tier, session_count, wh FROM b
        EXCEPT
        SELECT plan_tier, session_count, wh FROM a
    ) THEN 'PASS' ELSE 'FAIL' END AS status;

-- Informational: show the candidate report for manual inspection.
SELECT report_month, plan_tier, ROUND(total_watch_hours,4) AS total_watch_hours, session_count
FROM v_watch_hours_by_tier
WHERE report_month = '2025-01'
ORDER BY plan_tier;
