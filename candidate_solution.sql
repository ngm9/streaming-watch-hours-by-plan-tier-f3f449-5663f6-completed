-- =============================================================================
-- CANDIDATE SOLUTION FILE  (SQL ONLY)
-- =============================================================================
-- Business goal: a monthly report of watch-hours per plan tier, where each
-- viewing session is credited to the plan tier the subscriber held at the
-- moment the session STARTED. Report grain: one row per (report_month, plan_tier)
-- with total watch-hours and a distinct session count.
--
-- Deliver your corrected, deterministic, and performant SQL below. You may
-- create views, functions, indexes, or any SQL artifacts you judge appropriate.
-- Correctness must not be faked by masking a cardinality defect with a blanket
-- DISTINCT.
--
-- Please record your assumptions as SQL comments (boundary semantics at a
-- plan-change instant, how overlapping / superseded / late-arriving history
-- rows are resolved, treatment of the open-ended current row, and how sessions
-- with no resolvable plan are handled).
-- =============================================================================

-- ASSUMPTIONS (fill in):
--   1.
--   2.
--   3.

-- -----------------------------------------------------------------------------
-- REQUIRED: create or replace the corrected reporting view with this exact
-- name and these exact column names, so the validation suite can check it.
--   view name : v_watch_hours_by_tier
--   columns   : report_month TEXT, plan_tier TEXT,
--               total_watch_hours NUMERIC, session_count BIGINT
-- The view should report for month '2025-01'.
-- -----------------------------------------------------------------------------

-- CREATE OR REPLACE VIEW v_watch_hours_by_tier AS
-- ... your query here ...


-- -----------------------------------------------------------------------------
-- OPTIONAL: any supporting indexes or artifacts for performance.
-- -----------------------------------------------------------------------------


-- -----------------------------------------------------------------------------
-- OPTIONAL: a query returning sessions that have NO resolvable plan at their
-- start time within the report month, so they are visible rather than silently
-- dropped. Name it v_unattributed_sessions with column session_id.
-- -----------------------------------------------------------------------------

-- CREATE OR REPLACE VIEW v_unattributed_sessions AS
-- ... your query here ...
