"""Streamlit chat and read-only charts over gold tables."""

import os

import pandas as pd
import psycopg2
import streamlit as st

DSN = f"host={os.getenv('POSTGRES_HOST', 'localhost')} port={os.getenv('POSTGRES_PORT', '5432')} dbname={os.getenv('POSTGRES_DATABASE', 'LRDB')} user={os.getenv('POSTGRES_USERNAME', 'postgres')} password={os.getenv('POSTGRES_PASSWORD', 'postgres')}"


def query(sql: str) -> pd.DataFrame:
    conn = psycopg2.connect(DSN)
    try:
        return pd.read_sql(sql, conn)
    finally:
        conn.close()


st.set_page_config(page_title="LRDB Dashboard", layout="wide")
st.title("LRDB — Logistics Dashboard")

tab1, tab2 = st.tabs(["Charts", "Chat"])

with tab1:
    try:
        df = query(
            "SELECT metric_date, loads_count, total_revenue FROM gold.route_metrics_daily ORDER BY metric_date DESC LIMIT 100"
        )
        st.line_chart(df.set_index("metric_date")[["loads_count"]])
        st.bar_chart(df.set_index("metric_date")[["total_revenue"]])
        st.dataframe(
            query(
                "SELECT customer_id, total_loads, total_revenue FROM gold.customer_summary ORDER BY total_revenue DESC LIMIT 10"
            )
        )
    except Exception as e:  # noqa: BLE001
        st.warning(f"gold tables not yet loaded: {e}")

with tab2:
    if "messages" not in st.session_state:
        st.session_state.messages = []
    for m in st.session_state.messages:
        st.chat_message(m["role"]).write(m["content"])
    if prompt := st.chat_input("Ask about loads, customers, routes"):
        st.session_state.messages.append({"role": "user", "content": prompt})
        st.chat_message("user").write(prompt)
        reply = f"Echo: {prompt} (agent at http://agent-service:8000)"
        st.session_state.messages.append({"role": "assistant", "content": reply})
        st.chat_message("assistant").write(reply)
