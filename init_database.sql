-- Streamly analytics warehouse: point-in-time watch-hours reporting
-- Fresh-container initialization: schema + seed data.

SET client_min_messages = WARNING;

-- ---------------------------------------------------------------------------
-- Reference: plan catalog
-- ---------------------------------------------------------------------------
CREATE TABLE plans (
    plan_id      INTEGER PRIMARY KEY,
    plan_tier    TEXT NOT NULL,          -- e.g. Basic, Standard, Premium
    monthly_price NUMERIC(8,2) NOT NULL
);

INSERT INTO plans (plan_id, plan_tier, monthly_price) VALUES
    (1, 'Basic',    6.99),
    (2, 'Standard', 12.99),
    (3, 'Premium',  18.99);

-- ---------------------------------------------------------------------------
-- Subscribers
-- ---------------------------------------------------------------------------
CREATE TABLE subscribers (
    subscriber_id INTEGER PRIMARY KEY,
    display_name  TEXT NOT NULL,
    country       TEXT NOT NULL,
    signed_up_at  TIMESTAMPTZ NOT NULL
);

INSERT INTO subscribers (subscriber_id, display_name, country, signed_up_at) VALUES
    (101, 'Aditi Rao',      'IN', '2024-06-01T10:00:00Z'),
    (102, 'Liam Chen',      'SG', '2024-08-15T09:30:00Z'),
    (103, 'Sofia Alvarez',  'ES', '2024-09-20T14:00:00Z'),
    (104, 'Noah Weber',     'DE', '2024-10-05T18:45:00Z'),
    (105, 'Yuki Tanaka',    'JP', '2024-11-11T07:15:00Z'),
    (106, 'Grace Okonkwo',  'NG', '2024-12-01T12:00:00Z'),
    (107, 'Mateus Silva',   'BR', '2024-12-20T16:20:00Z'),
    (108, 'Elena Petrova',  'BG', '2025-01-02T08:00:00Z');

-- ---------------------------------------------------------------------------
-- Type-2 slowly changing plan history.
-- Each row records the plan a subscriber held over an effective window.
-- valid_to IS NULL denotes the currently open-ended row.
-- The data intentionally contains overlapping and late-arriving/corrective
-- rows that reflect how the upstream feed actually behaves.
-- ---------------------------------------------------------------------------
CREATE TABLE subscription_plan_history (
    history_id    BIGINT PRIMARY KEY,
    subscriber_id INTEGER NOT NULL REFERENCES subscribers(subscriber_id),
    plan_id       INTEGER NOT NULL REFERENCES plans(plan_id),
    valid_from    TIMESTAMPTZ NOT NULL,
    valid_to      TIMESTAMPTZ,               -- NULL => current/open-ended
    recorded_at   TIMESTAMPTZ NOT NULL       -- when this history row was written
);

-- 101: single stable plan across the whole period.
INSERT INTO subscription_plan_history VALUES
    (1, 101, 2, '2024-06-01T00:00:00Z', NULL, '2024-06-01T00:00:00Z');

-- 102: upgrade mid-January (Standard -> Premium at 2025-01-16 00:00Z).
INSERT INTO subscription_plan_history VALUES
    (2, 102, 2, '2024-08-15T00:00:00Z', '2025-01-16T00:00:00Z', '2024-08-15T00:00:00Z'),
    (3, 102, 3, '2025-01-16T00:00:00Z', NULL,                    '2025-01-16T00:00:00Z');

-- 103: downgrade mid-January, then a late-arriving correction of the
-- downgrade instant (two rows describe the same later state).
INSERT INTO subscription_plan_history VALUES
    (4, 103, 3, '2024-09-20T00:00:00Z', '2025-01-10T00:00:00Z', '2024-09-20T00:00:00Z'),
    (5, 103, 1, '2025-01-10T00:00:00Z', NULL,                    '2025-01-10T00:00:00Z'),
    -- corrective row written later: same subscriber, later state, overlaps row 5
    (6, 103, 1, '2025-01-10T00:00:00Z', NULL,                    '2025-01-25T00:00:00Z');

-- 104: cancel then reactivate. A gap where no plan applies
-- (cancelled 2025-01-05 .. reactivated 2025-01-20).
INSERT INTO subscription_plan_history VALUES
    (7, 104, 1, '2024-10-05T00:00:00Z', '2025-01-05T00:00:00Z', '2024-10-05T00:00:00Z'),
    (8, 104, 2, '2025-01-20T00:00:00Z', NULL,                    '2025-01-20T00:00:00Z');

-- 105: two overlapping open-ended rows from a duplicated upstream event.
INSERT INTO subscription_plan_history VALUES
    (9,  105, 3, '2024-11-11T00:00:00Z', NULL, '2024-11-11T00:00:00Z'),
    (10, 105, 3, '2024-11-11T00:00:00Z', NULL, '2024-12-01T00:00:00Z');

-- 106: upgrade then downgrade, all within January.
INSERT INTO subscription_plan_history VALUES
    (11, 106, 1, '2024-12-01T00:00:00Z', '2025-01-08T00:00:00Z', '2024-12-01T00:00:00Z'),
    (12, 106, 3, '2025-01-08T00:00:00Z', '2025-01-22T00:00:00Z', '2025-01-08T00:00:00Z'),
    (13, 106, 2, '2025-01-22T00:00:00Z', NULL,                    '2025-01-22T00:00:00Z');

-- 107: stable Basic.
INSERT INTO subscription_plan_history VALUES
    (14, 107, 1, '2024-12-20T00:00:00Z', NULL, '2024-12-20T00:00:00Z');

-- 108: history begins 2025-01-15; sessions before that have no plan.
INSERT INTO subscription_plan_history VALUES
    (15, 108, 2, '2025-01-15T00:00:00Z', NULL, '2025-01-15T00:00:00Z');

-- ---------------------------------------------------------------------------
-- Viewing sessions fact.
-- Each row is one playback session; watch_seconds is its duration.
-- ---------------------------------------------------------------------------
CREATE TABLE viewing_sessions (
    session_id    BIGINT PRIMARY KEY,
    subscriber_id INTEGER NOT NULL REFERENCES subscribers(subscriber_id),
    started_at    TIMESTAMPTZ NOT NULL,
    watch_seconds INTEGER NOT NULL CHECK (watch_seconds >= 0)
);

-- Base seeded sessions (hand-crafted to exercise edge cases).
-- 101: two January sessions, plan stable (Standard).
INSERT INTO viewing_sessions VALUES
    (1000, 101, '2025-01-03T20:00:00Z', 3600),
    (1001, 101, '2025-01-18T21:30:00Z', 5400);

-- 102: before and after the mid-Jan upgrade, plus a session exactly at the boundary.
INSERT INTO viewing_sessions VALUES
    (1002, 102, '2025-01-05T19:00:00Z', 3000),               -- Standard window
    (1003, 102, '2025-01-16T00:00:00Z', 3600),               -- exactly at boundary instant
    (1004, 102, '2025-01-20T22:00:00Z', 7200);               -- Premium window

-- 103: before and after downgrade; the after-downgrade state has a duplicated history row.
INSERT INTO viewing_sessions VALUES
    (1005, 103, '2025-01-04T18:00:00Z', 4200),               -- Premium window
    (1006, 103, '2025-01-14T20:00:00Z', 3600),               -- Basic window (dup history)
    (1007, 103, '2025-01-28T09:00:00Z', 1800);               -- Basic window (dup history)

-- 104: session during active, during cancelled gap, and after reactivation.
INSERT INTO viewing_sessions VALUES
    (1008, 104, '2025-01-02T10:00:00Z', 2400),               -- Basic window
    (1009, 104, '2025-01-12T10:00:00Z', 3000),               -- in cancelled gap (no plan)
    (1010, 104, '2025-01-25T10:00:00Z', 3600);               -- Standard window

-- 105: overlapping duplicate open-ended history rows.
INSERT INTO viewing_sessions VALUES
    (1011, 105, '2025-01-07T08:00:00Z', 5400),
    (1012, 105, '2025-01-21T08:00:00Z', 3600);

-- 106: three sub-windows within January.
INSERT INTO viewing_sessions VALUES
    (1013, 106, '2025-01-03T12:00:00Z', 3000),               -- Basic
    (1014, 106, '2025-01-15T12:00:00Z', 3600),               -- Premium
    (1015, 106, '2025-01-27T12:00:00Z', 4200);               -- Standard

-- 107: stable Basic sessions.
INSERT INTO viewing_sessions VALUES
    (1016, 107, '2025-01-06T15:00:00Z', 1800),
    (1017, 107, '2025-01-19T15:00:00Z', 2400);

-- 108: one session before history begins (no plan), one after.
INSERT INTO viewing_sessions VALUES
    (1018, 108, '2025-01-10T11:00:00Z', 3000),               -- before history begins
    (1019, 108, '2025-01-22T11:00:00Z', 3600);               -- Standard window

-- A December session that must NOT appear in the January report.
INSERT INTO viewing_sessions VALUES
    (1020, 101, '2024-12-30T20:00:00Z', 3600);

-- ---------------------------------------------------------------------------
-- Bulk synthetic sessions to create realistic scale for performance work.
-- Distributed across subscribers and across January 2025.
-- ---------------------------------------------------------------------------
INSERT INTO viewing_sessions (session_id, subscriber_id, started_at, watch_seconds)
SELECT
    2000 + g AS session_id,
    101 + (g % 7) AS subscriber_id,
    '2025-01-01T00:00:00Z'::timestamptz
        + ((g % 30) * INTERVAL '1 day')
        + ((g % 24) * INTERVAL '1 hour')
        + ((g % 60) * INTERVAL '1 minute') AS started_at,
    600 + (g % 7000) AS watch_seconds
FROM generate_series(1, 200000) AS g;

-- ---------------------------------------------------------------------------
-- Draft reporting view (flagged as unreliable by analysts).
-- Kept as-is for reference; see starter_queries.sql for the same logic.
-- ---------------------------------------------------------------------------
CREATE VIEW v_watch_hours_by_tier_draft AS
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
GROUP BY 1, 2;

ANALYZE;
