-- Seed the PostgreSQL relational source of truth for FleetMonitor.
-- GPS document samples are maintained separately in db/mongo/02_sample_documents.js.

INSERT INTO vehicle (registration_no, make, model, manufacture_year, vehicle_type, capacity_kg, status, odometer_km, current_latitude, current_longitude)
VALUES
('FM-101', 'Volvo', 'FH16', 2021, 'truck', 18000, 'active', 84210.5, 40.7128, -74.0060),
('FM-102', 'Ford', 'Transit', 2022, 'van', 1400, 'active', 32110.2, 40.7580, -73.9855),
('FM-103', 'Toyota', 'Corolla', 2020, 'car', 450, 'maintenance', 55980.0, 40.7306, -73.9352),
('FM-104', 'Mercedes', 'Sprinter', 2023, 'van', 1800, 'active', 12800.7, 40.6892, -74.0445),
('FM-105', 'Isuzu', 'N-Series', 2019, 'truck', 7500, 'active', 112450.8, 40.7831, -73.9712)
ON CONFLICT (registration_no) DO UPDATE SET
    current_latitude = EXCLUDED.current_latitude,
    current_longitude = EXCLUDED.current_longitude,
    updated_at = now();

INSERT INTO driver (full_name, license_no, phone)
VALUES
('Aisha Khan', 'LIC-1001', '+1-555-0101'),
('Daniel Brooks', 'LIC-1002', '+1-555-0102'),
('Priya Shah', 'LIC-1003', '+1-555-0103'),
('Mateo Garcia', 'LIC-1004', '+1-555-0104'),
('Noah Williams', 'LIC-1005', '+1-555-0105')
ON CONFLICT (license_no) DO NOTHING;

INSERT INTO route (route_code, origin, destination, planned_distance_km, service_level)
VALUES
('R-NY-BOS', 'New York', 'Boston', 346.0, 'priority'),
('R-NY-PHI', 'New York', 'Philadelphia', 152.0, 'standard'),
('R-NY-ALB', 'New York', 'Albany', 245.0, 'standard'),
('R-NY-JFK', 'Fleet depot', 'JFK Airport', 38.0, 'express'),
('R-NY-EWR', 'Fleet depot', 'Newark Airport', 27.0, 'express')
ON CONFLICT (route_code) DO NOTHING;

INSERT INTO vehicle_schedule (vehicle_id, driver_id, route_id, scheduled_start, scheduled_end, actual_start, actual_end, status, load_kg, notes)
SELECT v.vehicle_id, d.driver_id, r.route_id, x.scheduled_start, x.scheduled_end, x.actual_start, x.actual_end, x.status, x.load_kg, x.notes
FROM (VALUES
    ('FM-101', 'LIC-1001', 'R-NY-BOS', now() - INTERVAL '1 day', now() - INTERVAL '1 day' + INTERVAL '6 hours', now() - INTERVAL '1 day' + INTERVAL '12 minutes', now() - INTERVAL '1 day' + INTERVAL '6 hours 30 minutes', 'completed', 14500.0, 'Completed with minor delay'),
    ('FM-102', 'LIC-1002', 'R-NY-PHI', now() - INTERVAL '3 hours', now() + INTERVAL '1 hour', now() - INTERVAL '2 hours 50 minutes', NULL, 'in_progress', 950.0, 'Customer delivery route'),
    ('FM-104', 'LIC-1003', 'R-NY-JFK', now() + INTERVAL '2 hours', now() + INTERVAL '4 hours', NULL, NULL, 'planned', 800.0, 'Airport transfer'),
    ('FM-105', 'LIC-1004', 'R-NY-ALB', now() + INTERVAL '1 day', now() + INTERVAL '1 day 7 hours', NULL, NULL, 'planned', 6200.0, 'Refrigerated goods'),
    ('FM-103', 'LIC-1005', 'R-NY-EWR', now() - INTERVAL '2 days', now() - INTERVAL '2 days' + INTERVAL '3 hours', now() - INTERVAL '2 days' + INTERVAL '8 minutes', now() - INTERVAL '2 days' + INTERVAL '3 hours 5 minutes', 'completed', 250.0, 'Vehicle sent for inspection')
) AS x(registration_no, license_no, route_code, scheduled_start, scheduled_end, actual_start, actual_end, status, load_kg, notes)
JOIN vehicle v ON v.registration_no = x.registration_no
JOIN driver d ON d.license_no = x.license_no
JOIN route r ON r.route_code = x.route_code
WHERE NOT EXISTS (
    SELECT 1 FROM vehicle_schedule s
    WHERE s.vehicle_id = v.vehicle_id AND s.scheduled_start = x.scheduled_start
);

INSERT INTO maintenance_work_order (vehicle_id, due_at, maintenance_type, priority, status, description, estimated_cost)
SELECT v.vehicle_id, x.due_at, x.maintenance_type, x.priority, x.status, x.description, x.estimated_cost
FROM (VALUES
    ('FM-101', now() + INTERVAL '14 days', 'preventive', 'normal', 'open', 'Oil, filters, and brake inspection', 650.00),
    ('FM-102', now() - INTERVAL '2 days', 'inspection', 'high', 'open', 'Annual safety inspection overdue', 300.00),
    ('FM-103', now() - INTERVAL '1 day', 'corrective', 'critical', 'in_progress', 'Replace alternator and battery', 1200.00),
    ('FM-104', now() + INTERVAL '45 days', 'preventive', 'low', 'open', 'Scheduled 20,000 km service', 480.00),
    ('FM-105', now() - INTERVAL '10 days', 'corrective', 'high', 'completed', 'Replace worn tire set', 980.00)
) AS x(registration_no, due_at, maintenance_type, priority, status, description, estimated_cost)
JOIN vehicle v ON v.registration_no = x.registration_no
WHERE NOT EXISTS (
    SELECT 1 FROM maintenance_work_order m
    WHERE m.vehicle_id = v.vehicle_id AND m.description = x.description
);

INSERT INTO fuel_transaction (vehicle_id, filled_at, liters, cost, odometer_km, station)
SELECT v.vehicle_id, x.filled_at, x.liters, x.cost, x.odometer_km, x.station
FROM (VALUES
    ('FM-101', now() - INTERVAL '2 days', 280.0, 560.00, 83980.0, 'Depot North'),
    ('FM-102', now() - INTERVAL '1 day', 65.0, 130.00, 32010.0, 'Depot East'),
    ('FM-104', now() - INTERVAL '5 days', 72.0, 144.00, 12520.0, 'Depot South'),
    ('FM-105', now() - INTERVAL '3 days', 190.0, 380.00, 112100.0, 'Depot North')
) AS x(registration_no, filled_at, liters, cost, odometer_km, station)
JOIN vehicle v ON v.registration_no = x.registration_no
WHERE NOT EXISTS (
    SELECT 1 FROM fuel_transaction f
    WHERE f.vehicle_id = v.vehicle_id AND f.filled_at = x.filled_at
);

INSERT INTO operational_alert (vehicle_id, alert_type, severity, message, occurred_at)
SELECT v.vehicle_id, x.alert_type, x.severity, x.message, x.occurred_at
FROM (VALUES
    ('FM-102', 'late_departure', 'warning', 'Route R-NY-PHI departed 10 minutes late', now() - INTERVAL '2 hours'),
    ('FM-103', 'maintenance_due', 'critical', 'Vehicle is blocked by overdue corrective maintenance', now() - INTERVAL '1 day'),
    ('FM-105', 'low_fuel', 'info', 'Fuel level below planned threshold', now() - INTERVAL '4 hours')
) AS x(registration_no, alert_type, severity, message, occurred_at)
JOIN vehicle v ON v.registration_no = x.registration_no
WHERE NOT EXISTS (
    SELECT 1 FROM operational_alert a
    WHERE a.vehicle_id = v.vehicle_id AND a.message = x.message
);
