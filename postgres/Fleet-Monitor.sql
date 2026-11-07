-- Create a separate database first in pgAdmin:
-- fleetmonitor
--
-- Then run the rest of this script inside the fleetmonitor database.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Master tables

CREATE TABLE IF NOT EXISTS vehicles (
    vehicle_id BIGSERIAL PRIMARY KEY,
    registration_number VARCHAR(20) UNIQUE NOT NULL,
    vehicle_type VARCHAR(50) NOT NULL,
    make VARCHAR(50),
    model VARCHAR(50),
    manufacture_year INT CHECK (manufacture_year BETWEEN 1990 AND 2100),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'maintenance')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS drivers (
    driver_id BIGSERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    license_number VARCHAR(50) UNIQUE NOT NULL,
    phone VARCHAR(30),
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive'))
);

CREATE TABLE IF NOT EXISTS routes (
    route_id BIGSERIAL PRIMARY KEY,
    route_name VARCHAR(100) NOT NULL,
    origin VARCHAR(100) NOT NULL,
    destination VARCHAR(100) NOT NULL,
    distance_km NUMERIC(10,2) CHECK (distance_km >= 0)
);

CREATE TABLE IF NOT EXISTS schedules (
    schedule_id BIGSERIAL PRIMARY KEY,
    vehicle_id BIGINT NOT NULL REFERENCES vehicles(vehicle_id),
    driver_id BIGINT REFERENCES drivers(driver_id),
    route_id BIGINT REFERENCES routes(route_id),
    scheduled_start TIMESTAMPTZ NOT NULL,
    scheduled_end TIMESTAMPTZ NOT NULL,
    schedule_status VARCHAR(20) NOT NULL DEFAULT 'scheduled'
        CHECK (schedule_status IN ('scheduled', 'in_progress', 'completed', 'cancelled')),
    CHECK (scheduled_end > scheduled_start)
);

CREATE TABLE IF NOT EXISTS maintenance_work_orders (
    work_order_id BIGSERIAL PRIMARY KEY,
    vehicle_id BIGINT NOT NULL REFERENCES vehicles(vehicle_id),
    maintenance_type VARCHAR(100) NOT NULL,
    description TEXT,
    cost NUMERIC(12,2) DEFAULT 0 CHECK (cost >= 0),
    opened_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    work_status VARCHAR(20) NOT NULL DEFAULT 'open'
        CHECK (work_status IN ('open', 'in_progress', 'completed'))
);

-- 2. Partitioned PostgreSQL table for high-volume fleet telemetry.
-- This is PostgreSQL partitioning used as a practical sharding demonstration.

CREATE TABLE IF NOT EXISTS vehicle_telemetry (
    telemetry_id BIGSERIAL,
    vehicle_id BIGINT NOT NULL REFERENCES vehicles(vehicle_id),
    recorded_at TIMESTAMPTZ NOT NULL,
    latitude NUMERIC(9,6) NOT NULL,
    longitude NUMERIC(9,6) NOT NULL,
    speed_kmh NUMERIC(7,2) DEFAULT 0,
    fuel_level NUMERIC(5,2),
    engine_temperature NUMERIC(6,2),
    PRIMARY KEY (telemetry_id, recorded_at)
) PARTITION BY RANGE (recorded_at);

CREATE TABLE IF NOT EXISTS vehicle_telemetry_2025
    PARTITION OF vehicle_telemetry
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

CREATE TABLE IF NOT EXISTS vehicle_telemetry_2026
    PARTITION OF vehicle_telemetry
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

CREATE TABLE IF NOT EXISTS vehicle_telemetry_2027
    PARTITION OF vehicle_telemetry
    FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');

-- Catch-all partition for future dates
CREATE TABLE IF NOT EXISTS vehicle_telemetry_default
    PARTITION OF vehicle_telemetry DEFAULT;

-- 3. Insert master data

INSERT INTO vehicles
    (registration_number, vehicle_type, make, model, manufacture_year, status)
SELECT
    'FM-' || LPAD(value::text, 4, '0'),
    CASE value % 3
        WHEN 0 THEN 'Truck'
        WHEN 1 THEN 'Van'
        ELSE 'Bus'
    END,
    CASE value % 3
        WHEN 0 THEN 'Volvo'
        WHEN 1 THEN 'Toyota'
        ELSE 'Mercedes'
    END,
    CASE value % 3
        WHEN 0 THEN 'FH'
        WHEN 1 THEN 'Hiace'
        ELSE 'Sprinter'
    END,
    2018 + (value % 8),
    'active'
FROM generate_series(1, 100) AS numbers(value)
ON CONFLICT (registration_number) DO NOTHING;

INSERT INTO drivers
    (full_name, license_number, phone)
SELECT
    'Driver ' || value,
    'LIC-' || LPAD(value::text, 5, '0'),
    '+91-90000' || LPAD(value::text, 5, '0')
FROM generate_series(1, 100) AS numbers(value)
ON CONFLICT (license_number) DO NOTHING;

INSERT INTO routes
    (route_name, origin, destination, distance_km)
SELECT
    'Route ' || value,
    'City ' || value,
    'City ' || (value + 1),
    25 + value * 3.5
FROM generate_series(1, 20) AS numbers(value);

-- 4. Create exactly 100,000 telemetry records

INSERT INTO vehicle_telemetry (
    vehicle_id,
    recorded_at,
    latitude,
    longitude,
    speed_kmh,
    fuel_level,
    engine_temperature
)
SELECT
    1 + ((value - 1) % 100),
    TIMESTAMPTZ '2026-01-01 00:00:00+00'
        + ((value - 1) * INTERVAL '5 minutes'),
    17.000000 + ((value % 1000) * 0.000100),
    78.000000 + ((value % 1000) * 0.000100),
    20 + ((value * 7) % 80),
    20 + ((value * 13) % 80),
    70 + ((value * 11) % 30)
FROM generate_series(1, 100000) AS numbers(value);

-- 5. Indexes for dashboard queries

CREATE INDEX IF NOT EXISTS idx_telemetry_vehicle_time
    ON vehicle_telemetry (vehicle_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_telemetry_recorded_at
    ON vehicle_telemetry (recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_schedule_vehicle_start
    ON schedules (vehicle_id, scheduled_start);

CREATE INDEX IF NOT EXISTS idx_work_orders_vehicle_status
    ON maintenance_work_orders (vehicle_id, work_status);

ANALYZE vehicles;
ANALYZE schedules;
ANALYZE maintenance_work_orders;
ANALYZE vehicle_telemetry;

-- 6. Verify the 100,000 records

SELECT COUNT(*) AS telemetry_record_count
FROM vehicle_telemetry;

-- Verify records stored in each partition

SELECT
    tableoid::regclass AS partition_name,
    COUNT(*) AS record_count
FROM vehicle_telemetry
GROUP BY tableoid
ORDER BY partition_name;

-- Fleet dashboard summary

SELECT
    COUNT(*) AS total_vehicles,
    COUNT(*) FILTER (WHERE status = 'active') AS active_vehicles,
    COUNT(*) FILTER (WHERE status = 'maintenance') AS vehicles_in_maintenance
FROM vehicles;

-- Latest location for each vehicle

SELECT DISTINCT ON (vehicle_id)
    vehicle_id,
    recorded_at,
    latitude,
    longitude,
    speed_kmh,
    fuel_level
FROM vehicle_telemetry
ORDER BY vehicle_id, recorded_at DESC;

-- Daily telemetry summary for dashboard charts

SELECT
    recorded_at::date AS telemetry_date,
    COUNT(*) AS location_records,
    ROUND(AVG(speed_kmh), 2) AS average_speed,
    ROUND(AVG(fuel_level), 2) AS average_fuel
FROM vehicle_telemetry
GROUP BY recorded_at::date
ORDER BY telemetry_date;

EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM vehicle_telemetry
WHERE vehicle_id = 25
ORDER BY recorded_at DESC
LIMIT 100;

BEGIN;

INSERT INTO vehicle_telemetry (
    vehicle_id,
    recorded_at,
    latitude,
    longitude,
    speed_kmh,
    fuel_level,
    engine_temperature
)
SELECT
    v.vehicle_id,
    TIMESTAMPTZ '2026-01-01 00:00:00+00'
        + (g.record_no * INTERVAL '5 minutes'),
    ROUND((17.000000 + random() * 0.500000)::numeric, 6),
    ROUND((78.000000 + random() * 0.500000)::numeric, 6),
    ROUND((10 + random() * 90)::numeric, 2),
    ROUND((10 + random() * 90)::numeric, 2),
    ROUND((65 + random() * 35)::numeric, 2)
FROM generate_series(1, 50000) AS g(record_no)
CROSS JOIN LATERAL (
    SELECT vehicle_id
    FROM vehicles
    ORDER BY random()
    LIMIT 1
) AS v;

COMMIT;

ANALYZE vehicle_telemetry;

SELECT COUNT(*) AS total_telemetry_records
FROM vehicle_telemetry;
SELECT
    vehicle_id,
    COUNT(*) AS telemetry_records,
    ROUND(AVG(speed_kmh), 2) AS average_speed,
    ROUND(AVG(fuel_level), 2) AS average_fuel
FROM vehicle_telemetry
GROUP BY vehicle_id
ORDER BY vehicle_id;
SELECT
    recorded_at::date AS telemetry_date,
    COUNT(*) AS records_per_day
FROM vehicle_telemetry
GROUP BY recorded_at::date
ORDER BY telemetry_date;

ROLLBACK;

-- 1. Drivers
INSERT INTO drivers (
    full_name,
    license_number,
    phone
)
SELECT
    'Bulk Driver ' || n,
    'BULK-LIC-' || LPAD(n::text, 5, '0'),
    '+91-91000' || LPAD(n::text, 5, '0')
FROM generate_series(1, 100) AS s(n)
ON CONFLICT (license_number) DO NOTHING;

-- 2. Routes
INSERT INTO routes (
    route_name,
    origin,
    destination,
    distance_km
)
SELECT
    'Bulk Route ' || n,
    'City ' || n,
    'City ' || (n + 1),
    ROUND((25 + random() * 400)::numeric, 2)
FROM generate_series(1, 20) AS s(n)
WHERE NOT EXISTS (
    SELECT 1
    FROM routes r
    WHERE r.route_name = 'Bulk Route ' || n
);

-- 3. Vehicles
INSERT INTO vehicles (
    registration_number,
    vehicle_type,
    make,
    model,
    manufacture_year,
    status
)
SELECT
    'BULK-FM-' || LPAD(n::text, 5, '0'),
    CASE n % 3
        WHEN 0 THEN 'Truck'
        WHEN 1 THEN 'Van'
        ELSE 'Bus'
    END,
    CASE n % 3
        WHEN 0 THEN 'Volvo'
        WHEN 1 THEN 'Toyota'
        ELSE 'Mercedes'
    END,
    CASE n % 3
        WHEN 0 THEN 'FH'
        WHEN 1 THEN 'Hiace'
        ELSE 'Sprinter'
    END,
    2018 + (n % 8),
    CASE
        WHEN n <= 10000 THEN 'maintenance'
        ELSE 'active'
    END
FROM generate_series(1, 50000) AS s(n)
ON CONFLICT (registration_number) DO NOTHING;

-- 4. Schedules
INSERT INTO schedules (
    vehicle_id,
    driver_id,
    route_id,
    scheduled_start,
    scheduled_end,
    schedule_status
)
SELECT
    v.vehicle_id,
    d.driver_id,
    r.route_id,
    TIMESTAMPTZ '2026-01-01 06:00:00+00'
        + ((ROW_NUMBER() OVER (ORDER BY v.vehicle_id) - 1)
        * INTERVAL '30 minutes'),
    TIMESTAMPTZ '2026-01-01 08:00:00+00'
        + ((ROW_NUMBER() OVER (ORDER BY v.vehicle_id) - 1)
        * INTERVAL '30 minutes'),
    CASE v.vehicle_id % 4
        WHEN 0 THEN 'completed'
        WHEN 1 THEN 'in_progress'
        WHEN 2 THEN 'scheduled'
        ELSE 'cancelled'
    END
FROM vehicles v
CROSS JOIN LATERAL (
    SELECT driver_id
    FROM drivers
    ORDER BY driver_id
    OFFSET ((v.vehicle_id - 1) % 100)
    LIMIT 1
) AS d
CROSS JOIN LATERAL (
    SELECT route_id
    FROM routes
    WHERE route_name LIKE 'Bulk Route %'
    ORDER BY route_id
    OFFSET ((v.vehicle_id - 1) % 20)
    LIMIT 1
) AS r
WHERE v.registration_number LIKE 'BULK-FM-%';

-- 5. Maintenance work orders
INSERT INTO maintenance_work_orders (
    vehicle_id,
    maintenance_type,
    description,
    cost,
    opened_at,
    completed_at,
    work_status
)
SELECT
    v.vehicle_id,
    CASE n % 4
        WHEN 0 THEN 'Oil Change'
        WHEN 1 THEN 'Brake Inspection'
        WHEN 2 THEN 'Tire Replacement'
        ELSE 'Engine Service'
    END,
    'Bulk FleetMonitor work order ' || n,
    ROUND((100 + random() * 1900)::numeric, 2),
    TIMESTAMPTZ '2026-01-01 08:00:00+00'
        + ((n - 1) * INTERVAL '20 minutes'),
    CASE
        WHEN n % 3 = 0 THEN
            TIMESTAMPTZ '2026-01-01 08:00:00+00'
                + ((n - 1) * INTERVAL '20 minutes')
                + INTERVAL '4 hours'
        ELSE NULL
    END,
    CASE
        WHEN n % 3 = 0 THEN 'completed'
        WHEN n % 3 = 1 THEN 'in_progress'
        ELSE 'open'
    END
FROM generate_series(1, 50000) AS s(n)
JOIN LATERAL (
    SELECT vehicle_id
    FROM vehicles
    WHERE registration_number LIKE 'BULK-FM-%'
    ORDER BY vehicle_id
    OFFSET ((n - 1) % 50000)
    LIMIT 1
) AS v
ON TRUE;

ROLLBACK;

INSERT INTO maintenance_work_orders (
    vehicle_id,
    maintenance_type,
    description,
    cost,
    opened_at,
    completed_at,
    work_status
)
WITH bulk_vehicles AS (
    SELECT
        vehicle_id,
        ROW_NUMBER() OVER (ORDER BY vehicle_id) AS vehicle_number
    FROM vehicles
    WHERE registration_number LIKE 'BULK-FM-%'
),
numbers AS (
    SELECT generate_series(1, 50000)::bigint AS n
)
SELECT
    bv.vehicle_id,
    CASE n.n % 4
        WHEN 0 THEN 'Oil Change'
        WHEN 1 THEN 'Brake Inspection'
        WHEN 2 THEN 'Tire Replacement'
        ELSE 'Engine Service'
    END,
    'Bulk FleetMonitor work order ' || n.n,
    ROUND((100 + random() * 1900)::numeric, 2),
    TIMESTAMPTZ '2026-01-01 08:00:00+00'
        + ((n.n - 1) * INTERVAL '20 minutes'),
    CASE
        WHEN n.n % 3 = 0 THEN
            TIMESTAMPTZ '2026-01-01 08:00:00+00'
                + ((n.n - 1) * INTERVAL '20 minutes')
                + INTERVAL '4 hours'
        ELSE NULL
    END,
    CASE
        WHEN n.n % 3 = 0 THEN 'completed'
        WHEN n.n % 3 = 1 THEN 'in_progress'
        ELSE 'open'
    END
FROM numbers n
JOIN bulk_vehicles bv
    ON bv.vehicle_number = ((n.n - 1) % 50000) + 1;


ANALYZE vehicles;
ANALYZE schedules;
ANALYZE maintenance_work_orders;

SELECT COUNT(*) AS work_order_count
FROM maintenance_work_orders
WHERE description LIKE 'Bulk FleetMonitor work order%';

ANALYZE maintenance_work_orders;

SELECT
    pid,
    state,
    query_start,
    now() - query_start AS running_for,
    wait_event_type,
    wait_event,
    LEFT(query, 150) AS query_text
FROM pg_stat_activity
WHERE datname = current_database()
  AND state <> 'idle'
ORDER BY query_start;






