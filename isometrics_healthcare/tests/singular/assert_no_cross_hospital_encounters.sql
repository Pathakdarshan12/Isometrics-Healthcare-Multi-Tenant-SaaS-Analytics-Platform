-- CRITICAL TEST: Ensure no encounters reference patients from different hospitals
select
    e.encounter_id,
    e.hospital_id as encounter_hospital,
    p.hospital_id as patient_hospital
from {{ ref('stg_healthcare__encounters') }} e
join {{ ref('stg_healthcare__patients') }} p
    on e.patient_id = p.patient_id
where e.hospital_id != p.hospital_id