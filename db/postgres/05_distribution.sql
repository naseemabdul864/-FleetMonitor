/*
Hybrid distribution design
==========================

PostgreSQL is the system of record for vehicle identity, schedules, assignments,
maintenance state, and financial/operational constraints. MongoDB owns append-heavy
GPS points and flexible maintenance inspection telemetry. The vehicle registration
number or immutable vehicle_id is the cross-store key.

Recommended topology:
  - PostgreSQL primary + one or more streaming read replicas.
  - PostgreSQL monthly partitioning for schedule history and an outbox table for
    reliable event publication.
  - MongoDB replica set (3 voting members) for GPS/maintenance availability.
  - MongoDB sharding by hashed vehicle_id for balanced writes; time-based indexes
    support recent tracking queries.
  - Dashboard reads PostgreSQL replicas for reports and MongoDB secondaryPreferred
    for map history where slight staleness is acceptable.

Consistency:
  - A schedule or maintenance state change commits in PostgreSQL first.
  - The outbox event is published asynchronously to MongoDB/analytics.
  - Consumers are idempotent using event_id, so at-least-once delivery is safe.
  - A command that must be immediately reflected in the dispatch UI reads the
    PostgreSQL primary after commit.
*/

-- Runnable monthly partitioning example for a new history table.
CREATE TABLE IF NOT EXISTS vehicle_schedule_history (
    schedule_id BIGINT NOT NULL,
    vehicle_id BIGINT NOT NULL,
    scheduled_start TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now()
) PARTITION BY RANGE (scheduled_start);

CREATE TABLE IF NOT EXISTS vehicle_schedule_history_2026_01
    PARTITION OF vehicle_schedule_history
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE IF NOT EXISTS vehicle_schedule_history_default
    PARTITION OF vehicle_schedule_history DEFAULT;

-- Transactional outbox write: keep this statement in the same transaction as
-- the business update that changes the schedule.
BEGIN;
UPDATE vehicle_schedule
SET status = 'dispatched'
WHERE schedule_id = 1 AND status = 'planned';
INSERT INTO integration_outbox (aggregate_type, aggregate_id, event_type, payload)
SELECT 'vehicle_schedule', schedule_id, 'schedule.dispatched',
       jsonb_build_object('schedule_id', schedule_id, 'status', status, 'changed_at', now())
FROM vehicle_schedule
WHERE schedule_id = 1 AND status = 'dispatched';
COMMIT;

-- A worker claims unpublished events without holding locks while publishing.
WITH next_events AS (
    SELECT event_id
    FROM integration_outbox
    WHERE published_at IS NULL
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 100
)
UPDATE integration_outbox o
SET published_at = now()
FROM next_events n
WHERE o.event_id = n.event_id
RETURNING o.*;

-- MongoDB operational commands (run in mongosh after starting a replica set):
-- rs.initiate({_id:"fleet-rs", members:[{_id:0,host:"mongo-a:27017"},{_id:1,host:"mongo-b:27017"},{_id:2,host:"mongo-c:27017"}]})
-- sh.enableSharding("fleetmonitor")
-- sh.shardCollection("fleetmonitor.gps_locations", {vehicle_id:"hashed"})
-- db.gps_locations.createIndex({vehicle_id:1, recorded_at:-1})

