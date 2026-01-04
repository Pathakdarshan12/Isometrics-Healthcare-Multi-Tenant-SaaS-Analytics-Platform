"""
IsoMetrics Healthcare - Monitoring Dashboard
Real-time monitoring of data quality, SLA compliance, and system health
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import snowflake.connector
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv
load_dotenv()

# Page configuration
st.set_page_config(
    page_title="IsoMetrics Healthcare Monitor",
    page_icon="🏥",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS
st.markdown("""
<style>
    .main-header {
        font-size: 2.5rem;
        font-weight: bold;
        color: #1f77b4;
        margin-bottom: 0.5rem;
    }
    .metric-card {
        background-color: #f0f2f6;
        padding: 1rem;
        border-radius: 0.5rem;
        border-left: 4px solid #1f77b4;
    }
    .status-compliant {
        color: #28a745;
        font-weight: bold;
    }
    .status-warning {
        color: #ffc107;
        font-weight: bold;
    }
    .status-breach {
        color: #dc3545;
        font-weight: bold;
    }
</style>
""", unsafe_allow_html=True)

# ============================================
# SNOWFLAKE CONNECTION
# ============================================

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

# ============================================
# DATA LOADING FUNCTIONS
# ============================================

def load_sla_monitoring():
    """Load SLA monitoring data"""
    query = """
    SELECT 
        hospital_id,
        check_timestamp,
        encounters_freshness_minutes,
        freshness_sla_status,
        data_quality_score_pct,
        quality_sla_status,
        overall_sla_status,
        total_encounters,
        invalid_los_count,
        invalid_charges_count,
        invalid_dates_count
    FROM DBT_DEV_MARTS.FCT_SLA_MONITORING
    ORDER BY check_timestamp DESC
    LIMIT 1000
    """
    return run_query(query)


def load_cost_attribution():
    """Load cost attribution data"""
    query = """
    SELECT 
        hospital_id,
        query_date,
        query_count,
        total_gb_scanned,
        estimated_cost_usd,
        cumulative_cost_usd,
        cost_change_pct_wow,
        cost_per_query
    FROM DBT_DEV_MARTS.FCT_COST_ATTRIBUTION
    WHERE query_date >= DATEADD('day', -30, CURRENT_DATE())
    ORDER BY query_date DESC
    """
    return run_query(query)


def load_clinical_quality():
    """Load clinical quality metrics"""
    query = """
    SELECT 
        hospital_id,
        metric_date,
        total_encounters,
        inpatient_encounters,
        readmission_rate_30day_pct,
        mortality_rate_pct,
        avg_length_of_stay,
        high_risk_patients
    FROM DBT_DEV_MARTS.FCT_CLINICAL_QUALITY_METRICS
    WHERE metric_date >= DATEADD('day', -30, CURRENT_DATE())
    ORDER BY metric_date DESC
    """
    return run_query(query)


def load_operational_metrics():
    """Load operational metrics"""
    query = """
    SELECT 
        hospital_id,
        metric_date,
        inpatient_admissions,
        emergency_visits,
        bed_occupancy_rate_pct,
        total_patient_days,
        active_providers
    FROM DBT_DEV_MARTS.FCT_OPERATIONAL_METRICS
    WHERE metric_date >= DATEADD('day', -30, CURRENT_DATE())
    ORDER BY metric_date DESC
    """
    return run_query(query)


def load_hospitals():
    """Load hospital list"""
    query = """
    SELECT 
        hospital_id,
        hospital_name,
        hospital_type,
        region,
        contract_tier
    FROM DBT_DEV_STAGING.STG_HEALTHCARE__HOSPITALS
    """
    return run_query(query)


# ============================================
# VISUALIZATION FUNCTIONS
# ============================================

def create_sla_gauge(value, title, thresholds={'good': 99, 'warning': 95}):
    """Create SLA gauge chart"""
    fig = go.Figure(go.Indicator(
        mode="gauge+number+delta",
        value=value,
        domain={'x': [0, 1], 'y': [0, 1]},
        title={'text': title, 'font': {'size': 16}},
        delta={'reference': 100},
        gauge={
            'axis': {'range': [None, 100]},
            'bar': {'color': "darkblue"},
            'steps': [
                {'range': [0, thresholds['warning']], 'color': "lightcoral"},
                {'range': [thresholds['warning'], thresholds['good']], 'color': "lightyellow"},
                {'range': [thresholds['good'], 100], 'color': "lightgreen"}
            ],
            'threshold': {
                'line': {'color': "red", 'width': 4},
                'thickness': 0.75,
                'value': thresholds['good']
            }
        }
    ))
    fig.update_layout(height=250, margin=dict(l=20, r=20, t=50, b=20))
    return fig


def create_cost_trend(df):
    """Create cost trend chart"""
    fig = px.line(
        df,
        x='query_date',
        y='estimated_cost_usd',
        color='hospital_id',
        title='Daily Cost Trends by Hospital',
        labels={'estimated_cost_usd': 'Cost (USD)', 'query_date': 'Date'}
    )
    fig.update_layout(height=400)
    return fig


def create_quality_metrics(df):
    """Create quality metrics dashboard"""
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=(
            'Readmission Rate Trend',
            'Mortality Rate Trend',
            'Average Length of Stay',
            'High Risk Patient Count'
        )
    )

    for hospital_id in df['hospital_id'].unique()[:5]:  # Top 5 hospitals
        hospital_data = df[df['hospital_id'] == hospital_id]

        fig.add_trace(
            go.Scatter(x=hospital_data['metric_date'],
                       y=hospital_data['readmission_rate_30day_pct'],
                       name=hospital_id, legendgroup=hospital_id),
            row=1, col=1
        )

        fig.add_trace(
            go.Scatter(x=hospital_data['metric_date'],
                       y=hospital_data['mortality_rate_pct'],
                       name=hospital_id, legendgroup=hospital_id, showlegend=False),
            row=1, col=2
        )

        fig.add_trace(
            go.Scatter(x=hospital_data['metric_date'],
                       y=hospital_data['avg_length_of_stay'],
                       name=hospital_id, legendgroup=hospital_id, showlegend=False),
            row=2, col=1
        )

        fig.add_trace(
            go.Scatter(x=hospital_data['metric_date'],
                       y=hospital_data['high_risk_patients'],
                       name=hospital_id, legendgroup=hospital_id, showlegend=False),
            row=2, col=2
        )

    fig.update_xaxes(title_text="Date")
    fig.update_yaxes(title_text="Rate (%)", row=1, col=1)
    fig.update_yaxes(title_text="Rate (%)", row=1, col=2)
    fig.update_yaxes(title_text="Days", row=2, col=1)
    fig.update_yaxes(title_text="Count", row=2, col=2)

    fig.update_layout(height=600, showlegend=True)
    return fig


# ============================================
# MAIN DASHBOARD
# ============================================

def main():
    # Header
    st.markdown('<div class="main-header">🏥 IsoMetrics Healthcare Monitor</div>',
                unsafe_allow_html=True)
    st.markdown("**Real-time Data Quality & SLA Monitoring**")

    # Sidebar
    st.sidebar.title("⚙️ Dashboard Controls")

    # Refresh button
    if st.sidebar.button("🔄 Refresh Data", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

    # Load hospitals for filter
    hospitals_df = load_hospitals()
    hospitals_df.columns = hospitals_df.columns.str.lower()

    if not hospitals_df.empty:
        hospital_options = ['All Hospitals'] + sorted(
            hospitals_df['hospital_id']
            .astype(str)
            .unique()
            .tolist()
        )

        selected_hospital = st.sidebar.selectbox(
            "Select Hospital",
            hospital_options
        )
    else:
        selected_hospital = 'All Hospitals'

    # Date range filter
    date_range = st.sidebar.slider(
        "Days to Display",
        min_value=7,
        max_value=90,
        value=30
    )

    st.sidebar.markdown("---")
    st.sidebar.markdown("### 📊 Dashboard Sections")
    show_sla = st.sidebar.checkbox("SLA Monitoring", value=True)
    show_quality = st.sidebar.checkbox("Clinical Quality", value=True)
    show_cost = st.sidebar.checkbox("Cost Attribution", value=True)
    show_operations = st.sidebar.checkbox("Operations", value=True)

    # ============================================
    # SECTION 1: SLA MONITORING
    # ============================================

    if show_sla:
        st.markdown("---")
        st.header("🎯 SLA Compliance Dashboard")

        sla_df = load_sla_monitoring()

        if not sla_df.empty:
            if selected_hospital != 'All Hospitals':
                sla_df = sla_df[sla_df['hospital_id'] == selected_hospital]

            # Latest SLA status
            latest_sla = sla_df.groupby('hospital_id').first().reset_index()

            # Overall metrics
            col1, col2, col3, col4 = st.columns(4)

            with col1:
                compliant = len(latest_sla[latest_sla['overall_sla_status'] == 'COMPLIANT'])
                total = len(latest_sla)
                compliance_rate = (compliant / total * 100) if total > 0 else 0
                st.metric(
                    "Overall SLA Compliance",
                    f"{compliance_rate:.1f}%",
                    delta=f"{compliant}/{total} hospitals"
                )

            with col2:
                avg_quality = latest_sla['data_quality_score_pct'].mean()
                st.metric(
                    "Avg Data Quality Score",
                    f"{avg_quality:.1f}%"
                )

            with col3:
                avg_freshness = latest_sla['encounters_freshness_minutes'].mean()
                st.metric(
                    "Avg Data Freshness",
                    f"{avg_freshness:.0f} min",
                    delta="Target: <240 min"
                )

            with col4:
                total_encounters = latest_sla['total_encounters'].sum()
                st.metric(
                    "Total Encounters Monitored",
                    f"{total_encounters:,.0f}"
                )

            # SLA gauges
            st.subheader("Data Quality Scores")
            gauge_cols = st.columns(3)

            with gauge_cols[0]:
                st.plotly_chart(
                    create_sla_gauge(avg_quality, "Data Quality"),
                    use_container_width=True
                )

            with gauge_cols[1]:
                freshness_score = max(0, 100 - (avg_freshness / 240 * 100))
                st.plotly_chart(
                    create_sla_gauge(freshness_score, "Data Freshness"),
                    use_container_width=True
                )

            with gauge_cols[2]:
                compliance_score = compliance_rate
                st.plotly_chart(
                    create_sla_gauge(compliance_score, "SLA Compliance"),
                    use_container_width=True
                )

            # Hospital-level SLA table
            st.subheader("Hospital SLA Status")

            display_df = latest_sla[[
                'hospital_id', 'overall_sla_status', 'data_quality_score_pct',
                'encounters_freshness_minutes', 'total_encounters'
            ]].copy()

            display_df.columns = [
                'Hospital', 'SLA Status', 'Quality Score %',
                'Freshness (min)', 'Total Encounters'
            ]

            st.dataframe(
                display_df.style.applymap(
                    lambda x: 'color: green' if x == 'COMPLIANT'
                    else ('color: orange' if x == 'WARNING' else 'color: red'),
                    subset=['SLA Status']
                ),
                use_container_width=True,
                hide_index=True
            )
        else:
            st.warning("No SLA monitoring data available")

    # ============================================
    # SECTION 2: CLINICAL QUALITY METRICS
    # ============================================

    if show_quality:
        st.markdown("---")
        st.header("📈 Clinical Quality Metrics")

        quality_df = load_clinical_quality()

        if not quality_df.empty:
            if selected_hospital != 'All Hospitals':
                quality_df = quality_df[quality_df['hospital_id'] == selected_hospital]

            # Recent averages
            recent_quality = quality_df[
                quality_df['metric_date'] >= (datetime.now() - timedelta(days=7))
                ]

            col1, col2, col3, col4 = st.columns(4)

            with col1:
                avg_readmit = recent_quality['readmission_rate_30day_pct'].mean()
                st.metric(
                    "30-Day Readmission Rate",
                    f"{avg_readmit:.2f}%",
                    delta="Target: <5%"
                )

            with col2:
                avg_mortality = recent_quality['mortality_rate_pct'].mean()
                st.metric(
                    "Mortality Rate",
                    f"{avg_mortality:.2f}%"
                )

            with col3:
                avg_los = recent_quality['avg_length_of_stay'].mean()
                st.metric(
                    "Avg Length of Stay",
                    f"{avg_los:.1f} days"
                )

            with col4:
                total_high_risk = recent_quality['high_risk_patients'].sum()
                st.metric(
                    "High Risk Patients",
                    f"{total_high_risk:,.0f}"
                )

            # Quality trends
            st.plotly_chart(
                create_quality_metrics(quality_df),
                use_container_width=True
            )
        else:
            st.warning("No clinical quality data available")

    # ============================================
    # SECTION 3: COST ATTRIBUTION
    # ============================================

    if show_cost:
        st.markdown("---")
        st.header("💰 Cost Attribution & Optimization")

        cost_df = load_cost_attribution()

        if not cost_df.empty:
            if selected_hospital != 'All Hospitals':
                cost_df = cost_df[cost_df['hospital_id'] == selected_hospital]

            # Cost summary
            col1, col2, col3, col4 = st.columns(4)

            with col1:
                total_cost = cost_df['estimated_cost_usd'].sum()
                st.metric(
                    "Total Cost (Period)",
                    f"${total_cost:,.2f}"
                )

            with col2:
                avg_daily_cost = cost_df.groupby('query_date')['estimated_cost_usd'].sum().mean()
                st.metric(
                    "Avg Daily Cost",
                    f"${avg_daily_cost:,.2f}"
                )

            with col3:
                total_queries = cost_df['query_count'].sum()
                st.metric(
                    "Total Queries",
                    f"{total_queries:,.0f}"
                )

            with col4:
                avg_cost_per_query = cost_df['cost_per_query'].mean()
                st.metric(
                    "Avg Cost per Query",
                    f"${avg_cost_per_query:.4f}"
                )

            # Cost trend chart
            st.plotly_chart(
                create_cost_trend(cost_df),
                use_container_width=True
            )

            # Top cost hospitals
            st.subheader("Cost by Hospital")
            cost_by_hospital = cost_df.groupby('hospital_id').agg({
                'estimated_cost_usd': 'sum',
                'query_count': 'sum',
                'total_gb_scanned': 'sum'
            }).reset_index()

            cost_by_hospital.columns = [
                'Hospital', 'Total Cost', 'Total Queries', 'Total GB Scanned'
            ]
            cost_by_hospital = cost_by_hospital.sort_values('Total Cost', ascending=False)

            st.dataframe(
                cost_by_hospital.style.format({
                    'Total Cost': '${:,.2f}',
                    'Total Queries': '{:,.0f}',
                    'Total GB Scanned': '{:,.1f}'
                }),
                use_container_width=True,
                hide_index=True
            )
        else:
            st.warning("No cost attribution data available")

    # ============================================
    # SECTION 4: OPERATIONAL METRICS
    # ============================================

    if show_operations:
        st.markdown("---")
        st.header("🏥 Operational Metrics")

        ops_df = load_operational_metrics()

        if not ops_df.empty:
            if selected_hospital != 'All Hospitals':
                ops_df = ops_df[ops_df['hospital_id'] == selected_hospital]

            # Recent averages
            recent_ops = ops_df[
                ops_df['metric_date'] >= (datetime.now() - timedelta(days=7))
                ]

            col1, col2, col3, col4 = st.columns(4)

            with col1:
                avg_admissions = recent_ops['inpatient_admissions'].mean()
                st.metric(
                    "Avg Daily Admissions",
                    f"{avg_admissions:.0f}"
                )

            with col2:
                avg_ed = recent_ops['emergency_visits'].mean()
                st.metric(
                    "Avg Daily ED Visits",
                    f"{avg_ed:.0f}"
                )

            with col3:
                avg_occupancy = recent_ops['bed_occupancy_rate_pct'].mean()
                st.metric(
                    "Bed Occupancy Rate",
                    f"{avg_occupancy:.1f}%",
                    delta="Target: 75-85%"
                )

            with col4:
                avg_providers = recent_ops['active_providers'].mean()
                st.metric(
                    "Active Providers",
                    f"{avg_providers:.0f}"
                )

            # Volume trends
            fig = px.line(
                ops_df.groupby('metric_date').sum().reset_index(),
                x='metric_date',
                y=['inpatient_admissions', 'emergency_visits'],
                title='Daily Volume Trends',
                labels={'value': 'Count', 'metric_date': 'Date'}
            )
            fig.update_layout(height=400)
            st.plotly_chart(fig, use_container_width=True)
        else:
            st.warning("No operational metrics available")

    # Footer
    st.markdown("---")
    st.markdown(
        f"*Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | "
        f"Auto-refresh: 5 minutes*"
    )


def page_hipaa_audit():
    """HIPAA Audit Trail page"""
    st.markdown('<div class="main-header">🔒 HIPAA Audit Trail</div>',
                unsafe_allow_html=True)
    st.markdown("**PHI Access Monitoring & Compliance**")

    # Load audit data
    query = """
    SELECT 
        audit_id,
        access_timestamp,
        user_name,
        role_name,
        access_authorization_status,
        phi_type_accessed,
        hospital_id,
        records_accessed,
        is_bulk_access,
        is_unauthorized,
        access_duration_seconds
    FROM DBT_DEV_MARTS.FCT_HIPAA_AUDIT_TRAIL
    WHERE access_timestamp >= DATEADD('day', -7, CURRENT_DATE())
    ORDER BY access_timestamp DESC
    LIMIT 1000
    """
    audit_df = run_query(query)

    if not audit_df.empty:
        # Summary metrics
        col1, col2, col3, col4 = st.columns(4)

        with col1:
            total_access = len(audit_df)
            st.metric("Total PHI Access Events", f"{total_access:,}")

        with col2:
            unauthorized = audit_df['is_unauthorized'].sum()
            st.metric("Unauthorized Attempts", f"{unauthorized:,}",
                      delta="🚨" if unauthorized > 0 else "✅")

        with col3:
            bulk_access = audit_df['is_bulk_access'].sum()
            st.metric("Bulk Access Events", f"{bulk_access:,}")

        with col4:
            unique_users = audit_df['user_name'].nunique()
            st.metric("Unique Users", f"{unique_users:,}")

        # Access by authorization status
        st.subheader("Access Authorization Status")
        auth_counts = audit_df['access_authorization_status'].value_counts()

        fig = px.pie(
            values=auth_counts.values,
            names=auth_counts.index,
            title="PHI Access by Authorization Level",
            color_discrete_map={
                'AUTHORIZED_ADMIN': 'lightgreen',
                'AUTHORIZED_PHI_ANALYST': 'lightblue',
                'AUTHORIZED_AUDITOR': 'lightyellow',
                'UNAUTHORIZED_PHI_ACCESS': 'lightcoral'
            }
        )
        st.plotly_chart(fig, use_container_width=True)

        # Access timeline
        st.subheader("PHI Access Timeline")
        audit_df['date'] = pd.to_datetime(audit_df['access_timestamp']).dt.date
        daily_access = audit_df.groupby(['date', 'access_authorization_status']).size().reset_index(name='count')

        fig = px.line(
            daily_access,
            x='date',
            y='count',
            color='access_authorization_status',
            title='Daily PHI Access by Authorization Status'
        )
        st.plotly_chart(fig, use_container_width=True)

        # Recent access log
        st.subheader("Recent PHI Access Log")

        # Highlight unauthorized access
        def highlight_unauthorized(row):
            if row['is_unauthorized']:
                return ['background-color: #ffcccc'] * len(row)
            elif row['is_bulk_access']:
                return ['background-color: #fff3cd'] * len(row)
            return [''] * len(row)

        display_cols = [
            'access_timestamp', 'user_name', 'role_name',
            'access_authorization_status', 'phi_type_accessed',
            'hospital_id', 'records_accessed'
        ]

        st.dataframe(
            audit_df[display_cols].head(50).style.apply(highlight_unauthorized, axis=1),
            use_container_width=True,
            hide_index=True
        )

        # Alerts
        if unauthorized > 0:
            st.error(f"⚠️ **ALERT**: {unauthorized} unauthorized PHI access attempts detected!")
            st.dataframe(
                audit_df[audit_df['is_unauthorized']][display_cols],
                use_container_width=True
            )
    else:
        st.warning("No audit trail data available")


def page_data_lineage():
    """Data Lineage & Dependencies page"""
    st.markdown('<div class="main-header">🔄 Data Lineage</div>',
                unsafe_allow_html=True)
    st.markdown("**Model Dependencies & Refresh Status**")

    # dbt manifest data (would come from dbt artifacts in production)
    st.info("📌 This page would display dbt model lineage from manifest.json in production")

    # Model refresh status
    query = """
    SELECT 
        table_schema,
        table_name,
        row_count,
        bytes,
        last_altered,
        DATEDIFF('hour', last_altered, CURRENT_TIMESTAMP()) as hours_since_refresh
    FROM ISOMETRICS_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema IN ('DBT_DEV_STAGING', 'DBT_DEV_INTERMEDIATE', 'DBT_DEV_MARTS')
    ORDER BY last_altered DESC
    """
    tables_df = run_query(query)

    if not tables_df.empty:
        col1, col2, col3 = st.columns(3)

        with col1:
            st.metric("Total Models", len(tables_df))

        with col2:
            stale = len(tables_df[tables_df['hours_since_refresh'] > 24])
            st.metric("Stale Models (>24h)", stale,
                      delta="🚨" if stale > 0 else "✅")

        with col3:
            total_rows = tables_df['row_count'].sum()
            st.metric("Total Rows", f"{total_rows:,.0f}")

        # Model refresh timeline
        st.subheader("Model Refresh Status")

        tables_df['size_mb'] = tables_df['bytes'] / (1024 * 1024)
        tables_df['freshness_status'] = tables_df['hours_since_refresh'].apply(
            lambda x: 'Fresh' if x < 6 else ('Warning' if x < 24 else 'Stale')
        )

        fig = px.scatter(
            tables_df,
            x='hours_since_refresh',
            y='row_count',
            size='size_mb',
            color='freshness_status',
            hover_data=['table_schema', 'table_name'],
            title='Model Freshness vs Size',
            color_discrete_map={
                'Fresh': 'lightgreen',
                'Warning': 'orange',
                'Stale': 'red'
            }
        )
        st.plotly_chart(fig, use_container_width=True)

        # Table details
        st.subheader("Model Details")
        display_df = tables_df[[
            'table_schema', 'table_name', 'row_count',
            'size_mb', 'hours_since_refresh', 'freshness_status'
        ]].copy()

        display_df.columns = [
            'Schema', 'Model', 'Rows', 'Size (MB)',
            'Hours Since Refresh', 'Status'
        ]

        st.dataframe(
            display_df.style.format({
                'Rows': '{:,.0f}',
                'Size (MB)': '{:.2f}',
                'Hours Since Refresh': '{:.1f}'
            }).applymap(
                lambda x: 'color: red' if x == 'Stale'
                else ('color: orange' if x == 'Warning' else 'color: green'),
                subset=['Status']
            ),
            use_container_width=True,
            hide_index=True
        )
    else:
        st.warning("No table information available")


def page_hospital_comparison():
    """Hospital Performance Comparison page"""
    st.markdown('<div class="main-header">🏥 Hospital Comparison</div>',
                unsafe_allow_html=True)
    st.markdown("**Multi-Tenant Performance Benchmarking**")

    # Load hospitals
    hospitals_df = load_hospitals()

    # Multi-select for comparison
    if not hospitals_df.empty:
        selected_hospitals = st.multiselect(
            "Select Hospitals to Compare (max 5)",
            hospitals_df['hospital_id'].tolist(),
            default=hospitals_df['hospital_id'].tolist()[:5]
        )

        if selected_hospitals:
            # Load metrics for selected hospitals
            quality_df = load_clinical_quality()
            cost_df = load_cost_attribution()
            ops_df = load_operational_metrics()

            # Filter for selected hospitals
            quality_df = quality_df[quality_df['hospital_id'].isin(selected_hospitals)]
            cost_df = cost_df[cost_df['hospital_id'].isin(selected_hospitals)]
            ops_df = ops_df[ops_df['hospital_id'].isin(selected_hospitals)]

            # Aggregate recent metrics
            recent_quality = quality_df[
                quality_df['metric_date'] >= (datetime.now() - timedelta(days=7))
                ].groupby('hospital_id').agg({
                'readmission_rate_30day_pct': 'mean',
                'mortality_rate_pct': 'mean',
                'avg_length_of_stay': 'mean',
                'total_encounters': 'sum'
            }).reset_index()

            recent_cost = cost_df.groupby('hospital_id').agg({
                'estimated_cost_usd': 'sum',
                'cost_per_query': 'mean'
            }).reset_index()

            recent_ops = ops_df[
                ops_df['metric_date'] >= (datetime.now() - timedelta(days=7))
                ].groupby('hospital_id').agg({
                'bed_occupancy_rate_pct': 'mean',
                'inpatient_admissions': 'sum'
            }).reset_index()

            # Merge all metrics
            comparison_df = recent_quality.merge(
                recent_cost, on='hospital_id', how='left'
            ).merge(
                recent_ops, on='hospital_id', how='left'
            ).merge(
                hospitals_df[['hospital_id', 'hospital_name', 'hospital_type', 'region']],
                on='hospital_id',
                how='left'
            )

            # Display comparison table
            st.subheader("Performance Scorecard (Last 7 Days)")

            display_cols = [
                'hospital_name', 'hospital_type', 'region',
                'readmission_rate_30day_pct', 'mortality_rate_pct',
                'avg_length_of_stay', 'bed_occupancy_rate_pct',
                'estimated_cost_usd', 'total_encounters'
            ]

            comparison_display = comparison_df[display_cols].copy()
            comparison_display.columns = [
                'Hospital', 'Type', 'Region',
                'Readmit %', 'Mortality %',
                'Avg LOS', 'Bed Occ %',
                'Total Cost', 'Encounters'
            ]

            st.dataframe(
                comparison_display.style.format({
                    'Readmit %': '{:.2f}',
                    'Mortality %': '{:.2f}',
                    'Avg LOS': '{:.1f}',
                    'Bed Occ %': '{:.1f}',
                    'Total Cost': '${:,.2f}',
                    'Encounters': '{:,.0f}'
                }).background_gradient(subset=['Readmit %', 'Mortality %'], cmap='RdYlGn_r')
                .background_gradient(subset=['Bed Occ %'], cmap='RdYlGn'),
                use_container_width=True,
                hide_index=True
            )

            # Comparison charts
            col1, col2 = st.columns(2)

            with col1:
                fig = px.bar(
                    comparison_df,
                    x='hospital_name',
                    y='readmission_rate_30day_pct',
                    title='30-Day Readmission Rate Comparison',
                    color='readmission_rate_30day_pct',
                    color_continuous_scale='RdYlGn_r'
                )
                fig.add_hline(y=5, line_dash="dash", line_color="red",
                              annotation_text="Target: 5%")
                st.plotly_chart(fig, use_container_width=True)

            with col2:
                fig = px.bar(
                    comparison_df,
                    x='hospital_name',
                    y='bed_occupancy_rate_pct',
                    title='Bed Occupancy Rate Comparison',
                    color='bed_occupancy_rate_pct',
                    color_continuous_scale='RdYlGn'
                )
                fig.add_hline(y=75, line_dash="dash", line_color="orange",
                              annotation_text="Target: 75-85%")
                fig.add_hline(y=85, line_dash="dash", line_color="orange")
                st.plotly_chart(fig, use_container_width=True)

            # Rankings
            st.subheader("Performance Rankings")

            ranking_cols = st.columns(3)

            with ranking_cols[0]:
                st.markdown("**Best Clinical Quality**")
                quality_rank = comparison_df.nsmallest(5, 'readmission_rate_30day_pct')[
                    ['hospital_name', 'readmission_rate_30day_pct']
                ]
                st.dataframe(quality_rank, hide_index=True, use_container_width=True)

            with ranking_cols[1]:
                st.markdown("**Highest Volume**")
                volume_rank = comparison_df.nlargest(5, 'total_encounters')[
                    ['hospital_name', 'total_encounters']
                ]
                st.dataframe(volume_rank, hide_index=True, use_container_width=True)

            with ranking_cols[2]:
                st.markdown("**Most Cost Efficient**")
                cost_rank = comparison_df.nsmallest(5, 'estimated_cost_usd')[
                    ['hospital_name', 'estimated_cost_usd']
                ]
                st.dataframe(cost_rank, hide_index=True, use_container_width=True)
        else:
            st.info("Please select at least one hospital to compare")
    else:
        st.warning("No hospital data available")


def page_alerts():
    """Alerts & Notifications page"""
    st.markdown('<div class="main-header">🚨 Alerts & Notifications</div>',
                unsafe_allow_html=True)
    st.markdown("**Active Alerts & Threshold Breaches**")

    alerts = []

    # Check SLA breaches
    sla_df = load_sla_monitoring()
    if not sla_df.empty:
        latest_sla = sla_df.groupby('hospital_id').first().reset_index()

        for _, row in latest_sla.iterrows():
            if row['overall_sla_status'] == 'BREACH':
                quality = row['data_quality_score_pct']
                freshness = row['encounters_freshness_minutes']

                message = (
                    "SLA breach detected - "
                    f"Quality: {quality:.1f}%"
                    if quality is not None
                    else "Quality: N/A"
                )

                message += (
                    f", Freshness: {freshness:.0f} min"
                    if freshness is not None
                    else ", Freshness: N/A"
                )

                alerts.append({
                    'severity': '🔴 Critical',
                    'category': 'SLA',
                    'hospital_id': row['hospital_id'],
                    'message': message,
                    'timestamp': row['check_timestamp']
                })
            elif row['overall_sla_status'] == 'WARNING':
                alerts.append({
                    'severity': '🟡 Warning',
                    'category': 'SLA',
                    'hospital_id': row['hospital_id'],
                    'message': f"SLA warning - Quality: {row['data_quality_score_pct']:.1f}%",
                    'timestamp': row['check_timestamp']
                })

    # Check quality metrics
    quality_df = load_clinical_quality()
    if not quality_df.empty:
        recent_quality = quality_df[
            quality_df['metric_date'] >= (datetime.now() - timedelta(days=1))
            ]

        for _, row in recent_quality.iterrows():
            if row['readmission_rate_30day_pct'] > 10:
                alerts.append({
                    'severity': '🔴 Critical',
                    'category': 'Clinical Quality',
                    'hospital_id': row['hospital_id'],
                    'message': f"High readmission rate: {row['readmission_rate_30day_pct']:.2f}% (Target: <5%)",
                    'timestamp': row['metric_date']
                })

            if row['mortality_rate_pct'] > 5:
                alerts.append({
                    'severity': '🟡 Warning',
                    'category': 'Clinical Quality',
                    'hospital_id': row['hospital_id'],
                    'message': f"Elevated mortality rate: {row['mortality_rate_pct']:.2f}%",
                    'timestamp': row['metric_date']
                })

    # Check operational metrics
    ops_df = load_operational_metrics()
    if not ops_df.empty:
        recent_ops = ops_df[
            ops_df['metric_date'] >= (datetime.now() - timedelta(days=1))
            ]

        for _, row in recent_ops.iterrows():
            if row['bed_occupancy_rate_pct'] > 95:
                alerts.append({
                    'severity': '🔴 Critical',
                    'category': 'Operations',
                    'hospital_id': row['hospital_id'],
                    'message': f"Critical bed capacity: {row['bed_occupancy_rate_pct']:.1f}% occupancy",
                    'timestamp': row['metric_date']
                })
            elif row['bed_occupancy_rate_pct'] > 85:
                alerts.append({
                    'severity': '🟡 Warning',
                    'category': 'Operations',
                    'hospital_id': row['hospital_id'],
                    'message': f"High bed occupancy: {row['bed_occupancy_rate_pct']:.1f}%",
                    'timestamp': row['metric_date']
                })

    # Display alerts
    if alerts:
        alerts_df = pd.DataFrame(alerts)

        # Summary
        col1, col2, col3 = st.columns(3)

        with col1:
            critical = len(alerts_df[alerts_df['severity'] == '🔴 Critical'])
            st.metric("Critical Alerts", critical)

        with col2:
            warning = len(alerts_df[alerts_df['severity'] == '🟡 Warning'])
            st.metric("Warnings", warning)

        with col3:
            st.metric("Total Alerts", len(alerts_df))

        # Alerts by category
        st.subheader("Alerts by Category")
        fig = px.pie(
            alerts_df,
            names='category',
            title='Alert Distribution',
            color='severity'
        )
        st.plotly_chart(fig, use_container_width=True)

        # Alert list
        st.subheader("Active Alerts")

        # Sort by severity
        severity_order = {'🔴 Critical': 0, '🟡 Warning': 1, '🟢 Info': 2}
        alerts_df['sort_order'] = alerts_df['severity'].map(severity_order)
        alerts_df = alerts_df.sort_values('sort_order')

        st.dataframe(
            alerts_df[['severity', 'category', 'hospital_id', 'message', 'timestamp']],
            use_container_width=True,
            hide_index=True
        )
    else:
        st.success("✅ No active alerts - all systems operating normally")


if __name__ == "__main__":
    # Multi-page navigation
    st.sidebar.title("📊 Navigation")
    page = st.sidebar.radio(
        "Select Page",
        [
            "🏠 Main Dashboard",
            "🔒 HIPAA Audit Trail",
            "🔄 Data Lineage",
            "🏥 Hospital Comparison",
            "🚨 Alerts"
        ]
    )

    if page == "🏠 Main Dashboard":
        main()
    elif page == "🔒 HIPAA Audit Trail":
        page_hipaa_audit()
    elif page == "🔄 Data Lineage":
        page_data_lineage()
    elif page == "🏥 Hospital Comparison":
        page_hospital_comparison()
    elif page == "🚨 Alerts":
        page_alerts()