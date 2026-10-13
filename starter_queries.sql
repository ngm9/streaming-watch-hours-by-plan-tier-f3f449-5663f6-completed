-- =============================================================================
-- DRAFT / CURRENT REPORTING LOGIC (analyst-flagged as unreliable and slow)
-- =============================================================================
-- This is the logic currently serving the monthly watch-hours-by-tier report.
-- Analysts report inflated totals, some sessions credited to the wrong tier,
-- and poor performance at production volume.
--
-- The same definition also exists as the view v_watch_hours_by_tier_draft.
-- Use these queries to observe the current behaviour before writing your
-- corrected logic in candidate_solution.sql. Do NOT treat this as correct.
-- =============================================================================

-- Current report output for January 2025.
SELECT
    to_char(vs.started_at, 'YYYY-MM')        AS report_month,
    p.plan_tier                              AS plan_tier,
    SUM(vs.watch_seconds) / 3600.0           AS total_watch_hours,
    COUNT(vs.session_id)                     AS session_count
FROM viewing_sessions vs
JOIN subscription_plan_history h
       ON h.subscriber_id = vs.subscriber_id
      AND vs.started_at >= h.valid_from
      AND (vs.started_at <= h.valid_to OR h.valid_to IS NULL)
JOIN plans p
       ON p.plan_id = h.plan_id
WHERE to_char(vs.started_at, 'YYYY-MM') = '2025-01'
GROUP BY 1, 2
ORDER BY plan_tier;

-- Sanity reference: how many distinct sessions actually started in Jan 2025?
-- Compare this against the SUM of session_count above.
SELECT COUNT(*) AS distinct_january_sessions
FROM viewing_sessions
WHERE to_char(started_at, 'YYYY-MM') = '2025-01';

-- Inspect a subscriber who changed plans mid-month to see per-session behaviour.
SELECT vs.session_id, vs.started_at, h.history_id, h.plan_id, h.valid_from, h.valid_to
FROM viewing_sessions vs
JOIN subscription_plan_history h
       ON h.subscriber_id = vs.subscriber_id
      AND vs.started_at >= h.valid_from
      AND (vs.started_at <= h.valid_to OR h.valid_to IS NULL)
WHERE vs.subscriber_id = 103
ORDER BY vs.started_at, h.history_id;

-- Review the raw plan history for subscribers with tricky timelines.
SELECT * FROM subscription_plan_history
WHERE subscriber_id IN (102, 103, 104, 105, 106, 108)
ORDER BY subscriber_id, valid_from, history_id;
