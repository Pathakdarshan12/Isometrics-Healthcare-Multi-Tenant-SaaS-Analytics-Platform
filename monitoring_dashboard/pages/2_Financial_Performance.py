import os

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta
import snowflake.connector
from typing import Dict

# Page configuration
st.set_page_config(
    page_title="Financial Performance",
    page_icon="💰",
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
def load_financial_metrics(hospital_id: str = None, days: int = 30) -> pd.DataFrame:
    """Load financial performance metrics"""

    query = f"""
    SELECT
        hospital_id,
        metric_date,
        total_charges,
        total_payments,
        total_collections,
        total_denials,
        net_collection_rate_pct,
        denial_rate_pct,
        avg_days_in_ar,
        median_days_in_ar,
        ar_over_30_days,
        ar_over_60_days,
        ar_over_90_days,
        paid_count,
        pending_count,
        denial_count
    FROM ISOMETRICS_DEV.DBT_DEV_MARTS.fct_financial_performance
    """
    # WHERE metric_date >= DATEADD('day', -{days}, CURRENT_DATE())

    if hospital_id and hospital_id != "All Hospitals":
        query += f" AND hospital_id = '{hospital_id}'"

    query += " ORDER BY metric_date DESC"

    df = run_query(query)
    df['metric_date'] = pd.to_datetime(df['metric_date'])
    return df


@st.cache_data(ttl=300)
def load_hospital_list():
    """Load list of hospitals"""
    query = "SELECT DISTINCT hospital_id FROM ISOMETRICS_DEV.DBT_DEV_STAGING.stg_healthcare__hospitals ORDER BY hospital_id"
    df = run_query(query)
    return ["All Hospitals"] + df['hospital_id'].tolist()


def calculate_financial_summary(df: pd.DataFrame) -> Dict:
    """Calculate financial summary metrics"""
    total_charges = df['total_charges'].sum()
    total_collections = df['total_collections'].sum()
    total_denials = df['total_denials'].sum()

    return {
        'total_charges': total_charges,
        'total_collections': total_collections,
        'total_denials': total_denials,
        'avg_collection_rate': (total_collections / total_charges * 100) if total_charges > 0 else 0,
        'avg_denial_rate': df['denial_rate_pct'].mean(),
        'avg_days_in_ar': df['avg_days_in_ar'].mean()
    }


# Main Dashboard
st.title("💰 Financial Performance Dashboard")
st.markdown("Revenue cycle management and financial KPIs")

# Sidebar filters
st.sidebar.header("Filters")
hospitals = load_hospital_list()
selected_hospital = st.sidebar.selectbox("Select Hospital", hospitals)
date_range = st.sidebar.slider("Days to Display", 7, 90, 30)

# Load data
with st.spinner("Loading financial metrics..."):
    df_financial = load_financial_metrics(selected_hospital, date_range)

if df_financial.empty:
    st.error("No data available for selected filters")
    st.stop()

# Calculate summary
summary = calculate_financial_summary(df_financial)

# KPI Cards
st.subheader("💵 Key Financial Metrics")
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric(
        "Total Charges",
        f"${summary['total_charges']:,.0f}",
        help="Total charges billed in selected period"
    )

with col2:
    st.metric(
        "Collections",
        f"${summary['total_collections']:,.0f}",
        help="Total payments collected"
    )

with col3:
    st.metric(
        "Collection Rate",
        f"{summary['avg_collection_rate']:.1f}%",
        delta=f"{summary['avg_collection_rate'] - 95:.1f}%",
        delta_color="normal",
        help="Target: >95%"
    )

with col4:
    st.metric(
        "Days in A/R",
        f"{summary['avg_days_in_ar']:.0f} days",
        delta=f"{50 - summary['avg_days_in_ar']:.0f}",
        delta_color="normal",
        help="Target: <50 days"
    )

# Collection Rate Trend
st.subheader("📈 Net Collection Rate Trend")

fig_collection = go.Figure()

fig_collection.add_trace(go.Scatter(
    x=df_financial['metric_date'],
    y=df_financial['net_collection_rate_pct'],
    mode='lines+markers',
    name='Collection Rate',
    line=dict(color='#2ECC71', width=3),
    fill='tozeroy',
    fillcolor='rgba(46, 204, 113, 0.1)'
))

# Add benchmark line
fig_collection.add_hline(
    y=95,
    line_dash="dash",
    line_color="gray",
    annotation_text="Target (95%)",
    annotation_position="right"
)

fig_collection.update_layout(
    xaxis_title="Date",
    yaxis_title="Collection Rate (%)",
    yaxis_range=[0, 100],
    hovermode='x unified',
    height=400
)

st.plotly_chart(fig_collection, use_container_width=True)

# Two-column layout
col_left, col_right = st.columns(2)

with col_left:
    st.subheader("🚫 Denial Analysis")

    fig_denial = go.Figure()

    fig_denial.add_trace(go.Scatter(
        x=df_financial['metric_date'],
        y=df_financial['denial_rate_pct'],
        mode='lines+markers',
        name='Denial Rate',
        line=dict(color='#E74C3C', width=2)
    ))

    fig_denial.add_hline(
        y=5,
        line_dash="dash",
        line_color="orange",
        annotation_text="Warning Level (5%)"
    )

    fig_denial.update_layout(
        xaxis_title="Date",
        yaxis_title="Denial Rate (%)",
        hovermode='x unified',
        height=350
    )

    st.plotly_chart(fig_denial, use_container_width=True)

with col_right:
    st.subheader("⏰ Days in A/R Trend")

    fig_ar = go.Figure()

    fig_ar.add_trace(go.Scatter(
        x=df_financial['metric_date'],
        y=df_financial['avg_days_in_ar'],
        mode='lines',
        name='Average',
        line=dict(color='#3498DB', width=2)
    ))

    fig_ar.add_trace(go.Scatter(
        x=df_financial['metric_date'],
        y=df_financial['median_days_in_ar'],
        mode='lines',
        name='Median',
        line=dict(color='#9B59B6', width=2, dash='dash')
    ))

    fig_ar.update_layout(
        xaxis_title="Date",
        yaxis_title="Days",
        hovermode='x unified',
        height=350
    )

    st.plotly_chart(fig_ar, use_container_width=True)

# A/R Aging Analysis
st.subheader("📊 Accounts Receivable Aging")

latest_data = df_financial[df_financial['metric_date'] == df_financial['metric_date'].max()].iloc[0]

ar_aging = pd.DataFrame({
    'Aging Bucket': ['0-30 Days', '31-60 Days', '61-90 Days', '90+ Days'],
    'Amount': [
        latest_data['total_charges'] - latest_data['ar_over_30_days'],
        latest_data['ar_over_30_days'] - latest_data['ar_over_60_days'],
        latest_data['ar_over_60_days'] - latest_data['ar_over_90_days'],
        latest_data['ar_over_90_days']
    ]
})

fig_aging = px.bar(
    ar_aging,
    x='Aging Bucket',
    y='Amount',
    color='Aging Bucket',
    color_discrete_sequence=['#2ECC71', '#F39C12', '#E67E22', '#E74C3C'],
    text='Amount'
)

fig_aging.update_traces(texttemplate='$%{text:,.0f}', textposition='outside')
fig_aging.update_layout(
    yaxis_title="Amount ($)",
    showlegend=False,
    height=400
)

st.plotly_chart(fig_aging, use_container_width=True)

# Revenue Waterfall
st.subheader("💧 Revenue Waterfall")

waterfall_data = [
    latest_data['total_charges'],
    -latest_data['total_denials'],
    -(latest_data['total_charges'] - latest_data['total_collections'] - latest_data['total_denials']),
    latest_data['total_collections']
]

fig_waterfall = go.Figure(go.Waterfall(
    name="Revenue",
    orientation="v",
    measure=["absolute", "relative", "relative", "total"],
    x=["Charges", "Denials", "Adjustments", "Collections"],
    y=waterfall_data,
    text=[f"${x:,.0f}" for x in waterfall_data],
    textposition="outside",
    connector={"line": {"color": "rgb(63, 63, 63)"}},
))

fig_waterfall.update_layout(
    yaxis_title="Amount ($)",
    height=400
)

st.plotly_chart(fig_waterfall, use_container_width=True)

# Detailed Metrics Table
with st.expander("📋 View Detailed Financial Metrics"):
    display_df = df_financial.sort_values('metric_date', ascending=False).copy()

    # Format currency columns
    currency_cols = ['total_charges', 'total_payments', 'total_collections', 'total_denials']
    for col in currency_cols:
        display_df[col] = display_df[col].apply(lambda x: f"${x:,.2f}")

    st.dataframe(display_df, use_container_width=True, hide_index=True)

# Footer
st.markdown("---")
st.markdown(
    "**Data Source:** IsoMetrics Healthcare Analytics Platform | "
    f"**Last Updated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
)