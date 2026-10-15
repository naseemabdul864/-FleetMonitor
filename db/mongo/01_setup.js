use("fleetmonitor");

db.createCollection("gps_locations", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["vehicle_id", "recorded_at", "location", "speed_kph"],
      properties: {
        vehicle_id: { bsonType: ["int", "long"], description: "PostgreSQL vehicle_id" },
        recorded_at: { bsonType: "date" },
        location: {
          bsonType: "object",
          required: ["type", "coordinates"],
          properties: {
            type: { enum: ["Point"] },
            coordinates: { bsonType: "array", minItems: 2, maxItems: 2 }
          }
        },
        speed_kph: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
        heading: { bsonType: ["double", "int", "long", "decimal"], minimum: 0, maximum: 360 }
      }
    }
  },
  validationLevel: "moderate",
  validationAction: "error"
});

db.createCollection("maintenance_logs", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["vehicle_id", "logged_at", "event_type", "technician", "findings"],
      properties: {
        vehicle_id: { bsonType: ["int", "long"] },
        logged_at: { bsonType: "date" },
        event_type: { enum: ["inspection", "repair", "service", "part_replacement"] },
        technician: { bsonType: "string" },
        findings: { bsonType: "array" },
        parts: { bsonType: "array" },
        odometer_km: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 }
      }
    }
  },
  validationLevel: "moderate",
  validationAction: "error"
});

db.gps_locations.createIndex({ vehicle_id: 1, recorded_at: -1 });
db.gps_locations.createIndex({ location: "2dsphere" });
db.gps_locations.createIndex({ recorded_at: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 365 });
db.maintenance_logs.createIndex({ vehicle_id: 1, logged_at: -1 });
db.maintenance_logs.createIndex({ event_type: 1, logged_at: -1 });
db.maintenance_logs.createIndex({ "parts.part_no": 1 });
