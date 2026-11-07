# FleetMonitor single-file dashboard
#
# Do not store the PostgreSQL password in this file.
# Set it locally before starting:
#
# PowerShell:
# $env:POSTGRES_PASSWORD = "your-local-password"
#
# MongoDB databases:
#   fleetmonitor
#   fleetmonitor-2
#   fleetmonitor-3
#
# PostgreSQL databases:
#   Fleet-Monitor
#   Fleet-Monitor2
#   Fleet-Monitor3

import os
from datetime import datetime

import pandas as pd
import plotly.express as px
import psycopg2
import streamlit as st
from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv()

st.set_page_config(
    page_title="FleetMonitor Dashboard",
    page_icon="🚚",
    layout="wide",
)

# ------------------------------------------------------------
# Fixed database configuration
# ------------------------------------------------------------

POSTGRES_HOST = "localhost"
POSTGRES_PORT = 5432
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "0440")

POSTGRES_DATABASES = [
    "Fleet-Monitor",
    "Fleet-Monitor2",
    "Fleet-Monitor3",
]

MONGO_URI = os.getenv(
    "MONGO_URI",
    "mongodb://localhost:27017",
)

MONGO_DATABASES = [
    "fleetmonitor",
    "fleetmonitor-2",
    "fleetmonitor-3",
]


# ------------------------------------------------------------
# Styling
# ------------------------------------------------------------

st.markdown(
    """
    <style>
    @import url(
        'https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap'
    );

    html, body, [class*="css"] {
        font-family: "Inter", sans-serif;
    }

    .stApp {
        background:
            radial-gradient(
                circle at 10% 10%,
                rgba(0, 214, 143, 0.13),
                transparent 30%
            ),
            radial-gradient(
                circle at 90% 15%,
                rgba(0, 153, 255, 0.14),
                transparent 32%
            ),
            linear-gradient(135deg, #07111f 0%, #101827 100%);
    }

    [data-testid="stSidebar"] {
        background: #0a1626;
    }

    .hero {
        padding: 28px;
        border-radius: 24px;
        margin-bottom: 24px;
        background:
            linear-gradient(
                120deg,
                rgba(0, 214, 143, 0.25),
                rgba(0, 153, 255, 0.22),
                rgba(132, 0, 255, 0.22)
            );
        border: 1px solid rgba(255, 255, 255, 0.16);
        box-shadow: 0 18px 50px rgba(0, 0, 0, 0.28);
        animation: glow 5s ease-in-out infinite alternate;
    }

    .hero-title {
        font-size: 42px;
        font-weight: 800;
        letter-spacing: -1px;
        background: linear-gradient(90deg, #65fbd2, #6bbcff, #d6a5ff);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
    }

    .hero-subtitle {
        color: #d1d9e8;
        margin-top: 8px;
    }

    .section-title {
        padding: 12px 16px;
        margin-top: 24px;
        margin-bottom: 16px;
        border-left: 5px solid #42e7b0;
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.07);
        font-size: 22px;
        font-weight: 700;
    }

    div[data-testid="stMetric"] {
        padding: 18px;
        border-radius: 18px;
        background: rgba(255, 255, 255, 0.08);
        border: 1px solid rgba(255, 255, 255, 0.12);
        box-shadow: 0 10px 24px rgba(0, 0, 0, 0.2);
        transition: 0.25s ease;
    }

    div[data-testid="stMetric"]:hover {
        transform: translateY(-5px);
        box-shadow: 0 18px 35px rgba(0, 214, 143, 0.2);
    }

    @keyframes glow {
        from {
            transform: translateY(0);
        }
        to {
            transform: translateY(-4px);
        }
    }
    </style>
    """,
    unsafe_allow_html=True,
)


# ------------------------------------------------------------
# PostgreSQL functions
# ------------------------------------------------------------

def postgres_config(database_name):
    return {
        "host": POSTGRES_HOST,
        "port": POSTGRES_PORT,
        "dbname": database_name,
        "user": POSTGRES_USER,
        "password": POSTGRES_PASSWORD,
        "connect_timeout": 5,
    }


def postgres_connect(database_name):
    return psycopg2.connect(
        **postgres_config(database_name)
    )


def postgres_query(database_name, query, params=None):
    connection = None

    try:
        connection = postgres_connect(database_name)

        return pd.read_sql_query(
            query,
            connection,
            params=params,
        )

    finally:
        if connection is not None:
            connection.close()


def postgres_status(database_name):
    connection = None

    try:
        connection = postgres_connect(database_name)
        cursor = connection.cursor()
        cursor.execute("SELECT version()")
        version = cursor.fetchone()[0]
        cursor.close()

        return True, version

    except Exception as error:
        return False, str(error)

    finally:
        if connection is not None:
            connection.close()


@st.cache_data(ttl=30)
def load_postgres_kpis(database_name):
    query = """
        SELECT
            (SELECT COUNT(*) FROM vehicles)
                AS total_vehicles,

            (SELECT COUNT(*)
             FROM vehicles
             WHERE status = 'active')
                AS active_vehicles,

            (SELECT COUNT(*)
             FROM vehicles
             WHERE status = 'maintenance')
                AS maintenance_vehicles,

            (SELECT COUNT(*) FROM schedules)
                AS total_schedules,

            (SELECT COUNT(*)
             FROM maintenance_work_orders)
                AS total_work_orders,

            CASE
                WHEN to_regclass(
                    'public.vehicle_telemetry'
                ) IS NULL
                THEN 0
                ELSE (
                    SELECT COUNT(*)
                    FROM vehicle_telemetry
                )
            END AS total_telemetry_records
    """

    return postgres_query(
        database_name,
        query,
    ).iloc[0].to_dict()


@st.cache_data(ttl=30)
def load_vehicle_status(database_name):
    query = """
        SELECT
            status,
            COUNT(*) AS vehicle_count
        FROM vehicles
        GROUP BY status
        ORDER BY status
    """

    return postgres_query(database_name, query)


@st.cache_data(ttl=30)
def load_vehicle_types(database_name):
    query = """
        SELECT
            vehicle_type,
            COUNT(*) AS vehicle_count
        FROM vehicles
        GROUP BY vehicle_type
        ORDER BY vehicle_type
    """

    return postgres_query(database_name, query)


@st.cache_data(ttl=30)
def load_telemetry_summary(database_name):
    query = """
        SELECT
            recorded_at::date AS telemetry_date,
            COUNT(*) AS record_count,
            ROUND(AVG(speed_kmh), 2)
                AS average_speed,
            ROUND(AVG(fuel_level), 2)
                AS average_fuel,
            ROUND(AVG(engine_temperature), 2)
                AS average_temperature
        FROM vehicle_telemetry
        GROUP BY recorded_at::date
        ORDER BY telemetry_date
    """

    return postgres_query(database_name, query)


@st.cache_data(ttl=30)
def load_telemetry_rows(database_name, limit_value):
    query = """
        SELECT
            t.telemetry_id,
            t.vehicle_id,
            v.registration_number,
            t.recorded_at,
            t.latitude,
            t.longitude,
            t.speed_kmh,
            t.fuel_level,
            t.engine_temperature
        FROM vehicle_telemetry t
        JOIN vehicles v
            ON v.vehicle_id = t.vehicle_id
        ORDER BY t.recorded_at DESC
        LIMIT %s
    """

    return postgres_query(
        database_name,
        query,
        (limit_value,),
    )


@st.cache_data(ttl=30)
def load_schedules(database_name):
    query = """
        SELECT
            s.schedule_id,
            v.registration_number,
            r.route_name,
            r.origin,
            r.destination,
            s.scheduled_start,
            s.scheduled_end,
            s.schedule_status
        FROM schedules s
        JOIN vehicles v
            ON v.vehicle_id = s.vehicle_id
        LEFT JOIN routes r
            ON r.route_id = s.route_id
        ORDER BY s.scheduled_start DESC
        LIMIT 500
    """

    return postgres_query(database_name, query)


@st.cache_data(ttl=30)
def load_work_orders(database_name):
    query = """
        SELECT
            w.work_order_id,
            v.registration_number,
            w.maintenance_type,
            w.description,
            w.cost,
            w.opened_at,
            w.completed_at,
            w.work_status
        FROM maintenance_work_orders w
        JOIN vehicles v
            ON v.vehicle_id = w.vehicle_id
        ORDER BY w.opened_at DESC
        LIMIT 500
    """

    return postgres_query(database_name, query)


# ------------------------------------------------------------
# MongoDB functions
# ------------------------------------------------------------

@st.cache_resource
def mongo_client():
    client = MongoClient(
        MONGO_URI,
        serverSelectionTimeoutMS=5000,
    )
    client.admin.command("ping")
    return client


def mongo_status():
    try:
        client = mongo_client()
        client.admin.command("ping")
        return True, "Connected"
    except Exception as error:
        return False, str(error)


@st.cache_data(ttl=30)
def mongo_counts(database_name):
    client = mongo_client()
    database = client[database_name]

    gps_count = database[
        "gps_locations"
    ].count_documents({})

    maintenance_count = database[
        "maintenance_logs"
    ].count_documents({})

    return {
        "gps_locations": gps_count,
        "maintenance_logs": maintenance_count,
        "total": gps_count + maintenance_count,
    }


@st.cache_data(ttl=30)
def load_mongo_gps(database_name, limit_value):
    client = mongo_client()
    collection = client[
        database_name
    ]["gps_locations"]

    documents = list(
        collection.find(
            {},
            {
                "_id": 0,
                "vehicle_id": 1,
                "recorded_at": 1,
                "location": 1,
                "latitude": 1,
                "longitude": 1,
                "speed_kph": 1,
                "speed_kmh": 1,
                "heading": 1,
                "ignition": 1,
                "source": 1,
            },
        )
        .sort("recorded_at", -1)
        .limit(limit_value)
    )

    rows = []

    for document in documents:
        location = document.pop("location", {})

        if isinstance(location, dict):
            coordinates = location.get(
                "coordinates",
                [],
            )

            if len(coordinates) >= 2:
                document["longitude"] = coordinates[0]
                document["latitude"] = coordinates[1]

        rows.append(document)

    return pd.DataFrame(rows)


@st.cache_data(ttl=30)
def load_mongo_maintenance(database_name, limit_value):
    client = mongo_client()
    collection = client[
        database_name
    ]["maintenance_logs"]

    documents = list(
        collection.find(
            {},
            {
                "_id": 0,
                "vehicle_id": 1,
                "logged_at": 1,
                "event_type": 1,
                "technician": 1,
                "findings": 1,
                "parts": 1,
                "odometer_km": 1,
            },
        )
        .sort("logged_at", -1)
        .limit(limit_value)
    )

    rows = []

    for document in documents:
        findings = document.get("findings")

        if isinstance(findings, list):
            document["findings"] = "; ".join(
                str(item)
                for item in findings
            )

        parts = document.get("parts")

        if isinstance(parts, list):
            document["parts_count"] = len(parts)

        rows.append(document)

    return pd.DataFrame(rows)


# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

st.markdown(
    """
    <div class="hero">
        <div class="hero-title">🚚 FleetMonitor</div>
        <div class="hero-subtitle">
            PostgreSQL databases and MongoDB databases monitoring dashboard
        </div>
    </div>
    """,
    unsafe_allow_html=True,
)

if st.sidebar.button("Refresh dashboard"):
    st.cache_data.clear()
    st.rerun()


# ------------------------------------------------------------
# Sidebar selectors
# ------------------------------------------------------------

st.sidebar.header("PostgreSQL Database")

selected_postgres = st.sidebar.selectbox(
    "Select PostgreSQL database",
    POSTGRES_DATABASES,
)

st.sidebar.header("MongoDB Database")

selected_mongo = st.sidebar.selectbox(
    "Select MongoDB database",
    MONGO_DATABASES,
)

rows_to_display = st.sidebar.slider(
    "Rows to display",
    min_value=10,
    max_value=1000,
    value=100,
    step=10,
)


# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

postgres_online, postgres_message = postgres_status(
    selected_postgres
)

mongo_online, mongo_message = mongo_status()

st.sidebar.subheader("Connection Status")

if postgres_online:
    st.sidebar.success(
        f"{selected_postgres}: connected"
    )
else:
    st.sidebar.error(
        f"{selected_postgres}: unavailable"
    )
    st.sidebar.caption(postgres_message[:300])

if mongo_online:
    st.sidebar.success("MongoDB: connected")
else:
    st.sidebar.error("MongoDB: unavailable")
    st.sidebar.caption(mongo_message[:300])

if not postgres_online:
    st.error(
        f"Cannot connect to PostgreSQL database "
        f"'{selected_postgres}'."
    )
    st.code(str(postgres_message))
    st.stop()

if not mongo_online:
    st.warning(
        "MongoDB is unavailable. PostgreSQL sections remain available."
    )


# ------------------------------------------------------------
# PostgreSQL dashboard
# ------------------------------------------------------------

st.markdown(
    '<div class="section-title">PostgreSQL Fleet Data</div>',
    unsafe_allow_html=True,
)

try:
    kpis = load_postgres_kpis(selected_postgres)

    col1, col2, col3 = st.columns(3)
    col4, col5, col6 = st.columns(3)

    col1.metric(
        "Total Vehicles",
        f"{int(kpis['total_vehicles']):,}",
    )

    col2.metric(
        "Active Vehicles",
        f"{int(kpis['active_vehicles']):,}",
    )

    col3.metric(
        "Vehicles in Maintenance",
        f"{int(kpis['maintenance_vehicles']):,}",
    )

    col4.metric(
        "Schedules",
        f"{int(kpis['total_schedules']):,}",
    )

    col5.metric(
        "Work Orders",
        f"{int(kpis['total_work_orders']):,}",
    )

    col6.metric(
        "Telemetry Records",
        f"{int(kpis['total_telemetry_records']):,}",
    )

except Exception as error:
    st.error("Could not load PostgreSQL data.")
    st.exception(error)


try:
    vehicle_status = load_vehicle_status(
        selected_postgres
    )
    vehicle_types = load_vehicle_types(
        selected_postgres
    )

    col1, col2 = st.columns(2)

    with col1:
        if not vehicle_status.empty:
            chart = px.pie(
                vehicle_status,
                names="status",
                values="vehicle_count",
                hole=0.45,
                title="Vehicle Status",
            )

            st.plotly_chart(
                chart,
                use_container_width=True,
            )

    with col2:
        if not vehicle_types.empty:
            chart = px.bar(
                vehicle_types,
                x="vehicle_type",
                y="vehicle_count",
                color="vehicle_type",
                title="Vehicles by Type",
            )

            st.plotly_chart(
                chart,
                use_container_width=True,
            )

except Exception as error:
    st.warning("Vehicle charts could not be loaded.")
    st.caption(str(error))


try:
    telemetry_summary = load_telemetry_summary(
        selected_postgres
    )

    if not telemetry_summary.empty:
        st.subheader("Telemetry Analytics")

        chart = px.area(
            telemetry_summary,
            x="telemetry_date",
            y="record_count",
            markers=True,
            title="Telemetry Records Per Day",
        )

        st.plotly_chart(
            chart,
            use_container_width=True,
        )

except Exception as error:
    st.warning("Telemetry analytics could not be loaded.")
    st.caption(str(error))


st.subheader("Telemetry Preview")

try:
    telemetry_rows = load_telemetry_rows(
        selected_postgres,
        rows_to_display,
    )

    if telemetry_rows.empty:
        st.info("No telemetry records found.")
    else:
        st.dataframe(
            telemetry_rows,
            use_container_width=True,
            hide_index=True,
        )

except Exception as error:
    st.warning("Telemetry data could not be loaded.")
    st.caption(str(error))


st.subheader("Schedules")

try:
    schedules = load_schedules(
        selected_postgres
    )

    if schedules.empty:
        st.info("No schedules found.")
    else:
        st.dataframe(
            schedules,
            use_container_width=True,
            hide_index=True,
        )

except Exception as error:
    st.warning("Schedules could not be loaded.")
    st.caption(str(error))


st.subheader("Maintenance Work Orders")

try:
    work_orders = load_work_orders(
        selected_postgres
    )

    if work_orders.empty:
        st.info("No work orders found.")
    else:
        status_data = (
            work_orders.groupby("work_status")
            .size()
            .reset_index(name="count")
        )

        chart = px.bar(
            status_data,
            x="work_status",
            y="count",
            color="work_status",
            title="Work Orders by Status",
        )

        st.plotly_chart(
            chart,
            use_container_width=True,
        )

        st.dataframe(
            work_orders,
            use_container_width=True,
            hide_index=True,
        )

except Exception as error:
    st.warning("Work orders could not be loaded.")
    st.caption(str(error))


# ------------------------------------------------------------
# MongoDB dashboard
# ------------------------------------------------------------

st.markdown(
    '<div class="section-title">MongoDB Data</div>',
    unsafe_allow_html=True,
)

if mongo_online:
    try:
        counts = mongo_counts(
            selected_mongo
        )

        col1, col2, col3 = st.columns(3)

        col1.metric(
            "GPS Documents",
            f"{counts['gps_locations']:,}",
        )

        col2.metric(
            "Maintenance Documents",
            f"{counts['maintenance_logs']:,}",
        )

        col3.metric(
            "Total Documents",
            f"{counts['total']:,}",
        )

    except Exception as error:
        st.error("Could not count MongoDB documents.")
        st.exception(error)

    st.subheader(
        f"GPS Locations · {selected_mongo}"
    )

    try:
        gps_data = load_mongo_gps(
            selected_mongo,
            rows_to_display,
        )

        if gps_data.empty:
            st.info("No GPS documents found.")
        else:
            if {
                "latitude",
                "longitude",
            }.issubset(gps_data.columns):
                map_data = gps_data.dropna(
                    subset=[
                        "latitude",
                        "longitude",
                    ]
                )

                if not map_data.empty:
                    st.map(
                        map_data.rename(
                            columns={
                                "latitude": "lat",
                                "longitude": "lon",
                            }
                        )[["lat", "lon"]]
                    )

            st.dataframe(
                gps_data,
                use_container_width=True,
                hide_index=True,
            )

    except Exception as error:
        st.warning("GPS documents could not be loaded.")
        st.caption(str(error))

    st.subheader(
        f"Maintenance Logs · {selected_mongo}"
    )

    try:
        maintenance_data = load_mongo_maintenance(
            selected_mongo,
            rows_to_display,
        )

        if maintenance_data.empty:
            st.info("No maintenance logs found.")
        else:
            if "event_type" in maintenance_data.columns:
                event_data = (
                    maintenance_data.groupby("event_type")
                    .size()
                    .reset_index(name="count")
                )

                chart = px.bar(
                    event_data,
                    x="event_type",
                    y="count",
                    color="event_type",
                    title="Maintenance Events",
                )

                st.plotly_chart(
                    chart,
                    use_container_width=True,
                )

            st.dataframe(
                maintenance_data,
                use_container_width=True,
                hide_index=True,
            )

    except Exception as error:
        st.warning(
            "Maintenance documents could not be loaded."
        )
        st.caption(str(error))


# ------------------------------------------------------------
# Footer
# ------------------------------------------------------------

st.divider()

st.caption(
    "Active PostgreSQL database: "
    + selected_postgres
    + " | Active MongoDB database: "
    + selected_mongo
    + " | Refreshed: "
    + datetime.now().strftime("%Y-%m-%d %H:%M:%S")
)