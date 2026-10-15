use("fleetmonitor");

db.gps_locations.deleteMany({source: "fleetmonitor-demo"});
db.maintenance_logs.deleteMany({source: "fleetmonitor-demo"});

const now = new Date();
db.gps_locations.insertMany([
  { vehicle_id: NumberLong(1), recorded_at: new Date(now - 5 * 60 * 1000), location: {type: "Point", coordinates: [-74.0060, 40.7128]}, speed_kph: 54.2, heading: 92.0, ignition: true, source: "fleetmonitor-demo" },
  { vehicle_id: NumberLong(2), recorded_at: new Date(now - 4 * 60 * 1000), location: {type: "Point", coordinates: [-73.9855, 40.7580]}, speed_kph: 31.8, heading: 180.0, ignition: true, source: "fleetmonitor-demo" },
  { vehicle_id: NumberLong(4), recorded_at: new Date(now - 3 * 60 * 1000), location: {type: "Point", coordinates: [-74.0445, 40.6892]}, speed_kph: 0, heading: 270.0, ignition: false, source: "fleetmonitor-demo" },
  { vehicle_id: NumberLong(5), recorded_at: new Date(now - 2 * 60 * 1000), location: {type: "Point", coordinates: [-73.9712, 40.7831]}, speed_kph: 62.5, heading: 45.0, ignition: true, source: "fleetmonitor-demo" }
]);

db.maintenance_logs.insertMany([
  { vehicle_id: NumberLong(1), logged_at: new Date(now - 10 * 24 * 60 * 60 * 1000), event_type: "inspection", technician: "M. Patel", findings: ["Brake pads at 45%", "No leaks"], parts: [], odometer_km: 84000, source: "fleetmonitor-demo" },
  { vehicle_id: NumberLong(3), logged_at: new Date(now - 2 * 24 * 60 * 60 * 1000), event_type: "repair", technician: "L. Chen", findings: ["Alternator failure"], parts: [{part_no: "ALT-200", quantity: 1, cost: 540}], odometer_km: 55950, source: "fleetmonitor-demo" },
  { vehicle_id: NumberLong(5), logged_at: new Date(now - 20 * 24 * 60 * 60 * 1000), event_type: "part_replacement", technician: "R. Singh", findings: ["Tire tread below threshold"], parts: [{part_no: "TIRE-18", quantity: 4, cost: 760}], odometer_km: 112200, source: "fleetmonitor-demo" }
]);

