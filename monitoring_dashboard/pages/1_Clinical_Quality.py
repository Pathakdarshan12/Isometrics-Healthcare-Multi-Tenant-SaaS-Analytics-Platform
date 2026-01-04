import os

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta
import snowflake.connector
from typing import Dict, List

# Page configuration
st.set_page_config(
    page_title="Clinical Quality Metrics",
    page_icon="🏥",
    layout="wide"
)


@st.cache_resource
def init_connection():
    """Initialize Snowflake connection"""
    return snowflake.connector.connect(
        user = os.getenv('SNOWFLAKE_USER'),
        password = os.getenv('SNOWFLAKE_PASSWORD'),
        account = os.getenv('SNOWFLAKE_ACCOUNT'),
        warehouse = os.getenv('SNOWFLAKE_WAREHOUSE'),
        database = os.getenv('SNOWFLAKE_DATABASE'),
        schema = os.getenv('SNOWFLAKE_SCHEMA'),
        role=os.getenv('SNOWFLAKE_ROLE')
    )

@st.cache_data(ttl=600)
def run_query(query):
    """Run query and return results as DataFrame"""
    conn = init_connection()
    try:
        df = pd.read_sql(query, conn)
        df.columns = df.columns.str.lower()
        return df
    except Exception as e:
        st.error(f"Query error: {str(e)}")
        return pd.DataFrame()

@st.cache_data(ttl=300)
def load_clinical_metrics(hospital_id: str = None, days: int = 30) -> pd.DataFrame:
    """Load clinical quality metrics from Snowflake"""

    query = f"""
    SELECT
        hospital_id,
        metric_date,
        total_encounters,
        inpatient_encounters,
        emergency_encounters,
        unique_patients,
        readmissions_30day,
        readmission_rate_30day_pct,
        mortality_count,
        mortality_rate_pct,
        avg_length_of_stay,
        median_length_of_stay,
        high_risk_patients,
        medium_risk_patients,
        low_risk_patients
    FROM fct_clinical_quality_metrics
    """
    # WHERE metric_date >= DATEADD('day', -{days}, CURRENT_DATE())

    if hospital_id and hospital_id != "All Hospitals":
        query += f" AND hospital_id = '{hospital_id}'"

    query += " ORDER BY metric_date DESC"

    df = run_query(query)
    df['metric_date'] = pd.to_datetime(df['metric_date'])
    return df


@st.cache_data(ttl=300)
def load_hospital_list() -> List[str]:
    """Load list of hospitals"""
    query = """
    SELECT DISTINCT hospital_id, hospital_name
    FROM ISOMETRICS_DEV.DBT_DEV_STAGING.STG_HEALTHCARE__HOSPITALS
    ORDER BY hospital_name
    """
    df = run_query(query)
    return ["All Hospitals"] + df['hospital_id'].tolist()


def calculate_metrics_summary(df: pd.DataFrame) -> Dict:
    """Calculate summary statistics"""
    latest = df[df['metric_date'] == df['metric_date'].max()]

    return {
        'total_encounters': int(latest['total_encounters'].sum()),
        'avg_readmission_rate': float(latest['readmission_rate_30day_pct'].mean()),
        'avg_mortality_rate': float(latest['mortality_rate_pct'].mean()),
        'avg_los': float(latest['avg_length_of_stay'].mean()),
        'high_risk_patients': int(latest['high_risk_patients'].sum())
    }


# Main Dashboard
st.title("🏥 Clinical Quality Dashboard")
st.markdown("Real-time clinical quality and patient safety metrics")

# Sidebar filters
st.sidebar.header("Filters")
hospitals = load_hospital_list()
selected_hospital = st.sidebar.selectbox("Select Hospital", hospitals)
date_range = st.sidebar.slider("Days to Display", 7, 90, 30)

# Load data
with st.spinner("Loading clinical metrics..."):
    df_metrics = load_clinical_metrics(selected_hospital, date_range)

if df_metrics.empty:
    st.error("No data available for selected filters")
    st.stop()

# Calculate summary
summary = calculate_metrics_summary(df_metrics)

# KPI Cards
st.subheader("📊 Key Performance Indicators")
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric(
        "Total Encounters",
        f"{summary['total_encounters']:,}",
        help="Total patient encounters in selected period"
    )

with col2:
    st.metric(
        "30-Day Readmission Rate",
        f"{summary['avg_readmission_rate']:.1f}%",
        delta=f"{summary['avg_readmission_rate'] - 8.5:.1f}%",
        delta_color="inverse",
        help="Target: <8.5% (CMS benchmark)"
    )

with col3:
    st.metric(
        "Mortality Rate",
        f"{summary['avg_mortality_rate']:.2f}%",
        help="Inpatient mortality rate"
    )

with col4:
    st.metric(
        "Avg Length of Stay",
        f"{summary['avg_los']:.1f} days",
        help="Average inpatient length of stay"
    )

# Readmission Trend Chart
st.subheader("📈 30-Day Readmission Rate Trend")

fig_readmission = go.Figure()

# Add readmission rate line
fig_readmission.add_trace(go.Scatter(
    x=df_metrics['metric_date'],
    y=df_metrics['readmission_rate_30day_pct'],
    mode='lines+markers',
    name='Readmission Rate',
    line=dict(color='#FF6B6B', width=3)
))

# Add CMS benchmark line
fig_readmission.add_hline(
    y=8.5,
    line_dash="dash",
    line_color="green",
    annotation_text="CMS Target (8.5%)",
    annotation_position="right"
)

fig_readmission.update_layout(
    xaxis_title="Date",
    yaxis_title="Readmission Rate (%)",
    hovermode='x unified',
    height=400
)

st.plotly_chart(fig_readmission, use_container_width=True)

# Two-column layout for additional metrics
col_left, col_right = st.columns(2)

with col_left:
    st.subheader("🛏️ Length of Stay Analysis")

    fig_los = go.Figure()

    fig_los.add_trace(go.Scatter(
        x=df_metrics['metric_date'],
        y=df_metrics['avg_length_of_stay'],
        mode='lines',
        name='Average LOS',
        line=dict(color='#4ECDC4', width=2)
    ))

    fig_los.add_trace(go.Scatter(
        x=df_metrics['metric_date'],
        y=df_metrics['median_length_of_stay'],
        mode='lines',
        name='Median LOS',
        line=dict(color='#95E1D3', width=2, dash='dash')
    ))

    fig_los.update_layout(
        xaxis_title="Date",
        yaxis_title="Days",
        hovermode='x unified',
        height=350
    )

    st.plotly_chart(fig_los, use_container_width=True)

with col_right:
    st.subheader("⚠️ Patient Risk Distribution")

    latest_metrics = df_metrics[df_metrics['metric_date'] == df_metrics['metric_date'].max()]

    risk_data = pd.DataFrame({
        'Risk Category': ['High Risk', 'Medium Risk', 'Low Risk'],
        'Patient Count': [
            int(latest_metrics['high_risk_patients'].sum()),
            int(latest_metrics['medium_risk_patients'].sum()),
            int(latest_metrics['low_risk_patients'].sum())
        ]
    })

    fig_risk = px.pie(
        risk_data,
        values='Patient Count',
        names='Risk Category',
        color='Risk Category',
        color_discrete_map={
            'High Risk': '#FF6B6B',
            'Medium Risk': '#FFD93D',
            'Low Risk': '#6BCF7F'
        },
        hole=0.4
    )

    fig_risk.update_layout(height=350)
    st.plotly_chart(fig_risk, use_container_width=True)

# Volume Analysis
st.subheader("📊 Encounter Volume by Type")

fig_volume = go.Figure()

fig_volume.add_trace(go.Bar(
    x=df_metrics['metric_date'],
    y=df_metrics['inpatient_encounters'],
    name='Inpatient',
    marker_color='#667BC6'
))

fig_volume.add_trace(go.Bar(
    x=df_metrics['metric_date'],
    y=df_metrics['emergency_encounters'],
    name='Emergency',
    marker_color='#FF6B6B'
))

fig_volume.update_layout(
    barmode='stack',
    xaxis_title="Date",
    yaxis_title="Encounter Count",
    hovermode='x unified',
    height=400
)

st.plotly_chart(fig_volume, use_container_width=True)

# Data Table
with st.expander("📋 View Detailed Metrics"):
    st.dataframe(
        df_metrics.sort_values('metric_date', ascending=False),
        use_container_width=True,
        hide_index=True
    )

# Footer
st.markdown("---")
st.markdown(
    "**Data Source:** IsoMetrics Healthcare Analytics Platform | "
    f"**Last Updated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
)