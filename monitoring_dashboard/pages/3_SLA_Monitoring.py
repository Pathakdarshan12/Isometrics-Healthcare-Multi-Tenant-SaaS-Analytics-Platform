import os

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime
import snowflake.connector

# Page configuration
st.set_page_config(
    page_title="SLA Monitoring",
    page_icon="⚡",
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


@st.cache_data(ttl=60)
def load_sla_metrics(hospital_id: str = None):
    """Load SLA monitoring metrics"""
    query = """
    SELECT
        hospital_id,
        check_timestamp,
        encounters_freshness_minutes,
        patients_last_load,
        billing_last_load,
        freshness_sla_status,
        total_encounters,
        total_patients,
        data_quality_score_pct,
        quality_sla_status,
        invalid_los_count,
        invalid_charges_count,
        invalid_dates_count,
        overall_sla_status
    FROM ISOMETRICS_DEV.DBT_DEV_MARTS.fct_sla_monitoring
    ORDER BY check_timestamp DESC
    """

    if hospital_id and hospital_id != "All Hospitals":
        query = query.replace("ORDER BY", f"WHERE hospital_id = '{hospital_id}' ORDER BY")

    df = run_query(query)
    df['check_timestamp'] = pd.to_datetime(df['check_timestamp'])
    return df


@st.cache_data(ttl=300)
def load_hospital_list():
    """Load list of hospitals"""
    query = "SELECT DISTINCT hospital_id, hospital_name  FROM ISOMETRICS_DEV.DBT_DEV_STAGING.stg_healthcare__hospitals ORDER BY hospital_name"
    df = run_query(query)
    return ["All Hospitals"] + df['hospital_id'].tolist()


def get_status_color(status: str) -> str:
    """Return color based on SLA status"""
    colors = {
        'COMPLIANT': '#2ECC71',
        'WARNING': '#F39C12',
        'BREACH': '#E74C3C'
    }
    return colors.get(status, '#95A5A6')


def create_status_badge(status: str) -> str:
    """Create HTML badge for status"""
    color = get_status_color(status)
    return f"""
    <span style="
        background-color: {color};
        color: white;
        padding: 5px 15px;
        border-radius: 20px;
        font-weight: bold;
        font-size: 14px;
    ">{status}</span>
    """


# Main Dashboard
st.title("⚡ SLA Monitoring Dashboard")
st.markdown("Real-time data quality and SLA compliance tracking")

# Sidebar filters
st.sidebar.header("Filters")
hospitals = load_hospital_list()
selected_hospital = st.sidebar.selectbox("Select Hospital", hospitals)

# Auto-refresh toggle
auto_refresh = st.sidebar.checkbox("Auto-refresh (60s)", value=False)
if auto_refresh:
    st.sidebar.info("Dashboard will refresh every 60 seconds")

# Load data
with st.spinner("Loading SLA metrics..."):
    df_sla = load_sla_metrics(selected_hospital)

if df_sla.empty:
    st.error("No SLA data available")
    st.stop()

# Get latest snapshot
latest = df_sla.iloc[0]

# Overall Status Banner
st.subheader("🎯 Overall SLA Status")

status_color = get_status_color(latest['overall_sla_status'])
st.markdown(
    f"""
    <div style="
        background-color: {status_color};
        color: white;
        padding: 20px;
        border-radius: 10px;
        text-align: center;
        font-size: 24px;
        font-weight: bold;
        margin-bottom: 20px;
    ">
        {latest['overall_sla_status']}
    </div>
    """,
    unsafe_allow_html=True
)

# Key Metrics
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric(
        "Data Freshness",
        f"{int(latest['encounters_freshness_minutes'])} min",
        delta=f"{240 - int(latest['encounters_freshness_minutes'])} to SLA",
        delta_color="normal",
        help="Target: <240 minutes (4 hours)"
    )
    st.markdown(create_status_badge(latest['freshness_sla_status']), unsafe_allow_html=True)

with col2:
    st.metric(
        "Data Quality Score",
        f"{latest['data_quality_score_pct']:.1f}%",
        delta=f"{latest['data_quality_score_pct'] - 99:.1f}%",
        delta_color="normal",
        help="Target: >99%"
    )
    st.markdown(create_status_badge(latest['quality_sla_status']), unsafe_allow_html=True)

with col3:
    st.metric(
        "Total Encounters",
        f"{int(latest['total_encounters']):,}",
        help="Total encounters in system"
    )

with col4:
    st.metric(
        "Data Quality Errors",
        int(latest['invalid_los_count'] + latest['invalid_charges_count'] + latest['invalid_dates_count']),
        help="Total data quality violations"
    )

# SLA Status Distribution
st.subheader("📊 SLA Compliance by Hospital")

if selected_hospital == "All Hospitals":
    sla_summary = df_sla.groupby('overall_sla_status').size().reset_index(name='count')

    fig_status = px.pie(
        sla_summary,
        values='count',
        names='overall_sla_status',
        color='overall_sla_status',
        color_discrete_map={
            'COMPLIANT': '#2ECC71',
            'WARNING': '#F39C12',
            'BREACH': '#E74C3C'
        },
        hole=0.4
    )

    fig_status.update_layout(height=350)
    st.plotly_chart(fig_status, use_container_width=True)

# Data Freshness Timeline
st.subheader("⏰ Data Freshness Over Time")

# Get historical data (last 24 hours)
# Make datetime timezone-aware to match the DataFrame
from datetime import timezone

recent_df = df_sla[df_sla['check_timestamp'] >= pd.Timestamp.now(tz='UTC') - pd.Timedelta(hours=24)]

fig_freshness = go.Figure()

fig_freshness.add_trace(go.Scatter(
    x=recent_df['check_timestamp'],
    y=recent_df['encounters_freshness_minutes'],
    mode='lines+markers',
    name='Freshness (minutes)',
    line=dict(color='#3498DB', width=2),
    marker=dict(
        size=8,
        color=recent_df['freshness_sla_status'].map({
            'COMPLIANT': '#2ECC71',
            'WARNING': '#F39C12',
            'BREACH': '#E74C3C'
        })
    )
))

# Add SLA thresholds
fig_freshness.add_hline(
    y=240,
    line_dash="dash",
    line_color="green",
    annotation_text="SLA Target (4 hours)"
)

fig_freshness.add_hline(
    y=360,
    line_dash="dash",
    line_color="orange",
    annotation_text="Warning Level (6 hours)"
)

fig_freshness.update_layout(
    xaxis_title="Time",
    yaxis_title="Freshness (minutes)",
    hovermode='x unified',
    height=400
)

st.plotly_chart(fig_freshness, use_container_width=True)

# Data Quality Breakdown
col_left, col_right = st.columns(2)

with col_left:
    st.subheader("🔍 Data Quality Errors by Type")

    error_data = pd.DataFrame({
        'Error Type': ['Invalid LOS', 'Invalid Charges', 'Invalid Dates'],
        'Count': [
            int(latest['invalid_los_count']),
            int(latest['invalid_charges_count']),
            int(latest['invalid_dates_count'])
        ]
    })

    fig_errors = px.bar(
        error_data,
        x='Error Type',
        y='Count',
        color='Error Type',
        color_discrete_sequence=['#E74C3C', '#E67E22', '#F39C12'],
        text='Count'
    )

    fig_errors.update_traces(textposition='outside')
    fig_errors.update_layout(
        showlegend=False,
        yaxis_title="Error Count",
        height=350
    )

    st.plotly_chart(fig_errors, use_container_width=True)

with col_right:
    st.subheader("📈 Data Quality Score Trend")

    fig_quality = go.Figure()

    fig_quality.add_trace(go.Scatter(
        x=recent_df['check_timestamp'],
        y=recent_df['data_quality_score_pct'],
        mode='lines+markers',
        name='Quality Score',
        line=dict(color='#9B59B6', width=2),
        fill='tozeroy',
        fillcolor='rgba(155, 89, 182, 0.1)'
    ))

    fig_quality.add_hline(
        y=99,
        line_dash="dash",
        line_color="green",
        annotation_text="Target (99%)"
    )

    fig_quality.update_layout(
        xaxis_title="Time",
        yaxis_title="Quality Score (%)",
        yaxis_range=[95, 100],
        hovermode='x unified',
        height=350
    )

    st.plotly_chart(fig_quality, use_container_width=True)

# Hospital-Level SLA Status Table
st.subheader("🏥 Hospital-Level SLA Status")

if selected_hospital == "All Hospitals":
    # Show all hospitals
    hospital_status = df_sla.groupby('hospital_id').first().reset_index()

    display_cols = [
        'hospital_id',
        'overall_sla_status',
        'encounters_freshness_minutes',
        'data_quality_score_pct',
        'total_encounters'
    ]

    status_df = hospital_status[display_cols].copy()
    status_df.columns = ['Hospital ID', 'SLA Status', 'Freshness (min)', 'Quality Score (%)', 'Encounters']


    # Color code the status column
    def highlight_status(row):
        colors = {
            'COMPLIANT': 'background-color: #D5F4E6',
            'WARNING': 'background-color: #FCF3CF',
            'BREACH': 'background-color: #F5B7B1'
        }
        return [colors.get(row['SLA Status'], '') if col == 'SLA Status' else '' for col in row.index]


    styled_df = status_df.style.apply(highlight_status, axis=1)
    st.dataframe(styled_df, use_container_width=True, hide_index=True)
else:
    st.info(f"Viewing SLA metrics for: {selected_hospital}")

# Alerts Section
st.subheader("🚨 Active Alerts")

alerts = []

if latest['freshness_sla_status'] == 'BREACH':
    alerts.append({
        'severity': 'ERROR',
        'message': f"Data freshness SLA breach: {int(latest['encounters_freshness_minutes'])} minutes (>6 hours)"
    })
elif latest['freshness_sla_status'] == 'WARNING':
    alerts.append({
        'severity': 'WARNING',
        'message': f"Data freshness warning: {int(latest['encounters_freshness_minutes'])} minutes (>4 hours)"
    })

if latest['quality_sla_status'] == 'BREACH':
    alerts.append({
        'severity': 'ERROR',
        'message': f"Data quality SLA breach: {latest['data_quality_score_pct']:.1f}% (<95%)"
    })
elif latest['quality_sla_status'] == 'WARNING':
    alerts.append({
        'severity': 'WARNING',
        'message': f"Data quality warning: {latest['data_quality_score_pct']:.1f}% (<99%)"
    })

if latest['invalid_los_count'] > 10:
    alerts.append({
        'severity': 'WARNING',
        'message': f"High number of invalid LOS records: {int(latest['invalid_los_count'])}"
    })

if alerts:
    for alert in alerts:
        if alert['severity'] == 'ERROR':
            st.error(f"🚨 {alert['message']}")
        else:
            st.warning(f"⚠️ {alert['message']}")
else:
    st.success("✅ All SLA metrics are within acceptable thresholds")

# Footer
st.markdown("---")
st.markdown(
    f"**Last Check:** {latest['check_timestamp'].strftime('%Y-%m-%d %H:%M:%S')} | "
    f"**Next Refresh:** {(datetime.now() + pd.Timedelta(seconds=60)).strftime('%H:%M:%S')}"
)

# Auto-refresh logic
if auto_refresh:
    import time

    time.sleep(60)
    st.rerun()