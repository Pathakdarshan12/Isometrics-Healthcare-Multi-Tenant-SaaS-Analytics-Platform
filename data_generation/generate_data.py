"""
IsoMetrics Healthcare Data Generator
Generates realistic multi-tenant healthcare data with HIPAA compliance considerations

Entities Generated:
- Hospitals (tenants)
- Patients (with demographics)
- Providers (physicians, nurses, specialists)
- Facilities (ICU, ER, Surgery, etc.)
- Encounters (admissions/visits)
- Diagnoses (ICD-10 codes)
- Procedures (CPT codes)
- Billing transactions
"""

import pandas as pd
import numpy as np
from faker import Faker
from datetime import timedelta
import random
import os
import hashlib

# Reproducible results
np.random.seed(42)
Faker.seed(42)
fake = Faker()

# ============================================
# HOSPITAL DISTRIBUTION (Tenant Configuration)
# ============================================

HOSPITAL_DISTRIBUTION = {
    'academic_medical_center': {
        'count': 5,
        'bed_count': (500, 1000),
        'daily_encounters': (200, 500),
        'patients': (10000, 50000),
        'providers': (200, 500),
        'specialties': 15,
        'contract_tier': 'Enterprise',
        'emr_system': 'Epic'
    },
    'community_hospital': {
        'count': 15,
        'bed_count': (100, 400),
        'daily_encounters': (50, 150),
        'patients': (5000, 20000),
        'providers': (50, 150),
        'specialties': 10,
        'contract_tier': 'Advanced',
        'emr_system': ['Epic', 'Cerner']
    },
    'rural_hospital': {
        'count': 30,
        'bed_count': (25, 100),
        'daily_encounters': (10, 40),
        'patients': (1000, 5000),
        'providers': (10, 40),
        'specialties': 5,
        'contract_tier': 'Basic',
        'emr_system': ['Meditech', 'CPSI']
    }
}

# ============================================
# MEDICAL CODE LIBRARIES
# ============================================

# Common ICD-10 diagnosis codes (simplified for demo)
ICD10_CODES = {
    'I10': {'description': 'Essential (primary) hypertension', 'category': 'Cardiovascular', 'severity': 'Moderate'},
    'E11.9': {'description': 'Type 2 diabetes mellitus without complications', 'category': 'Endocrine', 'severity': 'Moderate'},
    'J44.9': {'description': 'COPD, unspecified', 'category': 'Respiratory', 'severity': 'High'},
    'I50.9': {'description': 'Heart failure, unspecified', 'category': 'Cardiovascular', 'severity': 'High'},
    'N18.9': {'description': 'Chronic kidney disease, unspecified', 'category': 'Renal', 'severity': 'High'},
    'J18.9': {'description': 'Pneumonia, unspecified organism', 'category': 'Respiratory', 'severity': 'High'},
    'I63.9': {'description': 'Cerebral infarction, unspecified', 'category': 'Neurological', 'severity': 'Critical'},
    'S72.001A': {'description': 'Fracture of unspecified part of neck of right femur', 'category': 'Injury', 'severity': 'High'},
    'I21.9': {'description': 'Acute myocardial infarction, unspecified', 'category': 'Cardiovascular', 'severity': 'Critical'},
    'K92.2': {'description': 'Gastrointestinal hemorrhage, unspecified', 'category': 'Digestive', 'severity': 'High'},
    'Z00.00': {'description': 'Encounter for general adult medical examination', 'category': 'Wellness', 'severity': 'Low'},
    'O80': {'description': 'Encounter for full-term uncomplicated delivery', 'category': 'Obstetric', 'severity': 'Moderate'},
    'F32.9': {'description': 'Major depressive disorder, single episode', 'category': 'Mental Health', 'severity': 'Moderate'},
    'M17.9': {'description': 'Osteoarthritis of knee, unspecified', 'category': 'Musculoskeletal', 'severity': 'Moderate'},
    'Z12.11': {'description': 'Encounter for screening for malignant neoplasm of colon', 'category': 'Prevention', 'severity': 'Low'}
}

# Common CPT procedure codes (simplified)
CPT_CODES = {
    '99285': {'description': 'Emergency department visit, high severity', 'category': 'Emergency', 'typical_charge': (800, 1500)},
    '99223': {'description': 'Initial hospital care, high complexity', 'category': 'Inpatient', 'typical_charge': (300, 600)},
    '99291': {'description': 'Critical care, first hour', 'category': 'Critical Care', 'typical_charge': (500, 1000)},
    '36415': {'description': 'Routine venipuncture', 'category': 'Lab', 'typical_charge': (10, 25)},
    '93000': {'description': 'Electrocardiogram, complete', 'category': 'Diagnostic', 'typical_charge': (50, 150)},
    '71046': {'description': 'Chest X-ray', 'category': 'Imaging', 'typical_charge': (100, 300)},
    '70450': {'description': 'CT scan, head without contrast', 'category': 'Imaging', 'typical_charge': (500, 1200)},
    '99232': {'description': 'Subsequent hospital care', 'category': 'Inpatient', 'typical_charge': (100, 250)},
    '43239': {'description': 'Upper GI endoscopy with biopsy', 'category': 'Procedure', 'typical_charge': (800, 2000)},
    '27447': {'description': 'Total knee arthroplasty', 'category': 'Surgery', 'typical_charge': (15000, 35000)}
}

# Medical specialties
SPECIALTIES = [
    'Internal Medicine', 'Family Medicine', 'Emergency Medicine',
    'Cardiology', 'Pulmonology', 'Neurology', 'Orthopedics',
    'General Surgery', 'Obstetrics', 'Pediatrics', 'Psychiatry',
    'Radiology', 'Anesthesiology', 'Oncology', 'Nephrology'
]

# Facility types
FACILITY_TYPES = [
    'Emergency Department', 'Intensive Care Unit', 'Medical-Surgical Unit',
    'Operating Room', 'Labor & Delivery', 'Observation Unit',
    'Cardiac Catheterization Lab', 'Endoscopy Suite', 'Radiology',
    'Outpatient Clinic', 'Urgent Care'
]

# Payer types
PAYERS = [
    {'payer_name': 'Medicare', 'payer_type': 'Government', 'reimbursement_rate': 0.85},
    {'payer_name': 'Medicaid', 'payer_type': 'Government', 'reimbursement_rate': 0.70},
    {'payer_name': 'Blue Cross Blue Shield', 'payer_type': 'Commercial', 'reimbursement_rate': 0.95},
    {'payer_name': 'Aetna', 'payer_type': 'Commercial', 'reimbursement_rate': 0.92},
    {'payer_name': 'UnitedHealthcare', 'payer_type': 'Commercial', 'reimbursement_rate': 0.93},
    {'payer_name': 'Cigna', 'payer_type': 'Commercial', 'reimbursement_rate': 0.90},
    {'payer_name': 'Humana', 'payer_type': 'Commercial', 'reimbursement_rate': 0.88},
    {'payer_name': 'Self-Pay', 'payer_type': 'Self-Pay', 'reimbursement_rate': 0.30}
]

class HealthcareDataGenerator:
    """
    Generates realistic healthcare data for multi-tenant analytics platform
    """

    def __init__(self, start_date='2023-01-01', end_date='2023-12-31'):
        self.start_date = pd.to_datetime(start_date)
        self.end_date = pd.to_datetime(end_date)
        self.date_range = pd.date_range(start_date, end_date, freq='D')

        print("=" * 70)
        print("IsoMetrics Healthcare Data Generator")
        print("=" * 70)
        print(f"Date Range: {start_date} to {end_date}")
        print(f"Total Days: {len(self.date_range)}")
        print(f"HIPAA Compliance: Generating synthetic PHI")
        print("=" * 70)

    def generate_hospitals(self):
        """Generate hospital master data (tenants)"""
        print("\nGenerating hospitals (tenants)...")
        hospitals = []
        hospital_id = 1

        for hospital_type, config in HOSPITAL_DISTRIBUTION.items():
            for i in range(config['count']):
                # Geographic distribution
                state = fake.state_abbr()
                city = fake.city()

                # EMR system
                if isinstance(config['emr_system'], list):
                    emr = random.choice(config['emr_system'])
                else:
                    emr = config['emr_system']

                hospital = {
                    'hospital_id': f'HOSP_{hospital_id:04d}',
                    'hospital_name': f"{city} {hospital_type.replace('_', ' ').title()}",
                    'hospital_type': hospital_type,
                    'bed_count': random.randint(*config['bed_count']),
                    'city': city,
                    'state': state,
                    'region': self._get_region(state),
                    'emr_system': emr,
                    'contract_tier': config['contract_tier'],
                    'contract_start_date': self.start_date - timedelta(days=random.randint(0, 730)),
                    'is_active': True,
                    'teaching_hospital': hospital_type == 'academic_medical_center'
                }
                hospitals.append(hospital)
                hospital_id += 1

        df = pd.DataFrame(hospitals)
        print(f"Generated {len(df)} hospitals")
        print(f"  - Academic Medical Centers: {len(df[df['hospital_type']=='academic_medical_center'])}")
        print(f"  - Community Hospitals: {len(df[df['hospital_type']=='community_hospital'])}")
        print(f"  - Rural Hospitals: {len(df[df['hospital_type']=='rural_hospital'])}")

        return df

    def _get_region(self, state):
        """Map state to US census region"""
        regions = {
            'Northeast': ['CT', 'ME', 'MA', 'NH', 'RI', 'VT', 'NJ', 'NY', 'PA'],
            'Midwest': ['IL', 'IN', 'MI', 'OH', 'WI', 'IA', 'KS', 'MN', 'MO', 'NE', 'ND', 'SD'],
            'South': ['DE', 'FL', 'GA', 'MD', 'NC', 'SC', 'VA', 'WV', 'AL', 'KY', 'MS', 'TN', 'AR', 'LA', 'OK', 'TX'],
            'West': ['AZ', 'CO', 'ID', 'MT', 'NV', 'NM', 'UT', 'WY', 'AK', 'CA', 'HI', 'OR', 'WA']
        }
        for region, states in regions.items():
            if state in states:
                return region
        return 'Other'

    def generate_patients(self, hospitals_df):
        """Generate patient demographics (PHI - Protected Health Information)"""
        print("\n👥 Generating patients (PHI)...")
        patients = []
        patient_id = 1

        for _, hospital in hospitals_df.iterrows():
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]
            num_patients = random.randint(*config['patients'])

            for i in range(num_patients):
                # Patient demographics
                gender = random.choice(['M', 'F', 'Other'])
                date_of_birth = fake.date_of_birth(minimum_age=0, maximum_age=95)

                # Generate MRN (Medical Record Number) - hospital-specific
                mrn = f"{hospital['hospital_id']}-{patient_id:08d}"

                # Hash SSN for privacy (never store real SSN!)
                ssn_hash = hashlib.sha256(f"SSN-{patient_id}".encode()).hexdigest()[:16]

                patient = {
                    'patient_id': f'PAT_{patient_id:010d}',
                    'hospital_id': hospital['hospital_id'],
                    'mrn': mrn,
                    'ssn_hash': ssn_hash,  # Hashed, not actual SSN
                    'first_name': fake.first_name_male() if gender == 'M' else fake.first_name_female(),
                    'last_name': fake.last_name(),
                    'date_of_birth': date_of_birth,
                    'gender': gender,
                    'race': random.choice(['White', 'Black', 'Asian', 'Hispanic', 'Other', 'Unknown']),
                    'ethnicity': random.choice(['Hispanic or Latino', 'Not Hispanic or Latino', 'Unknown']),
                    'zip_code': fake.zipcode(),
                    'phone_number_hash': hashlib.sha256(fake.phone_number().encode()).hexdigest()[:16],
                    'email_hash': hashlib.sha256(fake.email().encode()).hexdigest()[:16],
                    'primary_language': random.choice(['English', 'Spanish', 'Chinese', 'Other']),
                    'marital_status': random.choice(['Single', 'Married', 'Divorced', 'Widowed']),
                    'first_encounter_date': hospital['contract_start_date'] + timedelta(days=random.randint(0, 365))
                }
                patients.append(patient)
                patient_id += 1

        df = pd.DataFrame(patients)
        print(f"Generated {len(df):,} patients")
        print(f" Note: All PHI is synthetic (HIPAA-safe for demo)")

        return df

    def generate_providers(self, hospitals_df):
        """Generate provider roster (physicians, nurses, specialists)"""
        print("\n️Generating providers...")
        providers = []
        provider_id = 1

        for _, hospital in hospitals_df.iterrows():
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]
            num_providers = random.randint(*config['providers'])

            # Specialty distribution
            available_specialties = SPECIALTIES[:config['specialties']]

            for i in range(num_providers):
                hire_date = hospital['contract_start_date'] + timedelta(days=random.randint(-1000, 0))

                # Generate NPI (National Provider Identifier)
                npi = f"{random.randint(1000000000, 9999999999)}"

                specialty = random.choice(available_specialties)

                provider = {
                    'provider_id': f'PROV_{provider_id:08d}',
                    'hospital_id': hospital['hospital_id'],
                    'npi': npi,
                    'provider_first_name': fake.first_name(),
                    'provider_last_name': fake.last_name(),
                    'specialty': specialty,
                    'department': self._get_department(specialty),
                    'provider_type': random.choice(['MD', 'DO', 'NP', 'PA']),
                    'hire_date': hire_date,
                    'is_active': random.choice([True, True, True, False]),  # 75% active
                    'accepts_new_patients': random.choice([True, False])
                }
                providers.append(provider)
                provider_id += 1

        df = pd.DataFrame(providers)
        print(f"Generated {len(df):,} providers")

        return df

    def _get_department(self, specialty):
        """Map specialty to department"""
        dept_mapping = {
            'Emergency Medicine': 'Emergency Department',
            'Internal Medicine': 'Medicine',
            'Family Medicine': 'Primary Care',
            'Cardiology': 'Cardiology',
            'General Surgery': 'Surgery',
            'Orthopedics': 'Surgery',
            'Obstetrics': 'Women\'s Health'
        }
        return dept_mapping.get(specialty, 'Medicine')

    def generate_facilities(self, hospitals_df):
        """Generate facility/department master data"""
        print("\nGenerating facilities...")
        facilities = []
        facility_id = 1

        for _, hospital in hospitals_df.iterrows():
            # Each hospital has standard facilities
            for facility_type in FACILITY_TYPES:
                capacity = self._get_facility_capacity(facility_type, hospital['bed_count'])

                facility = {
                    'facility_id': f'FAC_{facility_id:08d}',
                    'hospital_id': hospital['hospital_id'],
                    'facility_name': f"{hospital['hospital_name']} - {facility_type}",
                    'facility_type': facility_type,
                    'bed_capacity': capacity,
                    'is_active': True,
                    'opened_date': hospital['contract_start_date']
                }
                facilities.append(facility)
                facility_id += 1

        df = pd.DataFrame(facilities)
        print(f"Generated {len(df):,} facilities")

        return df

    def _get_facility_capacity(self, facility_type, hospital_beds):
        """Calculate facility capacity based on type and hospital size"""
        ratios = {
            'Emergency Department': 0.05,
            'Intensive Care Unit': 0.10,
            'Medical-Surgical Unit': 0.50,
            'Operating Room': 0.03,
            'Labor & Delivery': 0.05
        }
        ratio = ratios.get(facility_type, 0.10)
        return max(int(hospital_beds * ratio), 5)

    def generate_diagnoses_reference(self):
        """Generate diagnosis code reference table"""
        print("\nGenerating diagnosis codes (ICD-10)...")

        diagnoses = []
        for code, details in ICD10_CODES.items():
            diagnoses.append({
                'diagnosis_code': code,
                'diagnosis_description': details['description'],
                'category': details['category'],
                'severity_level': details['severity'],
                'is_chronic': details['severity'] in ['High', 'Critical']
            })

        df = pd.DataFrame(diagnoses)
        print(f"Generated {len(df)} diagnosis codes")

        return df

    def generate_procedures_reference(self):
        """Generate procedure code reference table"""
        print("\nGenerating procedure codes (CPT)...")

        procedures = []
        for code, details in CPT_CODES.items():
            procedures.append({
                'procedure_code': code,
                'procedure_description': details['description'],
                'category': details['category'],
                'typical_charge_min': details['typical_charge'][0],
                'typical_charge_max': details['typical_charge'][1]
            })

        df = pd.DataFrame(procedures)
        print(f"Generated {len(df)} procedure codes")

        return df

    def generate_payers_reference(self):
        """Generate payer/insurance reference table"""
        print("\nGenerating payers (insurance companies)...")

        payers_list = []
        for i, payer in enumerate(PAYERS, 1):
            payers_list.append({
                'payer_id': f'PAY_{i:04d}',
                'payer_name': payer['payer_name'],
                'payer_type': payer['payer_type'],
                'reimbursement_rate': payer['reimbursement_rate'],
                'is_active': True
            })

        df = pd.DataFrame(payers_list)
        print(f"Generated {len(df)} payers")

        return df

    def generate_encounters(self, hospitals_df, patients_df, providers_df, facilities_df):
        """
        Generate patient encounters (admissions/visits) - THE MAIN FACT TABLE
        This is the most complex and important table
        """
        print("\nGenerating encounters (admissions/visits)...")
        print(" This may take several minutes...")

        encounters = []
        encounter_id = 1

        # Track recent discharges for readmission logic
        recent_discharges = {}

        for _, hospital in hospitals_df.iterrows():
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]

            # Get hospital's patients, providers, facilities
            hosp_patients = patients_df[patients_df['hospital_id'] == hospital['hospital_id']]
            hosp_providers = providers_df[
                (providers_df['hospital_id'] == hospital['hospital_id']) &
                (providers_df['is_active'] == True)
            ]
            hosp_facilities = facilities_df[facilities_df['hospital_id'] == hospital['hospital_id']]

            if len(hosp_patients) == 0 or len(hosp_providers) == 0:
                continue

            # Generate encounters for each day
            for date in self.date_range:
                if date < hospital['contract_start_date']:
                    continue

                # Daily encounter volume with seasonality
                base_encounters = random.randint(*config['daily_encounters'])
                seasonality = self._calculate_seasonality(date)
                num_encounters = int(base_encounters * seasonality)

                for _ in range(num_encounters):
                    # Random patient
                    patient = hosp_patients.sample(1).iloc[0]
                    if date < patient['first_encounter_date']:
                        continue

                    # Random provider
                    provider = hosp_providers.sample(1).iloc[0]

                    # Encounter type distribution
                    encounter_type = random.choices(
                        ['Inpatient', 'Outpatient', 'Emergency', 'Observation'],
                        weights=[0.20, 0.50, 0.25, 0.05]
                    )[0]

                    # Admission timestamp
                    hour = int(np.random.choice(range(24), p=self._get_hourly_dist()))
                    admission_dt = date + timedelta(hours=hour, minutes=random.randint(0, 59))

                    # Length of stay based on encounter type
                    los = int(self._calculate_length_of_stay(encounter_type))
                    discharge_dt = admission_dt + timedelta(days=los, hours=random.randint(0, 23))

                    # Facility assignment
                    facility = self._assign_facility(encounter_type, hosp_facilities)

                    # Diagnosis (primary)
                    diagnosis_code = random.choice(list(ICD10_CODES.keys()))

                    # Check if this is a readmission (within 30 days of previous discharge)
                    is_readmission = self._check_readmission(
                        patient['patient_id'],
                        admission_dt,
                        recent_discharges
                    )

                    # Track discharge for future readmission checks
                    recent_discharges[patient['patient_id']] = discharge_dt

                    # Financial calculations
                    total_charges = self._calculate_charges(encounter_type, los)

                    encounter = {
                        'encounter_id': f'ENC_{encounter_id:012d}',
                        'hospital_id': hospital['hospital_id'],
                        'patient_id': patient['patient_id'],
                        'provider_id': provider['provider_id'],
                        'facility_id': facility['facility_id'],
                        'admission_date': admission_dt,
                        'discharge_date': discharge_dt,
                        'length_of_stay': los,
                        'encounter_type': encounter_type,
                        'admission_source': random.choice(['Emergency', 'Physician Referral', 'Transfer', 'Elective']),
                        'discharge_disposition': random.choice(['Home', 'Home Health', 'SNF', 'Rehab', 'Deceased']),
                        'primary_diagnosis_code': diagnosis_code,
                        'total_charges': total_charges,
                        'is_readmission': is_readmission
                    }
                    encounters.append(encounter)
                    encounter_id += 1

            if encounter_id % 10000 == 0:
                print(f" Progress: {encounter_id:,} encounters generated...")

        df = pd.DataFrame(encounters)

        # Calculate readmission rate
        readmission_rate = df['is_readmission'].sum() * 100.0 / len(df)

        print(f"Generated {len(df):,} encounters")
        print(f" - Inpatient: {len(df[df['encounter_type']=='Inpatient']):,}")
        print(f" - Outpatient: {len(df[df['encounter_type']=='Outpatient']):,}")
        print(f" - Emergency: {len(df[df['encounter_type']=='Emergency']):,}")
        print(f" - 30-day Readmissions: {df['is_readmission'].sum():,} ({readmission_rate:.1f}%)")

        return df

    def _calculate_seasonality(self, date):
        """Healthcare has seasonal patterns (flu season, etc.)"""
        month = date.month
        if month in [12, 1, 2]:  # Winter - flu season
            return 1.3
        elif month in [7, 8]:  # Summer - lower volume
            return 0.85
        return 1.0

    def _get_hourly_dist(self):
        """Healthcare encounters peak during daytime"""
        hours = [
            0.01, 0.01, 0.01, 0.02, 0.02, 0.03,  # 12am-6am (night)
            0.04, 0.06, 0.08, 0.09, 0.10, 0.09,  # 6am-12pm (morning)
            0.08, 0.07, 0.06, 0.05, 0.04, 0.04,  # 12pm-6pm (afternoon)
            0.05, 0.04, 0.03, 0.02, 0.02, 0.01   # 6pm-12am (evening)
        ]
        return np.array(hours) / sum(hours)

    def _calculate_length_of_stay(self, encounter_type):
        """Calculate realistic length of stay"""
        if encounter_type == 'Inpatient':
            return max(1, int(np.random.lognormal(1.2, 0.8)))  # Mean ~4 days
        elif encounter_type == 'Observation':
            return random.choice([0, 1])
        elif encounter_type == 'Emergency':
            return 0
        else:  # Outpatient
            return 0

    def _assign_facility(self, encounter_type, facilities_df):
        """Assign appropriate facility based on encounter type"""
        if encounter_type == 'Emergency':
            facility = facilities_df[facilities_df['facility_type'] == 'Emergency Department']
        elif encounter_type == 'Inpatient':
            facility = facilities_df[facilities_df['facility_type'].isin([
                'Medical-Surgical Unit', 'Intensive Care Unit'
            ])]
        else:
            facility = facilities_df[facilities_df['facility_type'] == 'Outpatient Clinic']

        if len(facility) > 0:
            return facility.sample(1).iloc[0]
        else:
            return facilities_df.sample(1).iloc[0]

    def _check_readmission(self, patient_id, admission_date, recent_discharges):
        """Check if encounter is a 30-day readmission"""
        if patient_id in recent_discharges:
            last_discharge = recent_discharges[patient_id]
            days_since_discharge = (admission_date - last_discharge).days
            if 0 < days_since_discharge <= 30:
                return True
        return False

    def _calculate_charges(self, encounter_type, los):
        """Calculate total charges based on encounter type and LOS"""
        if encounter_type == 'Inpatient':
            daily_charge = random.uniform(2000, 5000)
            return round(daily_charge * max(los, 1), 2)
        elif encounter_type == 'Emergency':
            return round(random.uniform(500, 3000), 2)
        elif encounter_type == 'Observation':
            return round(random.uniform(1000, 2500), 2)
        else:  # Outpatient
            return round(random.uniform(100, 800), 2)

    def generate_billing_transactions(self, encounters_df, payers_df):
        """Generate billing/payment transactions"""
        print("\nGenerating billing transactions...")

        transactions = []
        transaction_id = 1

        for _, encounter in encounters_df.iterrows():
            # Assign payer (insurance)
            payer = payers_df.sample(1).iloc[0]

            charge_amount = encounter['total_charges']

            # Calculate payment based on payer reimbursement rate
            payment_amount = round(charge_amount * payer['reimbursement_rate'], 2)

            # Adjustment (difference between charge and payment)
            adjustment_amount = round(charge_amount - payment_amount, 2)

            # Payment status
            payment_status = random.choices(
                ['Paid', 'Pending', 'Denied', 'Partial'],
                weights=[0.70, 0.15, 0.10, 0.05]
            )[0]

            # Denial reason (if denied)
            denial_reason = None
            if payment_status == 'Denied':
                denial_reason = random.choice([
                    'Medical Necessity', 'Prior Authorization Required',
                    'Out of Network', 'Coding Error'
                ])

            # Transaction date (after discharge)
            transaction_date = encounter['discharge_date'] + timedelta(days=random.randint(1, 45))

            transaction = {
                'transaction_id': f'TXN_{transaction_id:012d}',
                'hospital_id': encounter['hospital_id'],
                'encounter_id': encounter['encounter_id'],
                'patient_id': encounter['patient_id'],
                'payer_id': payer['payer_id'],
                'transaction_date': transaction_date,
                'charge_amount': charge_amount,
                'payment_amount': payment_amount if payment_status == 'Paid' else 0,
                'adjustment_amount': adjustment_amount,
                'denial_reason': denial_reason,
                'payment_status': payment_status
            }
            transactions.append(transaction)
            transaction_id += 1

        df = pd.DataFrame(transactions)
        print(f"Generated {len(df):,} billing transactions")

        return df

    def save_to_csv(self, df, filename, output_dir='data'):
        """Save DataFrame to CSV"""
        os.makedirs(output_dir, exist_ok=True)
        filepath = os.path.join(output_dir, filename)
        df.to_csv(filepath, index=False)

        # Calculate file size
        size_mb = os.path.getsize(filepath) / (1024 * 1024)
        print(f"Saved: {filename} ({len(df):,} rows, {size_mb:.2f} MB)")

def main():
    print("\n")
    print("=" * 70)
    print("IsoMetrics Healthcare Data Generator")
    print(" Multi-Tenant Healthcare Analytics Platform")
    print("=" * 70)

    # Initialize generator
    generator = HealthcareDataGenerator(
        start_date='2023-01-01',
        end_date='2023-01-31'
    )

    # Generate all data
    hospitals = generator.generate_hospitals()
    generator.save_to_csv(hospitals, 'hospitals.csv')

    # providers = generator.generate_providers(hospitals)
    # generator.save_to_csv(providers, 'providers.csv')

    # facilities = generator.generate_facilities(hospitals)
    # generator.save_to_csv(facilities, 'facilities.csv')

    # diagnoses = generator.generate_diagnoses_reference()
    # generator.save_to_csv(diagnoses, 'diagnoses.csv')

    # procedures = generator.generate_procedures_reference()
    # generator.save_to_csv(procedures, 'procedures.csv')

    # payers = generator.generate_payers_reference()
    # generator.save_to_csv(payers, 'payers.csv')

    # encounters = generator.generate_encounters(hospitals, patients, providers, facilities)
    # generator.save_to_csv(encounters, 'encounters.csv')

    # billing = generator.generate_billing_transactions(encounters, payers)
    # generator.save_to_csv(billing, 'billing_transactions.csv')

    # Summary statistics
    print("\n" + "=" * 70)
    print("GENERATION COMPLETE!")
    print("=" * 70)


    print(f"Hospitals:    {len(hospitals):,}")

    # patients = generator.generate_patients(hospitals)
    # generator.save_to_csv(patients, 'patients.csv')
    # print(f"Patients:     {len(patients):,}")
    # print(f"Providers:    {len(providers):,}")
    # print(f"Facilities:   {len(facilities):,}")
    # print(f"Encounters:   {len(encounters):,}")
    # print(f"Billing Txns: {len(billing):,}")
    # print(f"\nTotal Charges: ${encounters['total_charges'].sum():,.2f}")
    # print(f"Avg Charges per Encounter: ${encounters['total_charges'].mean():,.2f}")
    # print(f"30-Day Readmission Rate: {encounters['is_readmission'].sum() * 100.0 / len(encounters):.2f}%")
    # print(f"Date Range: {encounters['admission_date'].min()} to {encounters['discharge_date'].max()}")
    # print("\n  All PHI is synthetic - HIPAA-safe for demonstration")
    print("=" * 70)

if __name__ == "__main__":
    main()