"""
IsoMetrics Healthcare - Monitoring Dashboard
Real-time monitoring of clinical quality, SLA compliance, and HIPAA auditing
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime, timedelta
import snowflake.connector
import os

# Page config
st.set_page_config(
    page_title="IsoMetrics Healthcare - Monitoring",
    page_icon="🏥",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS
st.markdown("""
    <style>
    .metric-card {
        background-color: #f0f2f6;
        padding: 20px;
        border-radius: 10px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    .sla-compliant { color: #28a745; font-weight: bold; }
    .sla-warning { color: #ffc107; font-weight: bold; }
    .sla-breach { color: #dc3545; font-weight: bold; }
    </style>
""", unsafe_allow_html=True)


# Snowflake connection
@st.cache_resource
def get_snowflake_connection():
    """Create Snowflake connection from environment variables or secrets"""
    try:
        # Try Streamlit secrets first (for deployment)
        conn = snowflake.connector.connect(
            user=st.secrets["snowflake"]["user"],
            password=st.secrets["snowflake"]["password"],
            account=st.secrets["snowflake"]["account"],
            warehouse=st.secrets["snowflake"]["warehouse"],
            database=st.secrets["snowflake"]["database"],
            schema=st.secrets["snowflake"]["schema"]
        )
    except:
        # Fallback to environment variables (for local dev)
        conn = snowflake.connector.connect(
            user=os.getenv('SNOWFLAKE_USER'),
            password=os.getenv('SNOWFLAKE_PASSWORD'),
            account=os.getenv('SNOWFLAKE_ACCOUNT'),
            warehouse=os.getenv('SNOWFLAKE_WAREHOUSE', 'DBT_DEV_WH'),
            database=os.getenv('SNOWFLAKE_DATABASE', 'ISOMETRICS_DEV'),
            schema=os.getenv('SNOWFLAKE_SCHEMA', 'MARTS')
        )
    return conn


@st.cache_data(ttl=300)  # Cache for 5 minutes
def run_query(query):
    """Execute query and return DataFrame"""
    conn = get_snowflake_connection()
    return pd.read_sql(query, conn)


# Header
st.title("🏥 IsoMetrics Healthcare - Monitoring Dashboard")
st.markdown("**Real-time monitoring of clinical quality, SLA compliance, and HIPAA auditing**")
st.markdown("---")

# Sidebar filters
st.sidebar.header("🔍 Filters")
date_range = st.sidebar.date_input(
    "Date Range",
    value=(datetime.now() - timedelta(days=7), datetime.now()),
    max_value=datetime.now()
)

# Get hospital list
hospitals_query = "SELECT DISTINCT hospital_id, hospital_name FROM stg_healthcare__hospitals ORDER BY hospital_name"
try:
    hospitals_df = run_query(hospitals_query)
    hospital_options = ['All Hospitals'] + hospitals_df['HOSPITAL_NAME'].tolist()
    selected_hospital = st.sidebar.selectbox("Hospital", hospital_options)

    # Get hospital_id for filtering
    if selected_hospital != 'All Hospitals':
        hospital_id = hospitals_df[hospitals_df['HOSPITAL_NAME'] == selected_hospital]['HOSPITAL_ID'].iloc[0]
    else:
        hospital_id = None
except Exception as e:
    st.sidebar.error(f"Error loading hospitals: {str(e)}")
    st.stop()

refresh_button = st.sidebar.button("🔄 Refresh Data")

# Main content tabs
tab1, tab2, tab3, tab4, tab5 = st.tabs([
    "📊 Overview",
    "🏥 Clinical Quality",
    "💰 Financial Performance",
    "⏰ SLA Monitoring",
    "🔒 HIPAA Audit"
])

# ============================================================================
# TAB 1: OVERVIEW
# ============================================================================

with tab1:
    st.header("📊 Executive Dashboard")

    # Top-level KPIs
    col1, col2, col3, col4 = st.columns(4)

    try:
        # Query for top-level metrics
        overview_query = f"""
        WITH latest_metrics AS (
            SELECT 
                COUNT(DISTINCT hospital_id) as total_hospitals,
                SUM(total_encounters) as total_encounters,
                AVG(readmission_rate_30day_pct) as avg_readmission_rate,
                AVG(mortality_rate_pct) as avg_mortality_rate
            FROM fct_clinical_quality_metrics
            WHERE metric_date >= '{date_range[0]}'
              AND metric_date <= '{date_range[1]}'
              {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
        ),
        sla_status AS (
            SELECT 
                COUNT(CASE WHEN overall_sla_status = 'COMPLIANT' THEN 1 END) * 100.0 / COUNT(*) as sla_compliance_pct
            FROM fct_sla_monitoring
            {f"WHERE hospital_id = '{hospital_id}'" if hospital_id else ""}
        )
        SELECT * FROM latest_metrics CROSS JOIN sla_status
        """

        overview_df = run_query(overview_query)

        with col1:
            st.metric(
                "Hospitals Monitored",
                f"{int(overview_df['TOTAL_HOSPITALS'].iloc[0]):,}",
                delta=None
            )

        with col2:
            st.metric(
                "Total Encounters",
                f"{int(overview_df['TOTAL_ENCOUNTERS'].iloc[0]):,}",
                delta=None
            )

        with col3:
            readmission_rate = overview_df['AVG_READMISSION_RATE'].iloc[0]
            st.metric(
                "Avg Readmission Rate",
                f"{readmission_rate:.1f}%",
                delta=f"{readmission_rate - 10:.1f}% vs target (10%)",
                delta_color="inverse"
            )

        with col4:
            sla_compliance = overview_df['SLA_COMPLIANCE_PCT'].iloc[0]
            st.metric(
                "SLA Compliance",
                f"{sla_compliance:.1f}%",
                delta=f"{sla_compliance - 95:.1f}% vs target (95%)",
                delta_color="normal"
            )

    except Exception as e:
        st.error(f"Error loading overview metrics: {str(e)}")

    st.markdown("---")

    # Trends over time
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("📈 Daily Encounter Volume")
        try:
            volume_query = f"""
            SELECT 
                metric_date,
                SUM(total_encounters) as encounters
            FROM fct_clinical_quality_metrics
            WHERE metric_date >= '{date_range[0]}'
              AND metric_date <= '{date_range[1]}'
              {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
            GROUP BY metric_date
            ORDER BY metric_date
            """
            volume_df = run_query(volume_query)

            fig = px.line(
                volume_df,
                x='METRIC_DATE',
                y='ENCOUNTERS',
                title='Daily Encounter Volume',
                labels={'METRIC_DATE': 'Date', 'ENCOUNTERS': 'Encounters'}
            )
            st.plotly_chart(fig, use_container_width=True)
        except Exception as e:
            st.error(f"Error: {str(e)}")

    with col2:
        st.subheader("🎯 Quality Metrics Trend")
        try:
            quality_query = f"""
            SELECT 
                metric_date,
                AVG(readmission_rate_30day_pct) as readmission_rate,
                AVG(mortality_rate_pct) as mortality_rate
            FROM fct_clinical_quality_metrics
            WHERE metric_date >= '{date_range[0]}'
              AND metric_date <= '{date_range[1]}'
              {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
            GROUP BY metric_date
            ORDER BY metric_date
            """
            quality_df = run_query(quality_query)

            fig = go.Figure()
            fig.add_trace(go.Scatter(
                x=quality_df['METRIC_DATE'],
                y=quality_df['READMISSION_RATE'],
                name='30-Day Readmission Rate',
                line=dict(color='#ff7f0e')
            ))
            fig.add_trace(go.Scatter(
                x=quality_df['METRIC_DATE'],
                y=quality_df['MORTALITY_RATE'],
                name='Mortality Rate',
                line=dict(color='#d62728')
            ))
            fig.update_layout(
                title='Quality Metrics Over Time',
                xaxis_title='Date',
                yaxis_title='Rate (%)',
                hovermode='x unified'
            )
            st.plotly_chart(fig, use_container_width=True)
        except Exception as e:
            st.error(f"Error: {str(e)}")

# ============================================================================
# TAB 2: CLINICAL QUALITY
# ============================================================================

with tab2:
    st.header("🏥 Clinical Quality Metrics")

    # Hospital comparison
    st.subheader("🏆 Hospital Performance Comparison")
    try:
        comparison_query = f"""
        SELECT 
            h.hospital_name,
            h.hospital_type,
            AVG(c.readmission_rate_30day_pct) as readmission_rate,
            AVG(c.mortality_rate_pct) as mortality_rate,
            AVG(c.avg_length_of_stay) as avg_los,
            SUM(c.total_encounters) as total_encounters
        FROM fct_clinical_quality_metrics c
        JOIN stg_healthcare__hospitals h ON c.hospital_id = h.hospital_id
        WHERE c.metric_date >= '{date_range[0]}'
          AND c.metric_date <= '{date_range[1]}'
          {f"AND c.hospital_id = '{hospital_id}'" if hospital_id else ""}
        GROUP BY h.hospital_name, h.hospital_type
        ORDER BY readmission_rate ASC
        LIMIT 20
        """
        comparison_df = run_query(comparison_query)

        # Create bar chart
        fig = px.bar(
            comparison_df,
            x='HOSPITAL_NAME',
            y='READMISSION_RATE',
            color='HOSPITAL_TYPE',
            title='30-Day Readmission Rate by Hospital',
            labels={'READMISSION_RATE': 'Readmission Rate (%)', 'HOSPITAL_NAME': 'Hospital'}
        )
        fig.add_hline(y=10, line_dash="dash", line_color="red",
                      annotation_text="National Target (10%)")
        st.plotly_chart(fig, use_container_width=True)

        # Data table
        st.dataframe(
            comparison_df.style.background_gradient(subset=['READMISSION_RATE'], cmap='RdYlGn_r'),
            use_container_width=True
        )
    except Exception as e:
        st.error(f"Error loading comparison: {str(e)}")

    st.markdown("---")

    # Length of Stay Analysis
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("⏱️ Length of Stay by Encounter Type")
        try:
            los_query = f"""
            SELECT 
                encounter_type,
                AVG(length_of_stay) as avg_los,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY length_of_stay) as median_los,
                COUNT(*) as encounter_count
            FROM fct_encounters
            WHERE admission_date_day >= '{date_range[0]}'
              AND admission_date_day <= '{date_range[1]}'
              {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
            GROUP BY encounter_type
            """
            los_df = run_query(los_query)

            fig = px.bar(
                los_df,
                x='ENCOUNTER_TYPE',
                y='AVG_LOS',
                title='Average Length of Stay',
                labels={'AVG_LOS': 'Days', 'ENCOUNTER_TYPE': 'Type'}
            )
            st.plotly_chart(fig, use_container_width=True)
        except Exception as e:
            st.error(f"Error: {str(e)}")

    with col2:
        st.subheader("🎯 Patient Risk Distribution")
        try:
            risk_query = f"""
            SELECT 
                DATE_TRUNC('week', admission_date_day) as week,
                COUNT(CASE WHEN severity_level = 'Critical' THEN 1 END) as critical,
                COUNT(CASE WHEN severity_level = 'High' THEN 1 END) as high,
                COUNT(CASE WHEN severity_level = 'Moderate' THEN 1 END) as moderate
            FROM fct_encounters
            WHERE admission_date_day >= '{date_range[0]}'
              AND admission_date_day <= '{date_range[1]}'
              {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
            GROUP BY week
            ORDER BY week
            """
            risk_df = run_query(risk_query)

            fig = go.Figure()
            fig.add_trace(go.Bar(name='Critical', x=risk_df['WEEK'], y=risk_df['CRITICAL']))
            fig.add_trace(go.Bar(name='High', x=risk_df['WEEK'], y=risk_df['HIGH']))
            fig.add_trace(go.Bar(name='Moderate', x=risk_df['WEEK'], y=risk_df['MODERATE']))
            fig.update_layout(barmode='stack', title='Patient Acuity by Week')
            st.plotly_chart(fig, use_container_width=True)
        except Exception as e:
            st.error(f"Error: {str(e)}")

# ============================================================================
# TAB 3: FINANCIAL PERFORMANCE
# ============================================================================

with tab3:
    st.header("💰 Financial Performance")

    # Financial KPIs
    col1, col2, col3, col4 = st.columns(4)

    try:
        financial_kpis_query = f"""
        SELECT 
            AVG(net_collection_rate_pct) as avg_collection_rate,
            AVG(denial_rate_pct) as avg_denial_rate,
            AVG(avg_days_in_ar) as avg_days_ar,
            SUM(total_charges) as total_charges
        FROM fct_financial_performance
        WHERE metric_date >= '{date_range[0]}'
          AND metric_date <= '{date_range[1]}'
          {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
        """
        fin_kpis = run_query(financial_kpis_query)

        with col1:
            collection_rate = fin_kpis['AVG_COLLECTION_RATE'].iloc[0]
            st.metric(
                "Net Collection Rate",
                f"{collection_rate:.1f}%",
                delta=f"{collection_rate - 95:.1f}% vs target (95%)"
            )

        with col2:
            denial_rate = fin_kpis['AVG_DENIAL_RATE'].iloc[0]
            st.metric(
                "Denial Rate",
                f"{denial_rate:.1f}%",
                delta=f"{10 - denial_rate:.1f}% vs target (10%)",
                delta_color="inverse"
            )

        with col3:
            days_ar = fin_kpis['AVG_DAYS_AR'].iloc[0]
            st.metric(
                "Days in AR",
                f"{days_ar:.0f} days",
                delta=f"{45 - days_ar:.0f} vs target (45 days)"
            )

        with col4:
            total_charges = fin_kpis['TOTAL_CHARGES'].iloc[0]
            st.metric(
                "Total Charges",
                f"${total_charges / 1e6:.1f}M"
            )
    except Exception as e:
        st.error(f"Error loading financial KPIs: {str(e)}")

    st.markdown("---")

    # Revenue cycle analysis
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("📊 AR Aging Distribution")
        try:
            ar_aging_query = f"""
            SELECT 
                ar_aging_bucket,
                SUM(charge_amount) as total_amount,
                COUNT(*) as transaction_count
            FROM fct_billing_transactions
            WHERE transaction_date >= '{date_range[0]}'
              AND transaction_date <= '{date_range[1]}'
              {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
            GROUP BY ar_aging_bucket
            ORDER BY 
                CASE ar_aging_bucket
                    WHEN '0-30 days' THEN 1
                    WHEN '31-60 days' THEN 2
                    WHEN '61-90 days' THEN 3
                    WHEN '91-120 days' THEN 4
                    ELSE 5
                END
            """
            ar_df = run_query(ar_aging_query)

            fig = px.pie(
                ar_df,
                values='TOTAL_AMOUNT',
                names='AR_AGING_BUCKET',
                title='AR Aging Distribution'
            )
            st.plotly_chart(fig, use_container_width=True)
        except Exception as e:
            st.error(f"Error: {str(e)}")

    with col2:
        st.subheader("💳 Payer Mix")
        try:
            payer_mix_query = f"""
            SELECT 
                p.payer_type,
                SUM(b.payment_amount) as total_payments,
                COUNT(*) as transaction_count
            FROM fct_billing_transactions b
            JOIN stg_reference__payers p ON b.payer_id = p.payer_id
            WHERE b.transaction_date >= '{date_range[0]}'
              AND b.transaction_date <= '{date_range[1]}'
              {f"AND b.hospital_id = '{hospital_id}'" if hospital_id else ""}
            GROUP BY p.payer_type
            """
            payer_df = run_query(payer_mix_query)

            fig = px.bar(
                payer_df,
                x='PAYER_TYPE',
                y='TOTAL_PAYMENTS',
                title='Revenue by Payer Type'
            )
            st.plotly_chart(fig, use_container_width=True)
        except Exception as e:
            st.error(f"Error: {str(e)}")

# ============================================================================
# TAB 4: SLA MONITORING
# ============================================================================

with tab4:
    st.header("⏰ SLA Monitoring & Compliance")

    try:
        sla_query = f"""
        SELECT 
            hospital_id,
            check_timestamp,
            encounters_freshness_minutes,
            freshness_sla_status,
            data_quality_score_pct,
            quality_sla_status,
            overall_sla_status,
            total_encounters,
            invalid_los_count + invalid_charges_count + invalid_dates_count as total_errors
        FROM fct_sla_monitoring
        {f"WHERE hospital_id = '{hospital_id}'" if hospital_id else ""}
        ORDER BY check_timestamp DESC
        LIMIT 50
        """
        sla_df = run_query(sla_query)

        # SLA Status Summary
        col1, col2, col3 = st.columns(3)

        compliant = len(sla_df[sla_df['OVERALL_SLA_STATUS'] == 'COMPLIANT'])
        warning = len(sla_df[sla_df['OVERALL_SLA_STATUS'] == 'WARNING'])
        breach = len(sla_df[sla_df['OVERALL_SLA_STATUS'] == 'BREACH'])

        with col1:
            st.metric("✅ Compliant", compliant)
        with col2:
            st.metric("⚠️ Warning", warning)
        with col3:
            st.metric("🚨 Breach", breach)

        st.markdown("---")

        # SLA Details Table
        st.subheader("📋 SLA Status by Hospital")


        # Color code the status
        def color_sla_status(val):
            if val == 'COMPLIANT':
                return 'background-color: #d4edda'
            elif val == 'WARNING':
                return 'background-color: #fff3cd'
            else:
                return 'background-color: #f8d7da'


        st.dataframe(
            sla_df.style.applymap(
                color_sla_status,
                subset=['FRESHNESS_SLA_STATUS', 'QUALITY_SLA_STATUS', 'OVERALL_SLA_STATUS']
            ),
            use_container_width=True
        )

        # Data Quality Trend
        st.subheader("📈 Data Quality Trend")
        fig = px.line(
            sla_df,
            x='CHECK_TIMESTAMP',
            y='DATA_QUALITY_SCORE_PCT',
            title='Data Quality Score Over Time',
            labels={'DATA_QUALITY_SCORE_PCT': 'Quality Score (%)'}
        )
        fig.add_hline(y=99, line_dash="dash", line_color="green", annotation_text="Target (99%)")
        st.plotly_chart(fig, use_container_width=True)

    except Exception as e:
        st.error(f"Error loading SLA data: {str(e)}")

# ============================================================================
# TAB 5: HIPAA AUDIT
# ============================================================================

with tab5:
    st.header("🔒 HIPAA Audit Trail")

    st.warning("⚠️ **PHI Access Logging** - All access to patient data is monitored and logged per HIPAA requirements")

    try:
        audit_summary_query = f"""
        SELECT 
            access_authorization_status,
            COUNT(*) as access_count,
            COUNT(DISTINCT user_name) as unique_users,
            SUM(records_accessed) as total_records,
            SUM(CASE WHEN is_unauthorized THEN 1 ELSE 0 END) as unauthorized_attempts
        FROM fct_hipaa_audit_trail
        WHERE access_timestamp >= '{date_range[0]}'
          AND access_timestamp <= '{date_range[1]}'
          {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
        GROUP BY access_authorization_status
        """
        audit_summary = run_query(audit_summary_query)

        # Audit Summary
        st.subheader("📊 Access Summary")
        st.dataframe(audit_summary, use_container_width=True)

        # Unauthorized access alerts
        unauthorized = audit_summary[audit_summary['UNAUTHORIZED_ATTEMPTS'] > 0]
        if len(unauthorized) > 0:
            st.error(
                f"🚨 **ALERT:** {unauthorized['UNAUTHORIZED_ATTEMPTS'].sum()} unauthorized PHI access attempts detected!")

        st.markdown("---")

        # Recent access log
        st.subheader("📜 Recent PHI Access Log")
        recent_access_query = f"""
        SELECT 
            access_timestamp,
            user_name,
            role_name,
            phi_type_accessed,
            hospital_id,
            records_accessed,
            access_authorization_status,
            is_unauthorized,
            is_bulk_access
        FROM fct_hipaa_audit_trail
        WHERE access_timestamp >= '{date_range[0]}'
          AND access_timestamp <= '{date_range[1]}'
          {f"AND hospital_id = '{hospital_id}'" if hospital_id else ""}
        ORDER BY access_timestamp DESC
        LIMIT 100
        """
        recent_access = run_query(recent_access_query)


        # Highlight unauthorized access
        def highlight_unauthorized(row):
            if row['IS_UNAUTHORIZED']:
                return ['background-color: #f8d7da'] * len(row)
            elif row['IS_BULK_ACCESS']:
                return ['background-color: #fff3cd'] * len(row)
            return [''] * len(row)


        st.dataframe(
            recent_access.style.apply(highlight_unauthorized, axis=1),
            use_container_width=True
        )

    except Exception as e:
        st.error(f"Error loading audit data: {str(e)}")

# Footer
st.markdown("---")
st.caption(f"Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | IsoMetrics Healthcare v1.0")