from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import pandas as pd
from dotenv import load_dotenv

load_dotenv()

try:
    import psycopg2
except ImportError:  # pragma: no cover - exercised when optional dependencies are absent
    psycopg2 = None

try:
    from pymongo import MongoClient
except ImportError:  # pragma: no cover
    MongoClient = None


POSTGRES_SOURCE_OF_TRUTH = "PostgreSQL stores structured fleet and schedule data."


@dataclass
class ConnectionStatus:
    postgres: bool = False
    mongo: bool = False
    messages: list[str] | None = None

    def __post_init__(self) -> None:
        if self.messages is None:
            self.messages = []


def _demo_vehicles() -> pd.DataFrame:
    return pd.DataFrame([
        {"vehicle_id": 1, "registration_no": "FM-101", "vehicle_type": "truck", "status": "active", "odometer_km": 84210.5, "current_latitude": 40.7128, "current_longitude": -74.0060},
        {"vehicle_id": 2, "registration_no": "FM-102", "vehicle_type": "van", "status": "active", "odometer_km": 32110.2, "current_latitude": 40.7580, "current_longitude": -73.9855},
        {"vehicle_id": 3, "registration_no": "FM-103", "vehicle_type": "car", "status": "maintenance", "odometer_km": 55980.0, "current_latitude": 40.7306, "current_longitude": -73.9352},
        {"vehicle_id": 4, "registration_no": "FM-104", "vehicle_type": "van", "status": "active", "odometer_km": 12800.7, "current_latitude": 40.6892, "current_longitude": -74.0445},
        {"vehicle_id": 5, "registration_no": "FM-105", "vehicle_type": "truck", "status": "active", "odometer_km": 112450.8, "current_latitude": 40.7831, "current_longitude": -73.9712},
    ])


def _demo_schedules() -> pd.DataFrame:
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    return pd.DataFrame([
        {"schedule_id": 1, "registration_no": "FM-101", "driver_name": "Aisha Khan", "route_code": "R-NY-BOS", "origin": "New York", "destination": "Boston", "scheduled_start": now - timedelta(days=1), "status": "completed", "departure_delay_minutes": 12.0},
        {"schedule_id": 2, "registration_no": "FM-102", "driver_name": "Daniel Brooks", "route_code": "R-NY-PHI", "origin": "New York", "destination": "Philadelphia", "scheduled_start": now - timedelta(hours=3), "status": "in_progress", "departure_delay_minutes": 10.0},
        {"schedule_id": 3, "registration_no": "FM-104", "driver_name": "Priya Shah", "route_code": "R-NY-JFK", "origin": "Fleet depot", "destination": "JFK Airport", "scheduled_start": now + timedelta(hours=2), "status": "planned", "departure_delay_minutes": None},
        {"schedule_id": 4, "registration_no": "FM-105", "driver_name": "Mateo Garcia", "route_code": "R-NY-ALB", "origin": "New York", "destination": "Albany", "scheduled_start": now + timedelta(days=1), "status": "planned", "departure_delay_minutes": None},
        {"schedule_id": 5, "registration_no": "FM-103", "driver_name": "Noah Williams", "route_code": "R-NY-EWR", "origin": "Fleet depot", "destination": "Newark Airport", "scheduled_start": now - timedelta(days=2), "status": "completed", "departure_delay_minutes": 8.0},
    ])


def _demo_maintenance() -> pd.DataFrame:
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    return pd.DataFrame([
        {"work_order_id": 1, "registration_no": "FM-101", "due_at": now + timedelta(days=14), "maintenance_type": "preventive", "priority": "normal", "status": "open", "description": "Oil, filters, and brake inspection", "estimated_cost": 650.0},
        {"work_order_id": 2, "registration_no": "FM-102", "due_at": now - timedelta(days=2), "maintenance_type": "inspection", "priority": "high", "status": "open", "description": "Annual safety inspection overdue", "estimated_cost": 300.0},
        {"work_order_id": 3, "registration_no": "FM-103", "due_at": now - timedelta(days=1), "maintenance_type": "corrective", "priority": "critical", "status": "in_progress", "description": "Replace alternator and battery", "estimated_cost": 1200.0},
        {"work_order_id": 4, "registration_no": "FM-104", "due_at": now + timedelta(days=45), "maintenance_type": "preventive", "priority": "low", "status": "open", "description": "Scheduled 20,000 km service", "estimated_cost": 480.0},
    ])


def _demo_alerts() -> pd.DataFrame:
    return pd.DataFrame([
        {"registration_no": "FM-102", "alert_type": "late_departure", "severity": "warning", "message": "Route R-NY-PHI departed late", "occurred_at": datetime.now()},
        {"registration_no": "FM-103", "alert_type": "maintenance_due", "severity": "critical", "message": "Vehicle blocked by overdue maintenance", "occurred_at": datetime.now()},
    ])


def _postgres_connect() -> Any:
    if psycopg2 is None:
        raise RuntimeError("psycopg2 is not installed")
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        dbname=os.getenv("POSTGRES_DB", "fleetmonitor"),
        user=os.getenv("POSTGRES_USER", "fleetmonitor"),
        password=os.getenv("POSTGRES_PASSWORD", "fleetmonitor"),
        connect_timeout=3,
    )


def load_data() -> tuple[dict[str, pd.DataFrame], ConnectionStatus]:
    status = ConnectionStatus()
    data = {
        "vehicles": _demo_vehicles(),
        "schedules": _demo_schedules(),
        "maintenance": _demo_maintenance(),
        "alerts": _demo_alerts(),
        "gps": _demo_vehicles()[["vehicle_id", "registration_no", "current_latitude", "current_longitude"]].rename(
            columns={"current_latitude": "latitude", "current_longitude": "longitude"}
        ),
    }
    # PostgreSQL is authoritative for structured fleet, schedule, maintenance,
    # and alert data. MongoDB is only used for GPS documents.
    try:
        with _postgres_connect() as conn:
            data["vehicles"] = pd.read_sql_query(
                "SELECT vehicle_id, registration_no, vehicle_type, status, odometer_km, current_latitude, current_longitude FROM vehicle ORDER BY registration_no",
                conn,
            )
            data["schedules"] = pd.read_sql_query("SELECT * FROM v_vehicle_schedule ORDER BY scheduled_start DESC", conn)
            data["maintenance"] = pd.read_sql_query(
                """SELECT m.work_order_id, v.registration_no, m.due_at, m.maintenance_type,
                          m.priority, m.status, m.description, m.estimated_cost
                   FROM maintenance_work_order m JOIN vehicle v ON v.vehicle_id = m.vehicle_id
                   ORDER BY m.due_at""",
                conn,
            )
            data["alerts"] = pd.read_sql_query(
                """SELECT v.registration_no, a.alert_type, a.severity, a.message, a.occurred_at
                   FROM operational_alert a LEFT JOIN vehicle v ON v.vehicle_id = a.vehicle_id
                   WHERE a.resolved_at IS NULL ORDER BY a.occurred_at DESC""",
                conn,
            )
        status.postgres = True
    except Exception as exc:  # UI should remain usable when local services are stopped.
        status.messages.append(f"PostgreSQL unavailable; using demo relational data ({exc.__class__.__name__}).")

    if MongoClient is not None:
        client = None
        try:
            client = MongoClient(os.getenv("MONGO_URI", "mongodb://localhost:27017"), serverSelectionTimeoutMS=2000)
            client.admin.command("ping")
            docs = list(client[os.getenv("MONGO_DB", "fleetmonitor")].gps_locations.find(
                {}, {"_id": 0, "vehicle_id": 1, "recorded_at": 1, "location": 1, "speed_kph": 1}
            ).sort("recorded_at", -1).limit(500))
            if docs:
                data["gps"] = pd.DataFrame([
                    {
                        "vehicle_id": int(doc["vehicle_id"]),
                        "recorded_at": doc.get("recorded_at"),
                        "latitude": doc["location"]["coordinates"][1],
                        "longitude": doc["location"]["coordinates"][0],
                        "speed_kph": doc.get("speed_kph", 0),
                    }
                    for doc in docs
                ])
            status.mongo = True
        except Exception as exc:
            status.messages.append(f"MongoDB unavailable; using demo GPS data ({exc.__class__.__name__}).")
        finally:
            if client is not None:
                client.close()
    else:
        status.messages.append("pymongo is not installed; using demo GPS data.")
    return data, status
