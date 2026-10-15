-- Run after 01_schema.sql and 02_seed.sql.
-- EXPLAIN ANALYZE changes database statistics and should be used on a safe copy.

ANALYZE vehicle;
ANALYZE vehicle_schedule;
ANALYZE maintenance_work_order;

EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT s.schedule_id, v.registration_no, r.route_code, s.scheduled_start, s.status
FROM vehicle_schedule s
JOIN vehicle v ON v.vehicle_id = s.vehicle_id
JOIN route r ON r.route_id = s.route_id
WHERE s.scheduled_start >= CURRENT_DATE
  AND s.scheduled_start < CURRENT_DATE + INTERVAL '1 day'
  AND s.status IN ('planned', 'dispatched', 'in_progress')
ORDER BY s.scheduled_start;

-- This partial index targets the dashboard's active schedule workload.
CREATE INDEX IF NOT EXISTS idx_schedule_dashboard_covering
ON vehicle_schedule (scheduled_start, vehicle_id)
INCLUDE (schedule_id, route_id, status, load_kg)
WHERE status IN ('planned', 'dispatched', 'in_progress');

EXPLAIN (ANALYZE, BUFFERS)
SELECT m.work_order_id, v.registration_no, m.priority, m.due_at, m.description
FROM maintenance_work_order m
JOIN vehicle v ON v.vehicle_id = m.vehicle_id
WHERE m.status IN ('open', 'in_progress')
  AND m.due_at <= CURRENT_DATE + INTERVAL '30 days'
ORDER BY m.due_at, m.priority DESC
LIMIT 50;

-- Keyset pagination avoids scanning and discarding a large OFFSET.
PREPARE schedule_page(timestamptz, bigint, integer) AS
SELECT schedule_id, vehicle_id, scheduled_start, status
FROM vehicle_schedule
WHERE (scheduled_start, schedule_id) > ($1, $2)
ORDER BY scheduled_start, schedule_id
LIMIT $3;
-- EXECUTE schedule_page('2026-01-01 00:00:00+00', 0, 25);
DEALLOCATE schedule_page;

-- Pre-aggregate once rather than running one correlated scan per vehicle.
EXPLAIN (ANALYZE, BUFFERS)
SELECT v.registration_no, COALESCE(m.open_count, 0) AS open_work_orders,
       COALESCE(f.fuel_cost_30d, 0) AS fuel_cost_30d
FROM vehicle v
LEFT JOIN (
    SELECT vehicle_id, COUNT(*) AS open_count
    FROM maintenance_work_order
    WHERE status IN ('open', 'in_progress')
    GROUP BY vehicle_id
) m ON m.vehicle_id = v.vehicle_id
LEFT JOIN (
    SELECT vehicle_id, SUM(cost) AS fuel_cost_30d
    FROM fuel_transaction
    WHERE filled_at >= now() - INTERVAL '30 days'
    GROUP BY vehicle_id
) f ON f.vehicle_id = v.vehicle_id;

-- Inspect whether indexes are actually used before retaining them.
SELECT relname AS table_name, indexrelname AS index_name, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
WHERE relname IN ('vehicle_schedule', 'maintenance_work_order', 'fuel_transaction')
ORDER BY idx_scan DESC;

