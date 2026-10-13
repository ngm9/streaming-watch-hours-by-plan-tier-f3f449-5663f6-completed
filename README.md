# Point-in-Time Watch-Hours by Plan Tier

## Task Overview
Streamly, a media streaming service, publishes a monthly report totalling watch-hours per plan tier, where each viewing session must be credited to the plan the subscriber held when the session started. Plan changes are stored as a Type-2 slowly changing dimension with effective date windows, and analysts have reported that the current report over-counts sessions, mis-attributes some to the wrong tier, and runs too slowly at production volume. The database is already deployed and fully populated with schema and seed data, including subscribers who changed plans mid-month and history that contains overlapping and late-arriving rows. You must diagnose and resolve the issue using SQL only.

## Objectives
- Produce a report at one row per plan tier per report month, with total watch-hours and a distinct session count that reconciles against the raw sessions of that month.
- Ensure every qualifying session is attributed to exactly one plan tier and counted exactly once, even when a subscriber's history overlaps, was superseded by a correction, or is open-ended.
- Guarantee deterministic, repeatable results that do not change across identical runs.
- Make explicit, and not silently mishandle, sessions that have no resolvable plan at their start time.
- Deliver a materially faster report at large data volume through SQL-level changes.

## Helpful Tips
- Review how the draft matches a session to a history row and think about what happens when more than one history row can match a single session.
- Consider the exact boundary semantics of the effective windows and how the open-ended current row should behave at and around a plan-change instant.
- Analyze which subscribers in the data changed plans within the report month and reconcile their per-session counts by hand against the report output.
- Think about whether a blanket de-duplication would hide, rather than fix, an underlying cardinality problem.
- Explore the query's behaviour at scale and consider which access patterns and predicates are limiting performance.

## How to Verify
- Run the provided validation script and confirm every check reports a passing status.
- Confirm the report returns exactly one row per (report month, plan tier) with no duplicated tier rows for a month.
- Confirm the sum of per-tier distinct session counts for the report month equals the number of distinct in-month sessions that have a resolvable plan.
- Confirm that subscribers who changed plans mid-month have their sessions split across tiers correctly with no session counted twice.
- Confirm results are identical when the report query is executed repeatedly.
- Observe that the corrected report's execution plan and timing are materially better than the draft at the seeded volume.