-- Concurrency laboratory. Run the labeled blocks in separate psql sessions.
-- Identify a vehicle with: SELECT vehicle_id, registration_no FROM vehicle ORDER BY vehicle_id LIMIT 1;

-- SESSION A: atomic transaction and rollback
BEGIN;
UPDATE vehicle SET status = 'maintenance' WHERE registration_no = 'FM-101';
SELECT registration_no, status FROM vehicle WHERE registration_no = 'FM-101';
ROLLBACK;

-- SESSION A: pessimistic locking
BEGIN;
SELECT vehicle_id, status FROM vehicle WHERE registration_no = 'FM-101' FOR UPDATE;
UPDATE vehicle SET status = 'maintenance' WHERE registration_no = 'FM-101';
-- Keep this transaction open while Session B runs its SELECT ... FOR UPDATE.
-- COMMIT;

-- SESSION B: this blocks until Session A commits or rolls back.
BEGIN;
SELECT vehicle_id, status FROM vehicle WHERE registration_no = 'FM-101' FOR UPDATE;
UPDATE vehicle SET status = 'active' WHERE registration_no = 'FM-101';
COMMIT;

-- SESSION A: optimistic locking. The version predicate prevents lost updates.
BEGIN;
SELECT work_order_id, status, version
FROM maintenance_work_order
WHERE work_order_id = 1;
-- Application remembers the returned version, then executes:
UPDATE maintenance_work_order
SET status = 'in_progress', version = version + 1
WHERE work_order_id = 1 AND version = 1;
-- If zero rows are affected, another writer won; reload and retry or report a conflict.
COMMIT;

-- Isolation demonstration:
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT COUNT(*) AS open_work_orders
FROM maintenance_work_order
WHERE status IN ('open', 'in_progress');
-- A concurrent committed insert is not visible in this transaction's snapshot.
COMMIT;

