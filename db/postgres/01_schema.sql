CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- PostgreSQL is the relational source of truth for structured fleet operations.
-- MongoDB stores high-volume GPS and flexible maintenance-log documents only.

CREATE TABLE IF NOT EXISTS vehicle (
    vehicle_id BIGSERIAL PRIMARY KEY,
    registration_no TEXT NOT NULL UNIQUE,
    make TEXT NOT NULL,
    model TEXT NOT NULL,
    manufacture_year SMALLINT NOT NULL CHECK (manufacture_year BETWEEN 1980 AND 2100),
    vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('truck', 'van', 'car', 'bus', 'motorcycle')),
    capacity_kg NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (capacity_kg >= 0),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'retired')),
    odometer_km NUMERIC(12, 1) NOT NULL DEFAULT 0 CHECK (odometer_km >= 0),
    current_latitude NUMERIC(9, 6) CHECK (current_latitude BETWEEN -90 AND 90),
    current_longitude NUMERIC(9, 6) CHECK (current_longitude BETWEEN -180 AND 180),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS driver (
    driver_id BIGSERIAL PRIMARY KEY,
    full_name TEXT NOT NULL,
    license_no TEXT NOT NULL UNIQUE,
    phone TEXT,
    employment_status TEXT NOT NULL DEFAULT 'active' CHECK (employment_status IN ('active', 'leave', 'inactive')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS route (
    route_id BIGSERIAL PRIMARY KEY,
    route_code TEXT NOT NULL UNIQUE,
    origin TEXT NOT NULL,
    destination TEXT NOT NULL,
    planned_distance_km NUMERIC(10, 2) NOT NULL CHECK (planned_distance_km > 0),
    service_level TEXT NOT NULL DEFAULT 'standard' CHECK (service_level IN ('standard', 'priority', 'express')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vehicle_schedule (
    schedule_id BIGSERIAL PRIMARY KEY,
    vehicle_id BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    driver_id BIGINT NOT NULL REFERENCES driver(driver_id),
    route_id BIGINT NOT NULL REFERENCES route(route_id),
    scheduled_start TIMESTAMPTZ NOT NULL,
    scheduled_end TIMESTAMPTZ NOT NULL,
    actual_start TIMESTAMPTZ,
    actual_end TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned', 'dispatched', 'in_progress', 'completed', 'cancelled')),
    load_kg NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (load_kg >= 0),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (scheduled_end > scheduled_start),
    CHECK (actual_end IS NULL OR actual_start IS NULL OR actual_end >= actual_start)
);

CREATE TABLE IF NOT EXISTS maintenance_work_order (
    work_order_id BIGSERIAL PRIMARY KEY,
    vehicle_id BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    maintenance_type TEXT NOT NULL CHECK (maintenance_type IN ('preventive', 'corrective', 'inspection', 'recall')),
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'completed', 'cancelled')),
    description TEXT NOT NULL,
    estimated_cost NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (estimated_cost >= 0),
    actual_cost NUMERIC(12, 2) CHECK (actual_cost IS NULL OR actual_cost >= 0),
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    CHECK (completed_at IS NULL OR completed_at >= reported_at)
);

CREATE TABLE IF NOT EXISTS fuel_transaction (
    fuel_transaction_id BIGSERIAL PRIMARY KEY,
    vehicle_id BIGINT NOT NULL REFERENCES vehicle(vehicle_id),
    filled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    liters NUMERIC(10, 2) NOT NULL CHECK (liters > 0),
    cost NUMERIC(12, 2) NOT NULL CHECK (cost >= 0),
    odometer_km NUMERIC(12, 1) NOT NULL CHECK (odometer_km >= 0),
    station TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS operational_alert (
    alert_id BIGSERIAL PRIMARY KEY,
    vehicle_id BIGINT REFERENCES vehicle(vehicle_id),
    alert_type TEXT NOT NULL CHECK (alert_type IN ('late_departure', 'geofence', 'maintenance_due', 'overspeed', 'low_fuel', 'system')),
    severity TEXT NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
    message TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS integration_outbox (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type TEXT NOT NULL,
    aggregate_id BIGINT NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_schedule_start_status ON vehicle_schedule (scheduled_start, status);
CREATE INDEX IF NOT EXISTS idx_schedule_vehicle_start ON vehicle_schedule (vehicle_id, scheduled_start DESC);
CREATE INDEX IF NOT EXISTS idx_schedule_active_window ON vehicle_schedule (scheduled_start, scheduled_end)
    WHERE status IN ('planned', 'dispatched', 'in_progress');
CREATE INDEX IF NOT EXISTS idx_maintenance_due_open ON maintenance_work_order (due_at, vehicle_id)
    WHERE status IN ('open', 'in_progress');
CREATE INDEX IF NOT EXISTS idx_alert_unresolved ON operational_alert (occurred_at DESC)
    WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_fuel_vehicle_date ON fuel_transaction (vehicle_id, filled_at DESC);

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS vehicle_set_updated_at ON vehicle;
CREATE TRIGGER vehicle_set_updated_at BEFORE UPDATE ON vehicle FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS schedule_set_updated_at ON vehicle_schedule;
CREATE TRIGGER schedule_set_updated_at BEFORE UPDATE ON vehicle_schedule FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW v_vehicle_schedule AS
SELECT
    s.schedule_id,
    v.registration_no,
    v.vehicle_type,
    d.full_name AS driver_name,
    r.route_code,
    r.origin,
    r.destination,
    s.scheduled_start,
    s.scheduled_end,
    s.actual_start,
    s.actual_end,
    s.status,
    CASE
        WHEN s.actual_start IS NULL THEN NULL
        ELSE EXTRACT(EPOCH FROM (s.actual_start - s.scheduled_start)) / 60
    END AS departure_delay_minutes
FROM vehicle_schedule s
JOIN vehicle v ON v.vehicle_id = s.vehicle_id
JOIN driver d ON d.driver_id = s.driver_id
JOIN route r ON r.route_id = s.route_id;

CREATE OR REPLACE VIEW v_vehicle_health AS
SELECT
    v.vehicle_id,
    v.registration_no,
    v.status,
    v.odometer_km,
    COUNT(m.work_order_id) FILTER (WHERE m.status IN ('open', 'in_progress')) AS open_work_orders,
    MIN(m.due_at) FILTER (WHERE m.status IN ('open', 'in_progress')) AS next_maintenance_due,
    COALESCE(SUM(f.cost) FILTER (WHERE f.filled_at >= now() - INTERVAL '30 days'), 0) AS fuel_cost_30d
FROM vehicle v
LEFT JOIN maintenance_work_order m ON m.vehicle_id = v.vehicle_id
LEFT JOIN fuel_transaction f ON f.vehicle_id = v.vehicle_id
GROUP BY v.vehicle_id;
