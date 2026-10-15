from __future__ import annotations

import pandas as pd
import streamlit as st

from app.data_access import POSTGRES_SOURCE_OF_TRUTH, load_data

st.set_page_config(page_title="FleetMonitor", page_icon="🚚", layout="wide")
st.title("FleetMonitor")
st.caption("Operational fleet visibility across schedules, GPS, maintenance, and alerts")
st.caption(f"Relational source of truth: {POSTGRES_SOURCE_OF_TRUTH}")

data, connection_status = load_data()
for message in connection_status.messages or []:
    st.warning(message)
if connection_status.postgres and connection_status.mongo:
    st.success("Connected to PostgreSQL and MongoDB.")
elif connection_status.postgres:
    st.info("Connected to PostgreSQL. GPS is running from demo/fallback data.")
else:
    st.info("Demo mode is active. Start Docker services for live database data.")

vehicles = data["vehicles"].copy()
schedules = data["schedules"].copy()
maintenance = data["maintenance"].copy()
alerts = data["alerts"].copy()
gps = data["gps"].copy()

active_count = int((vehicles["status"] == "active").sum())
maintenance_count = int((vehicles["status"] == "maintenance").sum())
completed = int((schedules["status"] == "completed").sum())
late = int((pd.to_numeric(schedules["departure_delay_minutes"], errors="coerce") > 0).sum())
overdue = int(((pd.to_datetime(maintenance["due_at"]) < pd.Timestamp.now()) & maintenance["status"].isin(["open", "in_progress"])).sum())

metric_cols = st.columns(5)
metric_cols[0].metric("Fleet size", len(vehicles))
metric_cols[1].metric("Active vehicles", active_count)
metric_cols[2].metric("In maintenance", maintenance_count)
metric_cols[3].metric("Completed trips", completed)
metric_cols[4].metric("Overdue work orders", overdue)

tab_overview, tab_tracking, tab_maintenance, tab_schedules = st.tabs(["Overview", "Live tracking", "Maintenance", "Schedules"])

with tab_overview:
    left, right = st.columns(2)
    with left:
        st.subheader("Vehicle status")
        st.bar_chart(vehicles["status"].value_counts())
    with right:
        st.subheader("Trip status")
        st.bar_chart(schedules["status"].value_counts())
    st.subheader("Open operational alerts")
    if alerts.empty:
        st.success("No unresolved alerts.")
    else:
        st.dataframe(alerts, use_container_width=True, hide_index=True)

with tab_tracking:
    st.subheader("Latest vehicle positions")
    tracking = gps.merge(vehicles[["vehicle_id", "registration_no", "status"]], on="vehicle_id", how="left")
    if not tracking.empty:
        st.map(tracking.rename(columns={"latitude": "lat", "longitude": "lon"})[["lat", "lon"]])
        st.dataframe(tracking, use_container_width=True, hide_index=True)
    else:
        st.info("No GPS points available.")

with tab_maintenance:
    st.subheader("Maintenance due and cost")
    maintenance["due_at"] = pd.to_datetime(maintenance["due_at"])
    maintenance["state"] = maintenance.apply(
        lambda row: "overdue" if row["status"] in ("open", "in_progress") and row["due_at"] < pd.Timestamp.now() else row["status"],
        axis=1,
    )
    st.dataframe(maintenance.sort_values("due_at"), use_container_width=True, hide_index=True)
    st.bar_chart(maintenance.groupby("state")["estimated_cost"].sum())

with tab_schedules:
    st.subheader("Schedule performance")
    schedules["scheduled_start"] = pd.to_datetime(schedules["scheduled_start"])
    filter_status = st.multiselect("Filter schedule status", sorted(schedules["status"].dropna().unique()), default=sorted(schedules["status"].dropna().unique()))
    filtered = schedules[schedules["status"].isin(filter_status)]
    st.dataframe(filtered.sort_values("scheduled_start", ascending=False), use_container_width=True, hide_index=True)
    avg_delay = pd.to_numeric(filtered["departure_delay_minutes"], errors="coerce").dropna()
    if not avg_delay.empty:
        st.metric("Average departure delay", f"{avg_delay.mean():.1f} minutes")
    st.caption(f"Late departures in loaded data: {late}")
