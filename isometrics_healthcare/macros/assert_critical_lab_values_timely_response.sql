/*
  CRITICAL SAFETY TEST: Critical Lab Values Without Timely Follow-up

  Critical laboratory values require immediate provider notification and
  documentation of acknowledgment within specified timeframes (typically 1 hour).

  This test identifies critical values that may not have been appropriately
  addressed based on subsequent orders or interventions.

  SEVERITY: CRITICAL - Patient safety risk

  Expected Result: All critical values should have follow-up orders within 2 hours
*/

with critical_labs as (
    select
        result_id,
        hospital_id,
        encounter_id,
        patient_id,
        test_code,
        test_name,
        result_value,
        result_value_numeric,
        result_units,
        result_datetime,
        is_critical_value,

        -- Identify specific critical value type
        case
            when lower(test_name) like '%glucose%' and result_value_numeric < 40 then 'Severe Hypoglycemia'
            when lower(test_name) like '%glucose%' and result_value_numeric > 500 then 'Severe Hyperglycemia'
            when lower(test_name) like '%potassium%' and result_value_numeric < 2.5 then 'Severe Hypokalemia'
            when lower(test_name) like '%potassium%' and result_value_numeric > 6.5 then 'Severe Hyperkalemia'
            when lower(test_name) like '%sodium%' and result_value_numeric < 120 then 'Severe Hyponatremia'
            when lower(test_name) like '%sodium%' and result_value_numeric > 160 then 'Severe Hypernatremia'
            when lower(test_name) like '%hemoglobin%' and result_value_numeric < 6 then 'Severe Anemia'
            when lower(test_name) like '%creatinine%' and result_value_numeric > 10 then 'Severe Renal Failure'
            when lower(test_name) like '%troponin%' and result_value_numeric > 0.5 then 'Positive Troponin (AMI)'
            when lower(test_name) like '%inr%' and result_value_numeric > 5 then 'Critical INR'
            else 'Other Critical Value'
        end as critical_value_type,

        -- Expected timeframe for response (in hours)
        case
            when lower(test_name) like any ('%glucose%', '%potassium%') then 1  -- Most urgent
            when lower(test_name) like '%troponin%' then 1  -- Cardiac emergency
            else 2  -- Standard critical value response
        end as expected_response_hours

    from {{ ref('int_clinical__lab_results_enriched') }}
    where is_critical_value = true
    and is_final = true  -- Only final results
    and result_datetime >= dateadd('day', -30, current_date())  -- Last 30 days
),

-- Check for follow-up orders after critical value
follow_up_orders as (
    select
        cl.result_id,
        cl.hospital_id,
        cl.encounter_id,
        cl.patient_id,
        cl.test_name,
        cl.result_value,
        cl.critical_value_type,
        cl.result_datetime,
        cl.expected_response_hours,

        -- Check for any orders placed after the critical result
        min(o.order_datetime) as first_order_after_result,

        -- Calculate response time
        datediff('minute', cl.result_datetime, min(o.order_datetime)) / 60.0 as response_time_hours,

        -- Count of orders within expected timeframe
        count(distinct case
            when o.order_datetime between cl.result_datetime
                and dateadd('hour', cl.expected_response_hours, cl.result_datetime)
            then o.order_id
        end) as orders_within_timeframe

    from critical_labs cl
    left join {{ ref('stg_healthcare__clinical_orders') }} o
        on cl.encounter_id = o.encounter_id
        and cl.hospital_id = o.hospital_id
        and o.order_datetime > cl.result_datetime  -- Orders after the result
        and o.order_datetime <= dateadd('hour', 24, cl.result_datetime)  -- Within 24 hours
    group by
        cl.result_id,
        cl.hospital_id,
        cl.encounter_id,
        cl.patient_id,
        cl.test_name,
        cl.result_value,
        cl.critical_value_type,
        cl.result_datetime,
        cl.expected_response_hours
),

violations as (
    select
        result_id,
        hospital_id,
        encounter_id,
        patient_id,
        test_name,
        result_value,
        critical_value_type,
        result_datetime,
        expected_response_hours,
        first_order_after_result,
        response_time_hours,
        orders_within_timeframe,

        -- Violation type
        case
            when first_order_after_result is null then 'NO FOLLOW-UP ORDERS'
            when response_time_hours > expected_response_hours then 'DELAYED RESPONSE'
            else 'NO VIOLATION'
        end as violation_type,

        -- Error message
        '🚨 CRITICAL LAB VALUE NOT ADDRESSED: ' || test_name || ' = ' || result_value ||
        ' (Type: ' || critical_value_type || ') ' ||
        case
            when first_order_after_result is null
            then 'No follow-up orders found within 24 hours'
            else 'Response delayed by ' || round(response_time_hours - expected_response_hours, 1) || ' hours'
        end as error_message,

        current_timestamp() as test_run_timestamp

    from follow_up_orders
    where
        -- Violations: Either no orders at all, or response too slow
        first_order_after_result is null
        or response_time_hours > expected_response_hours
)

-- Return all violations
select
    result_id,
    hospital_id,
    encounter_id,
    patient_id,
    test_name,
    result_value,
    critical_value_type,
    result_datetime,
    expected_response_hours,
    first_order_after_result,
    response_time_hours,
    violation_type,
    error_message,

    -- Action required
    case
        when violation_type = 'NO FOLLOW-UP ORDERS' then
            '⚠️ CRITICAL: Verify provider was notified. Document acknowledgment. Review patient status.'
        when response_time_hours > expected_response_hours * 2 then
            '⚠️ SEVERE DELAY: Investigate notification process. Patient safety review required.'
        else
            '⚠️ DELAYED RESPONSE: Review notification workflow. Ensure timely provider response.'
    end as action_required,

    -- Calculate hours since critical value
    datediff('hour', result_datetime, current_timestamp()) as hours_since_critical_value

from violations
where
    -- Focus on recent violations and severe cases
    datediff('hour', result_datetime, current_timestamp()) <= 48  -- Last 48 hours
    or violation_type = 'NO FOLLOW-UP ORDERS'
order by
    violation_type,
    result_datetime desc