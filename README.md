# FleetMonitor DBMS

FleetMonitor is an educational fleet-management system where **PostgreSQL is the relational source of truth** for structured fleet information and vehicle schedules. MongoDB complements it with high-volume GPS and flexible maintenance-log documents. It includes:

- PostgreSQL tables for vehicles, drivers, routes, schedules, GPS summaries, maintenance work orders, and alerts.
- Seed data that is safe to rerun.
- `EXPLAIN (ANALYZE, BUFFERS)` examples and indexes for common fleet queries.
- Transaction and locking demonstrations for ACID, pessimistic locking, and optimistic locking.
- MongoDB collections, validation rules, indexes, and sample GPS/maintenance documents.
- A Streamlit dashboard that uses live databases when available and automatically falls back to deterministic demo data.
- Docker Compose for local PostgreSQL and MongoDB.

## Simplest Windows run sequence

Install **Python 3.10+**, PostgreSQL, and MongoDB Server plus `mongosh`. Start both database services, open PowerShell in this folder, and run:

```powershell
py -3 -m pip install -r requirements.txt
# Optional: create .env locally and fill it with your own database settings.
# Do not commit it or paste its values into chat.
powershell -ExecutionPolicy Bypass -File .\scripts\setup_local.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\run_dashboard.ps1
```

Open <http://localhost:8501>. The setup script:

1. Creates and seeds the PostgreSQL relational source of truth.
2. Creates MongoDB GPS/maintenance collections, validators, and indexes.
3. Loads sample documents.

The script reads an existing `.env` silently and never prints its values. If PostgreSQL authentication is configured outside `.env`, `psql` may ask for its password interactively. No password is included in this repository.

### Manual commands

**Stage 1: PostgreSQL schema and seed**

```powershell
psql -h localhost -p 5432 -U fleetmonitor -d fleetmonitor -f db\postgres\01_schema.sql
psql -h localhost -p 5432 -U fleetmonitor -d fleetmonitor -f db\postgres\02_seed.sql
```

**Stage 3: MongoDB collections and sample documents**

```powershell
mongosh "mongodb://localhost:27017" --file db\mongo\01_setup.js
mongosh "mongodb://localhost:27017" --file db\mongo\02_sample_documents.js
```

**Dashboard**

```powershell
py -3 -m streamlit run app\dashboard.py
```

If PostgreSQL or MongoDB is unavailable, the dashboard warns you and uses deterministic demo data for the unavailable source.

## Project layout

| Path | Purpose |
| --- | --- |
| `db/postgres/01_schema.sql` | PostgreSQL schema, constraints, indexes, views, and helper functions |
| `db/postgres/02_seed.sql` | Idempotent sample fleet data |
| `db/postgres/03_optimization.sql` | Query plans, index demonstrations, and production query patterns |
| `db/postgres/04_concurrency.sql` | Two-session transaction and locking labs |
| `db/postgres/05_distribution.sql` | Practical hybrid architecture and PostgreSQL distribution examples |
| `db/mongo/01_setup.js` | MongoDB collections, validators, and indexes |
| `db/mongo/02_sample_documents.js` | GPS and maintenance sample documents |
| `app/dashboard.py` | Streamlit dashboard |
| `app/data_access.py` | Safe parameterized PostgreSQL/MongoDB access with graceful fallback |
| `scripts/setup_local.ps1` | Safe Windows setup for PostgreSQL Stage 1 and MongoDB Stage 3 |
| `scripts/run_dashboard.ps1` | Windows dashboard launcher |
| `tests/test_smoke.py` | Offline smoke tests for structure and demo data |
| `scripts/smoke_check.py` | Human-friendly smoke-check runner |

## Database configuration

`.env.example` contains local defaults:

```text
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=fleetmonitor
POSTGRES_USER=fleetmonitor
POSTGRES_PASSWORD=fleetmonitor
MONGO_URI=mongodb://localhost:27017
MONGO_DB=fleetmonitor
```

The application connects to PostgreSQL first for vehicles, schedules, maintenance work orders, and operational alerts. Those dashboard datasets are never read from MongoDB. MongoDB is used only for GPS documents. The application never builds SQL by string concatenation; dashboard database failures are surfaced in the UI before demo mode is selected.

## Stage guide

### 1. PostgreSQL relational source of truth

PostgreSQL is the system of record for fleet identity, schedules, routes, assignments, maintenance work orders, fuel transactions, and operational alerts. The normalized relational model uses foreign keys, check constraints, uniqueness constraints, and timestamp defaults to protect data quality. `v_vehicle_schedule` and `v_vehicle_health` are PostgreSQL reporting surfaces consumed by the dashboard.

### 2. Query optimization

Run `db/postgres/03_optimization.sql` in a non-production copy of the database. It demonstrates:

- `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)`.
- Partial and composite indexes for active schedules and maintenance due dates.
- A covering index for date-window schedule lookups.
- Keyset pagination instead of expensive deep `OFFSET`.
- A comparison of a correlated subquery and a pre-aggregated join.

Do not blindly create every example index in production; validate selectivity and write overhead with real workload statistics.

### 3. MongoDB document data

GPS points are time-series-style documents partitioned by vehicle. Maintenance logs retain flexible inspection findings and parts arrays. Validators enforce required fields while allowing domain-specific extensions. TTL indexes are included as a documented retention option, not enabled by default.

### 4. Concurrency

`04_concurrency.sql` is intentionally split into Session A and Session B blocks. It demonstrates:

- Atomic balance-like status changes and rollback.
- `SELECT ... FOR UPDATE` pessimistic locking.
- Version-column optimistic locking with an update row-count check.
- Isolation-level observations.

Run each block in separate `psql` sessions where noted.

### 5. Distributed design

`05_distribution.sql` documents the hybrid PostgreSQL/MongoDB boundary, outbox/event propagation, read replicas, partitioning, MongoDB replica sets, sharding keys, and consistency trade-offs. It includes runnable PostgreSQL partitioning and outbox examples plus MongoDB commands for replica-set and sharding planning.

### 6. Python dashboard

The dashboard provides:

- Fleet status and utilization metrics.
- Schedule and on-time performance views.
- Vehicle GPS tracking map.
- Maintenance due/overdue monitoring.
- Operational alerts.

If either database is unavailable, the app displays a warning and uses deterministic sample data, so classroom demonstrations and UI development do not require infrastructure.

## Testing

Offline tests do not require Docker:

```powershell
python -m unittest discover -s tests -v
```

The smoke script additionally attempts live connectivity when the Python drivers and databases are available:

```powershell
python scripts\smoke_check.py
```

## Reset local databases

This removes only the named Compose volumes:

```powershell
docker compose down -v
docker compose up -d postgres mongo
```
