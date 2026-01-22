"""
IsoMetrics Healthcare - Monitoring Dashboard
Real-time monitoring of data quality, SLA compliance, and system health
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import matplotlib.pyplot as plt
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
        metric_date,
        queries_executed,
        total_execution_time_seconds,
        cloud_services_cost_usd,
        warehouse_cost_usd,
        total_cost_usd,
        total_credits_used,
        cumulative_cost_usd,
        cost_7days_ago,
        cost_change_pct_wow,
        calculation_method,
        note,
        _dbt_loaded_at
    FROM DBT_DEV_MARTS.FCT_COST_ATTRIBUTION
    WHERE metric_date >= DATEADD('day', -30, CURRENT_DATE())
    ORDER BY metric_date DESC
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
        bed_count,
        city,
        state,
        region,
        emr_system,
        contract_tier,
        contract_start_date,
        is_active,
        teaching_hospital
    FROM DBT_DEV_STAGING.STG_HEALTHCARE__HOSPITALS
    WHERE is_active = TRUE
    ORDER BY hospital_name
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
    """Create cost trend visualization"""
    # Aggregate daily costs
    daily_cost = df.groupby('metric_date').agg({
        'total_cost_usd': 'sum',
        'warehouse_cost_usd': 'sum',
        'cloud_services_cost_usd': 'sum'
    }).reset_index()

    # Create main line chart with total_cost_usd (NOT estimated_cost_usd!)
    fig = px.line(
        daily_cost,
        x='metric_date',
        y='total_cost_usd',
        title='Daily Cost Trend',
        labels={
            'metric_date': 'Date',
            'total_cost_usd': 'Total Cost (USD)'
        }
    )

    # Add warehouse and cloud services as additional traces
    fig.add_scatter(
        x=daily_cost['metric_date'],
        y=daily_cost['warehouse_cost_usd'],
        mode='lines',
        name='Warehouse Cost',
        line=dict(dash='dash')
    )

    fig.add_scatter(
        x=daily_cost['metric_date'],
        y=daily_cost['cloud_services_cost_usd'],
        mode='lines',
        name='Cloud Services Cost',
        line=dict(dash='dot')
    )

    fig.update_layout(
        hovermode='x unified',
        legend=dict(
            orientation="h",
            yanchor="bottom",
            y=1.02,
            xanchor="right",
            x=1
        )
    )

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
                total_cost = cost_df['total_cost_usd'].sum()
                st.metric(
                    "Total Cost (Period)",
                    f"${total_cost:,.2f}"
                )

            with col2:
                avg_daily_cost = cost_df.groupby('metric_date')['total_cost_usd'].sum().mean()
                st.metric(
                    "Avg Daily Cost",
                    f"${avg_daily_cost:,.2f}"
                )

            with col3:
                total_queries = cost_df['queries_executed'].sum()
                st.metric(
                    "Total Queries",
                    f"{total_queries:,.0f}"
                )

            with col4:
                avg_cost_per_query = cost_df['total_cost_usd'].sum() / cost_df['queries_executed'].sum() if cost_df[
                                                                                                                'queries_executed'].sum() > 0 else 0
                st.metric(
                    "Avg Cost per Query",
                    f"${avg_cost_per_query:.4f}"
                )

            # Additional metrics row
            col5, col6, col7, col8 = st.columns(4)

            with col5:
                total_credits = cost_df['total_credits_used'].sum()
                st.metric(
                    "Total Credits Used",
                    f"{total_credits:,.2f}"
                )

            with col6:
                avg_execution_time = cost_df['total_execution_time_seconds'].mean()
                st.metric(
                    "Avg Execution Time",
                    f"{avg_execution_time:,.1f}s"
                )

            with col7:
                total_warehouse_cost = cost_df['warehouse_cost_usd'].sum()
                st.metric(
                    "Warehouse Cost",
                    f"${total_warehouse_cost:,.2f}"
                )

            with col8:
                total_cloud_cost = cost_df['cloud_services_cost_usd'].sum()
                st.metric(
                    "Cloud Services Cost",
                    f"${total_cloud_cost:,.2f}"
                )

            # Week-over-Week cost change
            if 'cost_change_pct_wow' in cost_df.columns:
                latest_wow = cost_df.sort_values('metric_date', ascending=False)['cost_change_pct_wow'].iloc[0]
                if pd.notna(latest_wow):
                    st.info(f"📊 Week-over-Week Cost Change: {latest_wow:+.1f}%")

            # Cost trend chart
            st.plotly_chart(
                create_cost_trend(cost_df),
                use_container_width=True
            )

            # Cost breakdown by type
            st.subheader("Cost Breakdown")
            col_left, col_right = st.columns(2)

            with col_left:
                # Pie chart for cost components
                cost_components = pd.DataFrame({
                    'Cost Type': ['Warehouse Cost', 'Cloud Services Cost'],
                    'Amount': [
                        cost_df['warehouse_cost_usd'].sum(),
                        cost_df['cloud_services_cost_usd'].sum()
                    ]
                })

                fig_pie = px.pie(
                    cost_components,
                    values='Amount',
                    names='Cost Type',
                    title='Cost Distribution by Type'
                )
                st.plotly_chart(fig_pie, use_container_width=True)

            with col_right:
                # Display cumulative cost trend
                cumulative_data = cost_df.sort_values('metric_date')[
                    ['metric_date', 'cumulative_cost_usd']].drop_duplicates('metric_date')
                if not cumulative_data.empty:
                    fig_cumulative = px.line(
                        cumulative_data,
                        x='metric_date',
                        y='cumulative_cost_usd',
                        title='Cumulative Cost Trend',
                        labels={'cumulative_cost_usd': 'Cumulative Cost (USD)', 'metric_date': 'Date'}
                    )
                    st.plotly_chart(fig_cumulative, use_container_width=True)

            # Top cost hospitals
            st.subheader("Cost by Hospital")
            cost_by_hospital = cost_df.groupby('hospital_id').agg({
                'total_cost_usd': 'sum',
                'queries_executed': 'sum',
                'warehouse_cost_usd': 'sum',
                'cloud_services_cost_usd': 'sum',
                'total_credits_used': 'sum',
                'total_execution_time_seconds': 'sum'
            }).reset_index()

            cost_by_hospital.columns = [
                'Hospital', 'Total Cost', 'Total Queries', 'Warehouse Cost',
                'Cloud Services Cost', 'Credits Used', 'Execution Time (s)'
            ]
            cost_by_hospital = cost_by_hospital.sort_values('Total Cost', ascending=False)

            # Add cost per query column
            cost_by_hospital['Cost per Query'] = cost_by_hospital['Total Cost'] / cost_by_hospital['Total Queries']

            st.dataframe(
                cost_by_hospital.style.format({
                    'Total Cost': '${:,.2f}',
                    'Total Queries': '{:,.0f}',
                    'Warehouse Cost': '${:,.2f}',
                    'Cloud Services Cost': '${:,.2f}',
                    'Credits Used': '{:,.2f}',
                    'Execution Time (s)': '{:,.1f}',
                    'Cost per Query': '${:.4f}'
                }),
                use_container_width=True,
                hide_index=True
            )

            # Optimization insights
            st.subheader("💡 Optimization Insights")

            # Identify hospitals with high cost per query
            high_cost_threshold = cost_by_hospital['Cost per Query'].quantile(0.75)
            high_cost_hospitals = cost_by_hospital[cost_by_hospital['Cost per Query'] > high_cost_threshold]

            if not high_cost_hospitals.empty:
                st.warning(f"⚠️ {len(high_cost_hospitals)} hospital(s) have above-average cost per query:")
                for _, row in high_cost_hospitals.iterrows():
                    st.write(f"- **{row['Hospital']}**: ${row['Cost per Query']:.4f} per query")

            # Show calculation method if available
            if 'calculation_method' in cost_df.columns:
                methods = cost_df['calculation_method'].unique()
                if len(methods) > 0:
                    st.info(f"📋 Calculation Method(s): {', '.join([str(m) for m in methods if pd.notna(m)])}")

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
        query_id,
        access_timestamp,
        user_name,
        role_name,
        session_id,
        database_name,
        schema_name,
        warehouse_name,
        hospital_id,
        phi_tables_accessed,
        phi_level,
        access_type,
        access_authorization_status,
        records_accessed,
        records_modified,
        bytes_scanned,
        is_bulk_access,
        is_unauthorized,
        execution_time_ms,
        total_elapsed_time_ms,
        access_duration_seconds,
        estimated_cost_usd,
        query_text_sample,
        compliance_note
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

        # Additional metrics row
        col5, col6, col7, col8 = st.columns(4)

        with col5:
            total_records = audit_df['records_accessed'].sum()
            st.metric("Total Records Accessed", f"{total_records:,}")

        with col6:
            total_modified = audit_df['records_modified'].sum()
            st.metric("Records Modified", f"{total_modified:,}")

        with col7:
            avg_cost = audit_df['estimated_cost_usd'].mean()
            st.metric("Avg Cost per Query", f"${avg_cost:.4f}")

        with col8:
            total_bytes = audit_df['bytes_scanned'].sum() / (1024 ** 3)  # Convert to GB
            st.metric("Total Data Scanned", f"{total_bytes:.2f} GB")

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

        # PHI Level Distribution
        col1, col2 = st.columns(2)

        with col1:
            st.subheader("PHI Level Distribution")
            phi_level_counts = audit_df['phi_level'].value_counts()
            fig = px.bar(
                x=phi_level_counts.index,
                y=phi_level_counts.values,
                title="Access by PHI Sensitivity Level",
                labels={'x': 'PHI Level', 'y': 'Count'},
                color=phi_level_counts.index,
                color_discrete_map={
                    'HIGH': 'red',
                    'MEDIUM': 'orange',
                    'LOW': 'yellow'
                }
            )
            st.plotly_chart(fig, use_container_width=True)

        with col2:
            st.subheader("Access Type Breakdown")
            access_type_counts = audit_df['access_type'].value_counts()
            fig = px.pie(
                values=access_type_counts.values,
                names=access_type_counts.index,
                title="Query Access Types"
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

        # Top users by access volume
        st.subheader("Top Users by PHI Access Volume")
        user_access = audit_df.groupby('user_name').agg({
            'audit_id': 'count',
            'records_accessed': 'sum',
            'is_unauthorized': 'sum',
            'estimated_cost_usd': 'sum'
        }).reset_index()
        user_access.columns = ['User', 'Access Events', 'Records Accessed', 'Unauthorized', 'Total Cost ($)']
        user_access = user_access.sort_values('Access Events', ascending=False).head(10)

        st.dataframe(user_access, use_container_width=True, hide_index=True)

        # Recent access log
        st.subheader("Recent PHI Access Log")

        # Define display columns (including the columns needed for highlighting)
        display_cols = [
            'access_timestamp', 'user_name', 'role_name',
            'access_authorization_status', 'phi_level', 'access_type',
            'phi_tables_accessed', 'hospital_id', 'records_accessed',
            'records_modified', 'is_unauthorized', 'is_bulk_access', 'compliance_note'
        ]

        # Create a subset for display
        display_df = audit_df[display_cols].head(50).copy()

        # Highlight unauthorized access - now the function has access to all needed columns
        def highlight_unauthorized(row):
            if row['is_unauthorized']:
                return ['background-color: #ffcccc'] * len(row)
            elif row['is_bulk_access']:
                return ['background-color: #fff3cd'] * len(row)
            elif row['phi_level'] == 'HIGH':
                return ['background-color: #ffe6e6'] * len(row)
            return [''] * len(row)

        # Apply styling
        styled_df = display_df.style.apply(highlight_unauthorized, axis=1)

        # Display without the flag columns if you prefer
        cols_to_show = [
            'access_timestamp', 'user_name', 'role_name',
            'access_authorization_status', 'phi_level', 'access_type',
            'phi_tables_accessed', 'hospital_id', 'records_accessed',
            'records_modified', 'compliance_note'
        ]

        st.dataframe(
            styled_df,
            use_container_width=True,
            hide_index=True,
            column_config={
                'is_unauthorized': None,  # Hide these columns
                'is_bulk_access': None
            }
        )

        # Detailed query analysis (expandable)
        with st.expander("🔍 View Detailed Query Information"):
            selected_audit = st.selectbox(
                "Select Audit Record",
                options=audit_df['audit_id'].head(20),
                format_func=lambda x: f"Audit ID: {x}"
            )

            if selected_audit:
                selected_row = audit_df[audit_df['audit_id'] == selected_audit].iloc[0]

                col1, col2 = st.columns(2)
                with col1:
                    st.write("**Query Details:**")
                    st.write(f"Query ID: {selected_row['query_id']}")
                    st.write(f"Session ID: {selected_row['session_id']}")
                    st.write(f"Database: {selected_row['database_name']}")
                    st.write(f"Schema: {selected_row['schema_name']}")
                    st.write(f"Warehouse: {selected_row['warehouse_name']}")

                with col2:
                    st.write("**Performance Metrics:**")
                    st.write(f"Execution Time: {selected_row['execution_time_ms']} ms")
                    st.write(f"Total Elapsed Time: {selected_row['total_elapsed_time_ms']} ms")
                    st.write(f"Bytes Scanned: {selected_row['bytes_scanned']:,} bytes")
                    st.write(f"Estimated Cost: ${selected_row['estimated_cost_usd']:.4f}")

                st.write("**Query Sample:**")
                st.code(selected_row['query_text_sample'], language='sql')

                if pd.notna(selected_row['compliance_note']) and selected_row['compliance_note']:
                    st.warning(f"⚠️ Compliance Note: {selected_row['compliance_note']}")

        # Alerts
        if unauthorized > 0:
            st.error(f"⚠️ **ALERT**: {unauthorized} unauthorized PHI access attempts detected!")
            alert_cols = [
                'access_timestamp', 'user_name', 'role_name',
                'access_authorization_status', 'phi_level', 'access_type',
                'phi_tables_accessed', 'hospital_id', 'records_accessed',
                'records_modified', 'compliance_note'
            ]
            st.dataframe(
                audit_df[audit_df['is_unauthorized']][alert_cols],
                use_container_width=True,
                hide_index=True
            )

        # High-risk access alerts
        high_risk = audit_df[
            (audit_df['phi_level'] == 'HIGH') &
            (audit_df['is_bulk_access'] == True)
            ]
        if not high_risk.empty:
            st.warning(f"⚠️ **NOTICE**: {len(high_risk)} bulk access events on HIGH sensitivity PHI detected!")

    else:
        st.warning("No audit trail data available")

def page_data_lineage():
    """Data Lineage & Dependencies page"""
    st.markdown('<div class="main-header">🔄 Data Lineage</div>',
                unsafe_allow_html=True)
    st.markdown("**Model Dependencies & Refresh Status**")

    st.info("📌 This page would display dbt model lineage from manifest.json in production")

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

    if tables_df.empty:
        st.warning("No table information available")
        return

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

    st.subheader("Model Refresh Status")
    tables_df['bytes'] = tables_df['bytes'].fillna(0)
    tables_df['row_count'] = tables_df['row_count'].fillna(0)
    tables_df['size_mb'] = tables_df['bytes'] / (1024 * 1024)
    tables_df['size_mb'] = tables_df['size_mb'].fillna(1).clip(lower=1)
    tables_df['hours_since_refresh'] = tables_df['hours_since_refresh'].fillna(0)

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

def page_hospital_comparison():
    """Hospital Performance Comparison page"""
    st.markdown('<div class="main-header">🏥 Hospital Comparison</div>',
                unsafe_allow_html=True)
    st.markdown("**Multi-Tenant Performance Benchmarking**")

    hospitals_df = load_hospitals()

    # Multi-select for comparison
    if not hospitals_df.empty:
        selected_hospitals = st.multiselect(
            "Select Hospitals to Compare (max 5)",
            hospitals_df['hospital_id'].tolist(),
            default=hospitals_df['hospital_id'].tolist()[:min(5, len(hospitals_df))],
            format_func=lambda x: hospitals_df[hospitals_df['hospital_id'] == x]['hospital_name'].values[0] if len(
                hospitals_df[hospitals_df['hospital_id'] == x]) > 0 else x
        )

        if selected_hospitals:
            # Load metrics for selected hospitals
            quality_query = f"""
            SELECT 
                hospital_id,
                metric_date,
                readmission_rate_30day_pct,
                mortality_rate_pct,
                avg_length_of_stay,
                total_encounters
            FROM DBT_DEV_MARTS.FCT_CLINICAL_QUALITY_METRICS
            WHERE hospital_id IN ({','.join([f"'{h}'" for h in selected_hospitals])})
              AND metric_date >= DATEADD('day', -7, CURRENT_DATE())
            """
            quality_df = run_query(quality_query)

            cost_query = f"""
            SELECT 
                hospital_id,
                SUM(estimated_cost_usd) as estimated_cost_usd,
                AVG(estimated_cost_usd) as cost_per_query
            FROM DBT_DEV_MARTS.FCT_HIPAA_AUDIT_TRAIL
            WHERE hospital_id IN ({','.join([f"'{h}'" for h in selected_hospitals])})
              AND access_timestamp >= DATEADD('day', -7, CURRENT_DATE())
            GROUP BY hospital_id
            """
            cost_df = run_query(cost_query)

            ops_query = f"""
            SELECT 
                hospital_id,
                metric_date,
                bed_occupancy_rate_pct,
                inpatient_admissions
            FROM DBT_DEV_MARTS.FCT_OPERATIONAL_METRICS
            WHERE hospital_id IN ({','.join([f"'{h}'" for h in selected_hospitals])})
              AND metric_date >= DATEADD('day', -7, CURRENT_DATE())
            """
            ops_df = run_query(ops_query)

            # Aggregate recent metrics
            if not quality_df.empty:
                recent_quality = quality_df.groupby('hospital_id').agg({
                    'readmission_rate_30day_pct': 'mean',
                    'mortality_rate_pct': 'mean',
                    'avg_length_of_stay': 'mean',
                    'total_encounters': 'sum'
                }).reset_index()
            else:
                recent_quality = pd.DataFrame(columns=['hospital_id', 'readmission_rate_30day_pct',
                                                       'mortality_rate_pct', 'avg_length_of_stay',
                                                       'total_encounters'])

            recent_cost = cost_df if not cost_df.empty else pd.DataFrame(
                columns=['hospital_id', 'estimated_cost_usd', 'cost_per_query'])

            if not ops_df.empty:
                recent_ops = ops_df.groupby('hospital_id').agg({
                    'bed_occupancy_rate_pct': 'mean',
                    'inpatient_admissions': 'sum'
                }).reset_index()
            else:
                recent_ops = pd.DataFrame(columns=['hospital_id', 'bed_occupancy_rate_pct', 'inpatient_admissions'])

            # Start with ALL hospital columns for selected hospitals
            comparison_df = hospitals_df[hospitals_df['hospital_id'].isin(selected_hospitals)].copy()

            # Merge metrics data
            if not recent_quality.empty:
                comparison_df = comparison_df.merge(recent_quality, on='hospital_id', how='left')
            else:
                comparison_df['readmission_rate_30day_pct'] = None
                comparison_df['mortality_rate_pct'] = None
                comparison_df['avg_length_of_stay'] = None
                comparison_df['total_encounters'] = None

            if not recent_cost.empty:
                comparison_df = comparison_df.merge(recent_cost, on='hospital_id', how='left')
            else:
                comparison_df['estimated_cost_usd'] = None
                comparison_df['cost_per_query'] = None

            if not recent_ops.empty:
                comparison_df = comparison_df.merge(recent_ops, on='hospital_id', how='left')
            else:
                comparison_df['bed_occupancy_rate_pct'] = None
                comparison_df['inpatient_admissions'] = None

            # Hospital profile summary
            st.subheader("Hospital Profiles")

            profile_cols = ['hospital_name', 'hospital_type', 'bed_count', 'city',
                            'state', 'region', 'emr_system', 'contract_tier', 'teaching_hospital']
            profile_display = comparison_df[profile_cols].copy()
            profile_display.columns = ['Hospital', 'Type', 'Beds', 'City',
                                       'State', 'Region', 'EMR', 'Contract', 'Teaching']
            profile_display['Teaching'] = profile_display['Teaching'].map({True: 'Yes', False: 'No', None: 'N/A'})

            st.dataframe(profile_display, use_container_width=True, hide_index=True)

            # Display comparison table
            st.subheader("Performance Scorecard (Last 7 Days)")

            display_cols = [
                'hospital_name', 'hospital_type', 'region', 'bed_count',
                'readmission_rate_30day_pct', 'mortality_rate_pct',
                'avg_length_of_stay', 'bed_occupancy_rate_pct',
                'estimated_cost_usd', 'total_encounters'
            ]

            comparison_display = comparison_df[display_cols].copy()
            comparison_display.columns = [
                'Hospital', 'Type', 'Region', 'Beds',
                'Readmit %', 'Mortality %',
                'Avg LOS', 'Bed Occ %',
                'Total Cost', 'Encounters'
            ]

            # Ensure numeric columns are numeric (important for gradients)
            numeric_cols = [
                'Beds', 'Readmit %', 'Mortality %',
                'Avg LOS', 'Bed Occ %',
                'Total Cost', 'Encounters'
            ]
            comparison_display[numeric_cols] = comparison_display[numeric_cols].apply(
                pd.to_numeric, errors="coerce"
            )

            # Fill NaN values for better display
            comparison_display = comparison_display.fillna(0)

            # Build styler
            styler = (
                comparison_display.style
                .format({
                    'Beds': '{:,.0f}',
                    'Readmit %': '{:.2f}',
                    'Mortality %': '{:.2f}',
                    'Avg LOS': '{:.1f}',
                    'Bed Occ %': '{:.1f}',
                    'Total Cost': '${:,.2f}',
                    'Encounters': '{:,.0f}'
                })
                .background_gradient(
                    subset=['Readmit %', 'Mortality %'],
                    cmap='RdYlGn_r'
                )
                .background_gradient(
                    subset=['Bed Occ %'],
                    cmap='RdYlGn'
                )
            )

            st.dataframe(
                styler,
                use_container_width=True,
                hide_index=True
            )

            # Key metrics overview
            st.subheader("Key Metrics Overview")

            metrics_col1, metrics_col2, metrics_col3, metrics_col4 = st.columns(4)

            with metrics_col1:
                avg_readmit = comparison_df['readmission_rate_30day_pct'].mean()
                st.metric("Avg Readmission Rate", f"{avg_readmit:.2f}%" if pd.notna(avg_readmit) else "N/A")

            with metrics_col2:
                avg_mortality = comparison_df['mortality_rate_pct'].mean()
                st.metric("Avg Mortality Rate", f"{avg_mortality:.2f}%" if pd.notna(avg_mortality) else "N/A")

            with metrics_col3:
                total_encounters = comparison_df['total_encounters'].sum()
                st.metric("Total Encounters", f"{total_encounters:,.0f}" if pd.notna(total_encounters) else "N/A")

            with metrics_col4:
                total_cost = comparison_df['estimated_cost_usd'].sum()
                st.metric("Total Cost", f"${total_cost:,.2f}" if pd.notna(total_cost) else "N/A")

            # Comparison charts
            col1, col2 = st.columns(2)

            with col1:
                if comparison_df['readmission_rate_30day_pct'].notna().any():
                    chart_df = comparison_df[comparison_df['readmission_rate_30day_pct'].notna()].copy()
                    fig = px.bar(
                        chart_df,
                        x='hospital_name',
                        y='readmission_rate_30day_pct',
                        title='30-Day Readmission Rate Comparison',
                        color='readmission_rate_30day_pct',
                        color_continuous_scale='RdYlGn_r',
                        labels={'hospital_name': 'Hospital', 'readmission_rate_30day_pct': 'Readmission Rate (%)'}
                    )
                    fig.add_hline(y=5, line_dash="dash", line_color="red",
                                  annotation_text="Target: 5%")
                    st.plotly_chart(fig, use_container_width=True)
                else:
                    st.info("No readmission data available")

            with col2:
                if comparison_df['bed_occupancy_rate_pct'].notna().any():
                    chart_df = comparison_df[comparison_df['bed_occupancy_rate_pct'].notna()].copy()
                    fig = px.bar(
                        chart_df,
                        x='hospital_name',
                        y='bed_occupancy_rate_pct',
                        title='Bed Occupancy Rate Comparison',
                        color='bed_occupancy_rate_pct',
                        color_continuous_scale='RdYlGn',
                        labels={'hospital_name': 'Hospital', 'bed_occupancy_rate_pct': 'Occupancy Rate (%)'}
                    )
                    fig.add_hline(y=75, line_dash="dash", line_color="orange",
                                  annotation_text="Target: 75-85%")
                    fig.add_hline(y=85, line_dash="dash", line_color="orange")
                    st.plotly_chart(fig, use_container_width=True)
                else:
                    st.info("No occupancy data available")

            # Additional comparison charts
            col3, col4 = st.columns(2)

            with col3:
                if comparison_df['avg_length_of_stay'].notna().any():
                    chart_df = comparison_df[comparison_df['avg_length_of_stay'].notna()].copy()
                    fig = px.bar(
                        chart_df,
                        x='hospital_name',
                        y='avg_length_of_stay',
                        title='Average Length of Stay Comparison',
                        color='avg_length_of_stay',
                        color_continuous_scale='RdYlGn_r',
                        labels={'hospital_name': 'Hospital', 'avg_length_of_stay': 'Avg LOS (days)'}
                    )
                    st.plotly_chart(fig, use_container_width=True)
                else:
                    st.info("No length of stay data available")

            with col4:
                if comparison_df['estimated_cost_usd'].notna().any():
                    chart_df = comparison_df[comparison_df['estimated_cost_usd'].notna()].copy()
                    fig = px.bar(
                        chart_df,
                        x='hospital_name',
                        y='estimated_cost_usd',
                        title='Total Cost Comparison (Last 7 Days)',
                        color='estimated_cost_usd',
                        color_continuous_scale='Blues',
                        labels={'hospital_name': 'Hospital', 'estimated_cost_usd': 'Total Cost ($)'}
                    )
                    st.plotly_chart(fig, use_container_width=True)
                else:
                    st.info("No cost data available")

            # Hospital characteristics analysis
            st.subheader("Hospital Characteristics")

            char_col1, char_col2 = st.columns(2)

            with char_col1:
                # By hospital type
                type_summary = comparison_df.groupby('hospital_type').agg({
                    'hospital_id': 'count',
                    'bed_count': 'sum',
                    'readmission_rate_30day_pct': 'mean'
                }).reset_index()
                type_summary.columns = ['Type', 'Count', 'Total Beds', 'Avg Readmit %']

                fig = px.bar(
                    type_summary,
                    x='Type',
                    y='Count',
                    title='Hospitals by Type',
                    text='Count',
                    color='Type'
                )
                fig.update_traces(textposition='outside')
                st.plotly_chart(fig, use_container_width=True)

            with char_col2:
                # By EMR system
                emr_summary = comparison_df.groupby('emr_system').size().reset_index(name='Count')

                fig = px.pie(
                    emr_summary,
                    values='Count',
                    names='emr_system',
                    title='Distribution by EMR System'
                )
                st.plotly_chart(fig, use_container_width=True)

            # Rankings
            st.subheader("Performance Rankings")

            ranking_cols = st.columns(3)

            with ranking_cols[0]:
                st.markdown("**Best Clinical Quality (Lowest Readmission)**")
                valid_quality = comparison_df[comparison_df['readmission_rate_30day_pct'].notna()].copy()
                if not valid_quality.empty:
                    quality_rank = valid_quality.nsmallest(5, 'readmission_rate_30day_pct')[
                        ['hospital_name', 'readmission_rate_30day_pct']
                    ].copy()
                    quality_rank.columns = ['Hospital', 'Readmit %']
                    quality_rank['Readmit %'] = quality_rank['Readmit %'].map('{:.2f}%'.format)
                    st.dataframe(quality_rank, hide_index=True, use_container_width=True)
                else:
                    st.info("No quality data available")

            with ranking_cols[1]:
                st.markdown("**Highest Volume**")
                valid_volume = comparison_df[comparison_df['total_encounters'].notna()].copy()
                if not valid_volume.empty:
                    volume_rank = valid_volume.nlargest(5, 'total_encounters')[
                        ['hospital_name', 'total_encounters']
                    ].copy()
                    volume_rank.columns = ['Hospital', 'Encounters']
                    volume_rank['Encounters'] = volume_rank['Encounters'].map('{:,.0f}'.format)
                    st.dataframe(volume_rank, hide_index=True, use_container_width=True)
                else:
                    st.info("No volume data available")

            with ranking_cols[2]:
                st.markdown("**Most Cost Efficient (Lowest Total Cost)**")
                valid_cost = comparison_df[comparison_df['estimated_cost_usd'].notna()].copy()
                if not valid_cost.empty:
                    cost_rank = valid_cost.nsmallest(5, 'estimated_cost_usd')[
                        ['hospital_name', 'estimated_cost_usd']
                    ].copy()
                    cost_rank.columns = ['Hospital', 'Total Cost']
                    cost_rank['Total Cost'] = cost_rank['Total Cost'].map('${:,.2f}'.format)
                    st.dataframe(cost_rank, hide_index=True, use_container_width=True)
                else:
                    st.info("No cost data available")
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