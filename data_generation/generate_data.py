import pandas as pd
import numpy as np
from faker import Faker
from datetime import timedelta, datetime
import random
import os
import hashlib
from tqdm import tqdm
from typing import Generator, Dict, List
import gc

# Reproducible results
np.random.seed(42)
Faker.seed(42)
random.seed(42)
fake = Faker()

# Import configurations
from medical_codes_library import (
    HOSPITAL_DISTRIBUTION, ICD10_CODES, CPT_CODES, SPECIALTIES,
    FACILITY_TYPES, PAYERS, ADMISSION_TYPES, DISCHARGE_DISPOSITIONS,
    DENIAL_REASONS, US_REGIONS,
)

from clinical_codes_library import (
    LAB_TESTS, MEDICATIONS, COMMON_ALLERGENS, CHRONIC_DIAGNOSES
)

BATCH_SIZE = 50000


class HealthcareDataGenerator:
    """Complete healthcare data generator with all clinical tables"""

    def __init__(self, start_date='2025-01-01', end_date='2025-01-31'):
        self.start_date = pd.to_datetime(start_date)
        self.end_date = pd.to_datetime(end_date)
        self.days = (self.end_date - self.start_date).days + 1

        # Track relationships for data integrity
        self.hospital_patients = {}
        self.hospital_providers = {}
        self.hospital_facilities = {}
        self.patient_encounters = {}

        print("=" * 70)
        print("IsoMetrics Healthcare Data Generator - COMPLETE VERSION")
        print("=" * 70)
        print(f"Date Range: {start_date} to {end_date}")
        print(f"Total Days: {self.days}")
        print("=" * 70)

    @staticmethod
    def get_region(state: str) -> str:
        """Fast region lookup"""
        for region, states in US_REGIONS.items():
            if state in states:
                return region
        return 'Other'

    def generate_vital_signs(self, encounters_df):
        """Generate vital signs for encounters"""
        print("\n🩺 Generating vital signs...")
        vitals = []
        vital_id = 1

        for _, encounter in tqdm(encounters_df.iterrows(), total=len(encounters_df), desc="Encounters"):
            # Determine number of measurements based on encounter type
            if encounter['encounter_type'] == 'Emergency':
                num_measurements = random.randint(3, 8)
            elif encounter['encounter_type'] == 'Inpatient':
                num_measurements = max(1, int(encounter['length_of_stay']) * random.randint(2, 4))
            else:
                num_measurements = 1

            for i in range(num_measurements):
                hours_offset = (i * (encounter['length_of_stay'] * 24 / max(num_measurements, 1)))
                measurement_time = encounter['admission_date'] + timedelta(hours=hours_offset)

                temp_f = round(np.random.normal(98.6, 1.0), 1)
                hr = max(40, min(180, int(np.random.normal(75, 12))))
                rr = max(8, min(40, int(np.random.normal(16, 3))))
                sbp = max(70, min(200, int(np.random.normal(120, 15))))
                dbp = max(40, min(120, int(np.random.normal(80, 10))))
                spo2 = max(85, min(100, int(np.random.normal(97, 2))))

                if i == 0:
                    weight_kg = max(40, np.random.normal(75, 15))
                    height_cm = max(140, np.random.normal(170, 10))

                bmi = weight_kg / ((height_cm / 100) ** 2)
                pain = random.randint(0, 10) if random.random() < 0.4 else 0
                map_mmhg = int((sbp + 2 * dbp) / 3)

                vitals.append({
                    'vital_id': f'VIT_{vital_id:012d}',
                    'hospital_id': encounter['hospital_id'],
                    'encounter_id': encounter['encounter_id'],
                    'patient_id': encounter['patient_id'],
                    'measurement_datetime': measurement_time,
                    'temperature_f': temp_f,
                    'heart_rate_bpm': hr,
                    'respiratory_rate': rr,
                    'systolic_bp': sbp,
                    'diastolic_bp': dbp,
                    'oxygen_saturation_pct': spo2,
                    'weight_kg': round(weight_kg, 1),
                    'height_cm': round(height_cm, 1),
                    'bmi': round(bmi, 1),
                    'pain_score': pain,
                    'map_mmhg': map_mmhg,
                    'position': random.choice(['SITTING', 'STANDING', 'SUPINE']),
                    'measured_by_role': random.choice(['RN', 'MA', 'MD']),
                    '_loaded_at': datetime.now()
                })
                vital_id += 1

        return pd.DataFrame(vitals)

    def generate_clinical_orders(self, encounters_df):
        """Generate clinical orders for encounters"""
        print("\n📋 Generating clinical orders...")
        orders = []
        order_id = 1

        for _, encounter in tqdm(encounters_df.iterrows(), total=len(encounters_df), desc="Encounters"):
            num_orders = {
                'Emergency': random.randint(5, 15),
                'Inpatient': random.randint(10, 30),
                'Observation': random.randint(5, 12),
                'Outpatient': random.randint(1, 5)
            }.get(encounter['encounter_type'], 3)

            for i in range(num_orders):
                order_type = random.choices(
                    ['LAB', 'RADIOLOGY', 'MEDICATION', 'PROCEDURE'],
                    weights=[0.40, 0.20, 0.30, 0.10]
                )[0]

                order_time = encounter['admission_date'] + timedelta(
                    hours=random.uniform(0, min(24, encounter['length_of_stay'] * 24)))

                order = {
                    'order_id': f'ORD_{order_id:012d}',
                    'hospital_id': encounter['hospital_id'],
                    'encounter_id': encounter['encounter_id'],
                    'patient_id': encounter['patient_id'],
                    'provider_id': encounter['provider_id'],
                    'ordering_provider_id': encounter['provider_id'],
                    'order_type': order_type,
                    'order_datetime': order_time,
                    'priority': random.choices(['ROUTINE', 'URGENT', 'STAT'], weights=[0.70, 0.20, 0.10])[0],
                    'performing_location': 'Laboratory' if order_type == 'LAB' else 'Radiology',
                    '_loaded_at': datetime.now(),
                    'result_id': None,
                    '_source_file': 'synthetic_data'
                }

                # Type-specific fields
                if order_type == 'LAB':
                    test = random.choice(list(LAB_TESTS.items()))
                    order.update({
                        'order_code': test[0],
                        'order_description': test[1]['name'],
                        'specimen_type': random.choice(['Blood', 'Serum', 'Urine']),
                        'scheduled_datetime': order_time + timedelta(hours=1),
                        'completed_datetime': order_time + timedelta(hours=random.uniform(2, 6)),
                        'order_status': 'COMPLETED',
                        'collection_datetime': order_time + timedelta(minutes=30)
                    })
                elif order_type == 'MEDICATION':
                    med = random.choice(MEDICATIONS)
                    order.update({
                        'order_code': f'MED-{random.randint(1000, 9999)}',
                        'order_description': med['name'],
                        'medication_name': med['name'],
                        'dose': med['dose'],
                        'route': random.choice(med['routes']),
                        'frequency': med['frequency'],
                        'scheduled_datetime': order_time,
                        'completed_datetime': order_time + timedelta(minutes=30),
                        'order_status': 'COMPLETED',
                        'duration_days': random.randint(1, 14)
                    })
                else:
                    order.update({
                        'order_code': f'{order_type}-{random.randint(1000, 9999)}',
                        'order_description': f'{order_type} Study',
                        'scheduled_datetime': order_time + timedelta(hours=2),
                        'completed_datetime': order_time + timedelta(hours=4),
                        'order_status': random.choice(['COMPLETED', 'IN_PROGRESS'])
                    })

                orders.append(order)
                order_id += 1

        return pd.DataFrame(orders)

    def generate_clinical_results(self, orders_df):
        """Generate lab results from orders"""
        print("\n🔬 Generating clinical results...")
        results = []
        result_id = 1

        lab_orders = orders_df[orders_df['order_type'] == 'LAB']

        for _, order in tqdm(lab_orders.iterrows(), total=len(lab_orders), desc="Lab Orders"):
            if order['order_status'] == 'COMPLETED' and order['order_code'] in LAB_TESTS:
                test_info = LAB_TESTS[order['order_code']]
                mean = (test_info['range'][0] + test_info['range'][1]) / 2
                std = (test_info['range'][1] - test_info['range'][0]) / 4

                value = np.random.normal(mean, std)
                abnormal_flag = 'L' if value < test_info['range'][0] else 'H' if value > test_info['range'][1] else 'N'

                results.append({
                    'result_id': f'RES_{result_id:012d}',
                    'hospital_id': order['hospital_id'],
                    'order_id': order['order_id'],
                    'patient_id': order['patient_id'],
                    'encounter_id': order['encounter_id'],
                    'interpreting_provider_id': order['provider_id'],
                    'result_type': 'LAB',
                    'test_code': order['order_code'],
                    'test_name': test_info['name'],
                    'component_code': order['order_code'],
                    'component_name': test_info['name'],
                    'result_value': f"{value:.2f}",
                    'result_value_numeric': round(value, 2),
                    'result_units': test_info['units'],
                    'reference_range_low': test_info['range'][0],
                    'reference_range_high': test_info['range'][1],
                    'abnormal_flag': abnormal_flag,
                    'result_datetime': order['completed_datetime'],
                    'collected_datetime': order.get('collection_datetime', order['order_datetime']),
                    'resulted_datetime': order['completed_datetime'],
                    'result_status': 'FINAL',
                    'performing_lab': 'Main Laboratory',
                    'imaging_modality': None,
                    'impression': None,
                    'report_text': None,
                    '_loaded_at': datetime.now()
                })
                result_id += 1

        return pd.DataFrame(results)

    def generate_medication_administration(self, orders_df):
        """Generate medication administration records"""
        print("\n💊 Generating medication administration...")
        administrations = []
        admin_id = 1

        med_orders = orders_df[orders_df['order_type'] == 'MEDICATION']

        for _, order in tqdm(med_orders.iterrows(), total=len(med_orders), desc="Med Orders"):
            num_admin = random.randint(1, 10)

            for i in range(num_admin):
                scheduled_time = order['scheduled_datetime'] + timedelta(hours=i * 6)
                admin_time = scheduled_time + timedelta(minutes=random.randint(-30, 60))

                status = random.choices(
                    ['GIVEN', 'REFUSED', 'HELD', 'MISSED'],
                    weights=[0.85, 0.05, 0.05, 0.05]
                )[0]

                administrations.append({
                    'admin_id': f'ADM_{admin_id:012d}',
                    'hospital_id': order['hospital_id'],
                    'encounter_id': order['encounter_id'],
                    'patient_id': order['patient_id'],
                    'order_id': order['order_id'],
                    'medication_name': order.get('medication_name'),
                    'dose': order.get('dose'),
                    'route': order.get('route'),
                    'scheduled_datetime': scheduled_time,
                    'administered_datetime': admin_time if status == 'GIVEN' else None,
                    'administered_by_provider_id': order['provider_id'],
                    'witnessed_by_provider_id': f'PROV_{random.randint(1, 100):08d}' if random.random() < 0.80 else None,
                    'administration_status': status,
                    'refusal_reason': 'Patient declined' if status == 'REFUSED' else None,
                    'hold_reason': 'Clinical hold' if status == 'HELD' else None,
                    'barcode_scanned': random.random() < 0.90,
                    'adverse_reaction_flag': random.random() < 0.02,
                    'reaction_description': 'Mild rash' if random.random() < 0.02 else None,
                    '_loaded_at': datetime.now()
                })
                admin_id += 1

        return pd.DataFrame(administrations)

    def generate_patient_allergies(self, patients_df):
        """Generate patient allergies"""
        print("\n🚫 Generating patient allergies...")
        allergies = []
        allergy_id = 1

        for _, patient in tqdm(patients_df.iterrows(), total=len(patients_df), desc="Patients"):
            if random.random() < 0.40:
                num_allergies = random.choices([1, 2, 3], weights=[0.70, 0.25, 0.05])[0]

                for _ in range(num_allergies):
                    allergen = random.choice(COMMON_ALLERGENS)
                    severity = random.choice(allergen['severity'])
                    reaction = random.choice(allergen['reactions'])

                    allergies.append({
                        'allergy_id': f'ALG_{allergy_id:012d}',
                        'hospital_id': patient['hospital_id'],
                        'patient_id': patient['patient_id'],
                        'documented_by_provider_id': f'PROV_{random.randint(1, 100):08d}',
                        'allergen_type': 'DRUG' if allergen['name'] in ['Penicillin', 'Sulfa', 'Morphine'] else 'FOOD',
                        'allergen_code': f'ALLG-{allergy_id}',
                        'allergen_name': allergen['name'],
                        'reaction_type': reaction,
                        'severity': severity,
                        'allergy_status': 'ACTIVE',
                        'onset_date': datetime.now() - timedelta(days=random.randint(30, 3650)),
                        'resolution_date': None,
                        'documentation_date': datetime.now() - timedelta(days=random.randint(1, 365)),
                        'clinical_notes': f'Patient reports {reaction.lower()} with {allergen["name"]}',
                        '_loaded_at': datetime.now()
                    })
                    allergy_id += 1

        return pd.DataFrame(allergies)

    def generate_problem_list(self, patients_df):
        """Generate patient problem lists"""
        print("\n📝 Generating problem lists...")
        problems = []
        problem_id = 1

        for _, patient in tqdm(patients_df.iterrows(), total=len(patients_df), desc="Patients"):
            num_problems = random.choices([0, 1, 2, 3, 4, 5], weights=[0.20, 0.30, 0.25, 0.15, 0.07, 0.03])[0]

            for _ in range(num_problems):
                diagnosis = random.choice(CHRONIC_DIAGNOSES)

                problems.append({
                    'problem_id': f'PROB_{problem_id:012d}',
                    'hospital_id': patient['hospital_id'],
                    'patient_id': patient['patient_id'],
                    'documented_by_provider_id': f'PROV_{random.randint(1, 100):08d}',
                    'diagnosis_code': diagnosis[0],
                    'diagnosis_description': diagnosis[1],
                    'problem_status': random.choices(['ACTIVE', 'RESOLVED'], weights=[0.80, 0.20])[0],
                    'onset_date': datetime.now() - timedelta(days=random.randint(365, 3650)),
                    'resolution_date': None,
                    'last_reviewed_date': datetime.now() - timedelta(days=random.randint(0, 180)),
                    'severity': diagnosis[3],
                    'is_chronic': diagnosis[2],
                    'is_primary_diagnosis': random.random() < 0.3,
                    'documentation_date': datetime.now() - timedelta(days=random.randint(365, 3650)),
                    'clinical_notes': f'Active management of {diagnosis[1].lower()}',
                    '_loaded_at': datetime.now()
                })
                problem_id += 1

        return pd.DataFrame(problems)

    def generate_patient_coverage(self, patients_df, payers_df):
        """Generate patient insurance coverage"""
        print("\n🏥 Generating patient coverage...")
        coverage = []
        coverage_id = 1

        for _, patient in tqdm(patients_df.iterrows(), total=len(patients_df), desc="Patients"):
            num_coverages = random.choices([0, 1, 2], weights=[0.10, 0.75, 0.15])[0]

            for priority in range(1, num_coverages + 1):
                payer = payers_df.sample(1).iloc[0]

                coverage.append({
                    'coverage_id': f'COV_{coverage_id:012d}',
                    'hospital_id': patient['hospital_id'],
                    'patient_id': patient['patient_id'],
                    'payer_id': payer['payer_id'],
                    'policy_number': f'POL-{random.randint(100000, 999999)}',
                    'group_number': f'GRP-{random.randint(1000, 9999)}',
                    'subscriber_id': f'SUB-{random.randint(100000, 999999)}',
                    'subscriber_name': f"{fake.first_name()} {fake.last_name()}",
                    'subscriber_relationship': 'SELF' if random.random() < 0.7 else random.choice(
                        ['SPOUSE', 'CHILD', 'PARENT']),
                    'effective_date': datetime.now() - timedelta(days=random.randint(0, 730)),
                    'termination_date': None,
                    'coverage_status': 'ACTIVE',
                    'plan_type': random.choice(['HMO', 'PPO', 'EPO', 'POS']),
                    'coverage_level': random.choice(['Individual', 'Family']),
                    'deductible_amount': random.choice([500, 1000, 2500, 5000]),
                    'deductible_met_amount': random.uniform(0, 2000),
                    'out_of_pocket_max': random.choice([3000, 5000, 7500, 10000]),
                    'out_of_pocket_met': random.uniform(0, 3000),
                    'copay_amount': random.choice([20, 30, 40, 50]),
                    'coinsurance_pct': random.choice([0.10, 0.20, 0.30]),
                    'coverage_priority': priority,
                    '_loaded_at': datetime.now()
                })
                coverage_id += 1

        return pd.DataFrame(coverage)

    def generate_sdoh_screenings(self, patients_df):
        """Generate SDOH screenings"""
        print("\n🏘️ Generating SDOH screenings...")
        screenings = []
        screening_id = 1

        for _, patient in tqdm(patients_df.iterrows(), total=len(patients_df), desc="Patients"):
            if random.random() < 0.30:
                screenings.append({
                    'screening_id': f'SDOH_{screening_id:012d}',
                    'hospital_id': patient['hospital_id'],
                    'patient_id': patient['patient_id'],
                    'encounter_id': None,
                    'screening_date': datetime.now() - timedelta(days=random.randint(0, 365)),
                    'screening_tool_name': 'PRAPARE',
                    'housing_status': random.choice(['STABLE', 'UNSTABLE', 'HOMELESS']),
                    'housing_concerns': random.random() < 0.15,
                    'food_insecurity_flag': random.random() < 0.20,
                    'difficulty_affording_food': random.random() < 0.20,
                    'transportation_barriers': random.random() < 0.25,
                    'difficulty_paying_utilities': random.random() < 0.18,
                    'difficulty_affording_medications': random.random() < 0.15,
                    'social_isolation_score': random.randint(0, 10),
                    'safety_concerns': random.random() < 0.10,
                    'intimate_partner_violence_screen': random.random() < 0.05,
                    'employment_status': random.choice(['Employed Full-time', 'Unemployed', 'Retired', 'Disabled']),
                    'highest_education_level': random.choice(['High School', 'Some College', 'Bachelor', 'Graduate']),
                    'health_literacy_score': random.randint(0, 10),
                    'referrals_text': 'Social services referral provided' if random.random() < 0.20 else None,
                    '_loaded_at': datetime.now()
                })
                screening_id += 1

        return pd.DataFrame(screenings)

    def generate_hospitals(self) -> pd.DataFrame:
        """Generate hospital master data"""
        print("\n🏥 Generating hospitals...")

        hospitals = []
        hospital_id = 1

        for h_type, config in HOSPITAL_DISTRIBUTION.items():
            for _ in range(config['count']):
                state = fake.state_abbr()
                city = fake.city()

                emr = (random.choice(config['emr_system'])
                       if isinstance(config['emr_system'], list)
                       else config['emr_system'])

                hosp_id = f'HOSP_{hospital_id:04d}'
                hospitals.append({
                    'hospital_id': hosp_id,
                    'hospital_name': f"{city} {h_type.replace('_', ' ').title()}",
                    'hospital_type': h_type,
                    'bed_count': random.randint(*config['bed_count']),
                    'city': city,
                    'state': state,
                    'region': self.get_region(state),
                    'emr_system': emr,
                    'contract_tier': config['contract_tier'],
                    'contract_start_date': self.start_date - timedelta(days=random.randint(365, 730)),
                    'is_active': True,
                    'teaching_hospital': h_type == 'academic_medical_center'
                })

                # Initialize tracking
                self.hospital_patients[hosp_id] = []
                self.hospital_providers[hosp_id] = []
                self.hospital_facilities[hosp_id] = []

                hospital_id += 1

        df = pd.DataFrame(hospitals)
        print(f"✓ Generated {len(df)} hospitals")
        return df

    def generate_patients(self, hospitals_df: pd.DataFrame) -> pd.DataFrame:
        """Generate patients with proper hospital relationships"""
        print("\n👥 Generating patients...")

        patients = []
        patient_id = 1

        for _, hospital in tqdm(hospitals_df.iterrows(), total=len(hospitals_df), desc="Hospitals"):
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]
            num_patients = random.randint(*config['patients'])

            for _ in range(num_patients):
                gender = random.choice(['M', 'F', 'Other'])
                dob = fake.date_of_birth(minimum_age=0, maximum_age=95)

                pat_id = f'PAT_{patient_id:010d}'

                patients.append({
                    'patient_id': pat_id,
                    'hospital_id': hospital['hospital_id'],
                    'mrn': f"{hospital['hospital_id']}-{patient_id:08d}",
                    'ssn_hash': hashlib.sha256(f"SSN-{patient_id}".encode()).hexdigest()[:16],
                    'first_name': fake.first_name_male() if gender == 'M' else fake.first_name_female(),
                    'last_name': fake.last_name(),
                    'date_of_birth': dob,
                    'gender': gender,
                    'race': random.choice(['White', 'Black', 'Asian', 'Hispanic', 'Other', 'Unknown']),
                    'ethnicity': random.choice(['Hispanic or Latino', 'Not Hispanic or Latino', 'Unknown']),
                    'zip_code': fake.zipcode(),
                    'phone_number_hash': hashlib.sha256(fake.phone_number().encode()).hexdigest()[:16],
                    'email_hash': hashlib.sha256(fake.email().encode()).hexdigest()[:16],
                    'primary_language': random.choice(['English', 'Spanish', 'Chinese', 'Other']),
                    'marital_status': random.choice(['Single', 'Married', 'Divorced', 'Widowed']),
                    'first_encounter_date': hospital['contract_start_date'] + timedelta(days=random.randint(0, 365))
                })

                # Track patient-hospital relationship
                self.hospital_patients[hospital['hospital_id']].append(pat_id)
                self.patient_encounters[pat_id] = []

                patient_id += 1

        df = pd.DataFrame(patients)
        print(f"✓ Generated {len(df):,} patients")
        return df

    def generate_providers(self, hospitals_df: pd.DataFrame) -> pd.DataFrame:
        """Generate providers with proper hospital relationships"""
        print("\n🩺 Generating providers...")

        providers = []
        provider_id = 1

        for _, hospital in tqdm(hospitals_df.iterrows(), total=len(hospitals_df), desc="Hospitals"):
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]
            num_providers = random.randint(*config['providers'])

            available_specialties = SPECIALTIES[:config['specialties']]

            for _ in range(num_providers):
                hire_date = hospital['contract_start_date'] + timedelta(days=random.randint(-1000, 0))
                specialty = random.choice(available_specialties)

                prov_id = f'PROV_{provider_id:08d}'

                providers.append({
                    'provider_id': prov_id,
                    'hospital_id': hospital['hospital_id'],
                    'npi': f"{random.randint(1000000000, 9999999999)}",
                    'provider_first_name': fake.first_name(),
                    'provider_last_name': fake.last_name(),
                    'specialty': specialty,
                    'department': self._get_department(specialty),
                    'provider_type': random.choice(['MD', 'DO', 'NP', 'PA']),
                    'hire_date': hire_date,
                    'is_active': True,  # Keep all active for testing
                    'accepts_new_patients': random.choice([True, False])
                })

                # Track provider-hospital relationship
                self.hospital_providers[hospital['hospital_id']].append(prov_id)

                provider_id += 1

        df = pd.DataFrame(providers)
        print(f"✓ Generated {len(df):,} providers")
        return df

    @staticmethod
    def _get_department(specialty: str) -> str:
        """Map specialty to department"""
        dept_map = {
            'Emergency Medicine': 'Emergency Department',
            'Internal Medicine': 'Medicine',
            'Family Medicine': 'Primary Care',
            'Cardiology': 'Cardiology',
            'General Surgery': 'Surgery',
            'Orthopedic Surgery': 'Surgery',
            'Obstetrics': "Women's Health"
        }
        return dept_map.get(specialty, 'Medicine')

    def generate_facilities(self, hospitals_df: pd.DataFrame) -> pd.DataFrame:
        """Generate facilities with proper hospital relationships"""
        print("\n🏢 Generating facilities...")

        facilities = []
        facility_id = 1

        # Essential facility types every hospital needs
        essential_facilities = [
            'Emergency Department',
            'Medical-Surgical Unit',
            'Intensive Care Unit',
            'Operating Room',
            'Outpatient Clinic'
        ]

        for _, hospital in tqdm(hospitals_df.iterrows(), total=len(hospitals_df), desc="Hospitals"):
            for facility_type in essential_facilities:
                capacity = self._get_facility_capacity(facility_type, hospital['bed_count'])

                fac_id = f'FAC_{facility_id:08d}'

                facilities.append({
                    'facility_id': fac_id,
                    'hospital_id': hospital['hospital_id'],
                    'facility_name': f"{hospital['hospital_name']} - {facility_type}",
                    'facility_type': facility_type,
                    'bed_capacity': capacity,
                    'is_active': True,
                    'opened_date': hospital['contract_start_date']
                })

                # Track facility-hospital relationship
                self.hospital_facilities[hospital['hospital_id']].append(fac_id)

                facility_id += 1

        df = pd.DataFrame(facilities)
        print(f"✓ Generated {len(df):,} facilities")
        return df

    @staticmethod
    def _get_facility_capacity(facility_type: str, hospital_beds: int) -> int:
        """Calculate facility capacity"""
        ratios = {
            'Emergency Department': 0.05,
            'Intensive Care Unit': 0.10,
            'Medical-Surgical Unit': 0.50,
            'Operating Room': 0.03,
            'Outpatient Clinic': 0.05
        }
        ratio = ratios.get(facility_type, 0.10)
        return max(int(hospital_beds * ratio), 5)

    def generate_reference_tables(self) -> tuple:
        """Generate reference tables"""
        print("\n📚 Generating reference tables...")

        diagnoses = [{
            'diagnosis_code': code,
            'diagnosis_description': details['description'],
            'category': details['category'],
            'severity_level': details['severity'],
            'is_chronic': details['severity'] in ['High', 'Critical']
        } for code, details in ICD10_CODES.items()]

        procedures = [{
            'procedure_code': code,
            'procedure_description': details['description'],
            'category': details['category'],
            'typical_charge_min': details['typical_charge'][0],
            'typical_charge_max': details['typical_charge'][1]
        } for code, details in CPT_CODES.items()]

        payers_list = [{
            'payer_id': f'PAY_{i:04d}',
            'payer_name': payer['payer_name'],
            'payer_type': payer['payer_type'],
            'reimbursement_rate': payer['reimbursement_rate'],
            'is_active': True
        } for i, payer in enumerate(PAYERS, 1)]

        print(f"✓ Generated {len(diagnoses)} diagnoses")
        print(f"✓ Generated {len(procedures)} procedures")
        print(f"✓ Generated {len(payers_list)} payers")

        return (pd.DataFrame(diagnoses),
                pd.DataFrame(procedures),
                pd.DataFrame(payers_list))

    def generate_encounters(self, hospitals_df: pd.DataFrame,
                          patients_df: pd.DataFrame,
                          providers_df: pd.DataFrame,
                          facilities_df: pd.DataFrame) -> pd.DataFrame:
        """Generate encounters with FIXED relationships and validation"""
        print("\n🏥 Generating encounters with proper validation...")

        encounters = []
        encounter_id = 1
        diagnosis_codes = list(ICD10_CODES.keys())

        for _, hospital in tqdm(hospitals_df.iterrows(), total=len(hospitals_df), desc="Hospitals"):
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]

            # Get related data for this hospital
            hosp_patients = self.hospital_patients[hospital['hospital_id']]
            hosp_providers = self.hospital_providers[hospital['hospital_id']]
            hosp_facilities = self.hospital_facilities[hospital['hospital_id']]

            if not hosp_patients or not hosp_providers or not hosp_facilities:
                continue

            # Generate encounters per day
            date_range = pd.date_range(self.start_date, self.end_date, freq='D')

            for date in date_range:
                if date < hospital['contract_start_date']:
                    continue

                num_encounters = random.randint(*config['daily_encounters'])

                for _ in range(num_encounters):
                    # Select patient from THIS hospital only
                    patient_id = random.choice(hosp_patients)
                    provider_id = random.choice(hosp_providers)

                    # Encounter type
                    enc_type = random.choices(
                        ['Inpatient', 'Outpatient', 'Emergency', 'Observation'],
                        weights=[0.20, 0.50, 0.25, 0.05]
                    )[0]

                    # Get appropriate facility for encounter type
                    facility_id = self._get_facility_for_encounter(
                        enc_type, hosp_facilities, facilities_df
                    )

                    # Admission time
                    hour = random.randint(0, 23)
                    admission_dt = pd.Timestamp(date) + timedelta(hours=hour, minutes=random.randint(0, 59))

                    # LOS - FIXED validation
                    los = self._calculate_valid_los(enc_type)

                    # Discharge date - ensure it's AFTER admission
                    discharge_dt = admission_dt + timedelta(days=los, hours=random.randint(0, 23))

                    # Ensure discharge >= admission
                    if discharge_dt < admission_dt:
                        discharge_dt = admission_dt + timedelta(hours=1)

                    # Recalculate LOS
                    los = (discharge_dt - admission_dt).total_seconds() / 86400
                    los = round(los, 2)

                    # Diagnosis
                    diagnosis_code = random.choice(diagnosis_codes)

                    # Charges
                    total_charges = self._calculate_charges(enc_type, los)

                    # Check for readmission (30-day window)
                    is_readmission = self._check_readmission(
                        patient_id, admission_dt, enc_type
                    )

                    enc_id = f'ENC_{encounter_id:012d}'

                    encounter_data = {
                        'encounter_id': enc_id,
                        'hospital_id': hospital['hospital_id'],
                        'patient_id': patient_id,
                        'provider_id': provider_id,
                        'facility_id': facility_id,
                        'admission_date': admission_dt,
                        'discharge_date': discharge_dt,
                        'length_of_stay': los,
                        'encounter_type': enc_type,
                        'admission_source': random.choice(ADMISSION_TYPES),
                        'discharge_disposition': random.choice(DISCHARGE_DISPOSITIONS),
                        'primary_diagnosis_code': diagnosis_code,
                        'total_charges': total_charges,
                        'is_readmission': is_readmission,
                        '_source_updated_at': admission_dt
                    }

                    encounters.append(encounter_data)

                    # Track for readmission logic
                    self.patient_encounters[patient_id].append({
                        'encounter_id': enc_id,
                        'admission_date': admission_dt,
                        'discharge_date': discharge_dt,
                        'encounter_type': enc_type
                    })

                    encounter_id += 1

        df = pd.DataFrame(encounters)
        print(f"✓ Generated {len(df):,} encounters")

        # Validate data
        self._validate_encounters(df)

        return df

    def _get_facility_for_encounter(self, enc_type: str,
                                   hospital_facilities: List[str],
                                   facilities_df: pd.DataFrame) -> str:
        """Get appropriate facility for encounter type"""
        facility_map = {
            'Emergency': 'Emergency Department',
            'Inpatient': ['Medical-Surgical Unit', 'Intensive Care Unit'],
            'Outpatient': 'Outpatient Clinic',
            'Observation': ['Medical-Surgical Unit', 'Outpatient Clinic']
        }

        target_types = facility_map.get(enc_type, 'Medical-Surgical Unit')
        if isinstance(target_types, str):
            target_types = [target_types]

        # Filter facilities for this hospital and type
        valid_facilities = facilities_df[
            (facilities_df['facility_id'].isin(hospital_facilities)) &
            (facilities_df['facility_type'].isin(target_types))
        ]['facility_id'].tolist()

        if valid_facilities:
            return random.choice(valid_facilities)
        else:
            # Fallback to any facility from this hospital
            return random.choice(hospital_facilities)

    def _calculate_valid_los(self, encounter_type: str) -> int:
        """Calculate valid LOS based on encounter type"""
        if encounter_type == 'Inpatient':
            # Inpatient: 1-365 days
            return max(1, min(365, int(np.random.lognormal(1.2, 0.8))))
        elif encounter_type == 'Observation':
            # Observation: 0-2 days
            return random.choice([0, 1, 2])
        elif encounter_type == 'Emergency':
            # Emergency: typically 0 days (same day)
            return random.choice([0, 0, 0, 1])  # Mostly 0, occasionally 1
        else:  # Outpatient
            # Outpatient: 0 days (same day)
            return 0

    def _calculate_charges(self, enc_type: str, los: float) -> float:
        """Calculate charges based on encounter type and LOS"""
        if enc_type == 'Inpatient':
            base = random.uniform(2000, 5000)
            return round(base * max(los, 1), 2)
        elif enc_type == 'Emergency':
            return round(random.uniform(500, 3000), 2)
        elif enc_type == 'Observation':
            return round(random.uniform(1000, 2500), 2)
        else:  # Outpatient
            return round(random.uniform(100, 800), 2)

    def _check_readmission(self, patient_id: str,
                          admission_dt: pd.Timestamp,
                          enc_type: str) -> bool:
        """Check if this is a 30-day readmission"""
        if enc_type != 'Inpatient':
            return False

        prior_encounters = self.patient_encounters.get(patient_id, [])

        for prior in prior_encounters:
            # Must be prior inpatient encounter
            if prior['encounter_type'] != 'Inpatient':
                continue

            # Check if within 30 days of prior discharge
            days_since = (admission_dt - prior['discharge_date']).days
            if 1 <= days_since <= 30:
                return True

        return False

    def _validate_encounters(self, df: pd.DataFrame):
        """Validate encounter data quality"""
        print("\n📊 Validating encounter data...")

        # Check discharge >= admission
        invalid_dates = df[df['discharge_date'] < df['admission_date']]
        if len(invalid_dates) > 0:
            print(f"⚠ WARNING: {len(invalid_dates)} encounters with discharge before admission")

        # Check LOS by type
        for enc_type in ['Inpatient', 'Outpatient', 'Emergency', 'Observation']:
            subset = df[df['encounter_type'] == enc_type]
            if len(subset) == 0:
                continue

            if enc_type == 'Inpatient':
                invalid = subset[(subset['length_of_stay'] < 1) | (subset['length_of_stay'] > 365)]
            elif enc_type in ['Outpatient', 'Emergency']:
                invalid = subset[subset['length_of_stay'] > 1]
            elif enc_type == 'Observation':
                invalid = subset[subset['length_of_stay'] > 2]

            if len(invalid) > 0:
                print(f"⚠ WARNING: {len(invalid)} {enc_type} encounters with invalid LOS")

        # Check readmissions
        readmissions = df[df['is_readmission'] == True]
        print(f"✓ {len(readmissions)} readmissions ({len(readmissions)/len(df)*100:.1f}%)")

        print("✓ Validation complete")

    def generate_billing_transactions(self, encounters_df: pd.DataFrame,
                                     payers_df: pd.DataFrame) -> pd.DataFrame:
        """Generate billing with proper relationships"""
        print("\n💰 Generating billing transactions...")

        transactions = []
        transaction_id = 1

        for _, encounter in tqdm(encounters_df.iterrows(), total=len(encounters_df), desc="Encounters"):
            payer = payers_df.sample(1).iloc[0]
            charge = encounter['total_charges']
            payment = round(charge * payer['reimbursement_rate'], 2)
            adjustment = round(charge - payment, 2)

            status = random.choices(
                ['Paid', 'Partial', 'Denied', 'Pending'],
                weights=[0.40, 0.05, 0.10, 0.45]
            )[0]

            denial_reason = None
            if status == 'Denied':
                denial_reason = random.choice(DENIAL_REASONS)
                payment = 0

            # Transaction date after discharge
            discharge_date = pd.to_datetime(encounter['discharge_date'])
            txn_date = discharge_date + timedelta(days=random.randint(1, 45))

            transactions.append({
                'transaction_id': f'TXN_{transaction_id:012d}',
                'hospital_id': encounter['hospital_id'],
                'encounter_id': encounter['encounter_id'],
                'patient_id': encounter['patient_id'],
                'payer_id': payer['payer_id'],
                'transaction_date': txn_date,
                'charge_amount': charge,
                'payment_amount': payment if status in ['Paid', 'Partial'] else 0,
                'adjustment_amount': adjustment,
                'denial_reason': denial_reason,
                'payment_status': status
            })
            transaction_id += 1

        df = pd.DataFrame(transactions)
        print(f"✓ Generated {len(df):,} billing transactions")
        return df

        @staticmethod
        def save_to_csv(df: pd.DataFrame, filename: str, output_dir: str = 'data_generation/2025'):
            """Save DataFrame to CSV"""
            os.makedirs(output_dir, exist_ok=True)
            filepath = os.path.join(output_dir, filename)

            print(f"  Saving {filename}...", end=" ")
            df.to_csv(filepath, index=False)

            size_mb = os.path.getsize(filepath) / (1024 * 1024)
            print(f"✓ ({len(df):,} rows, {size_mb:.2f} MB)")

    # Add the main() function with all data generation steps
def main():
    generator = HealthcareDataGenerator(
        start_date='2025-01-01',
        end_date='2025-01-31'
    )

    # Generate master data
    hospitals = generator.generate_hospitals()
    generator.save_to_csv(hospitals, 'hospitals.csv')

    patients = generator.generate_patients(hospitals)
    generator.save_to_csv(patients, 'patients.csv')

    providers = generator.generate_providers(hospitals)
    generator.save_to_csv(providers, 'providers.csv')

    facilities = generator.generate_facilities(hospitals)
    generator.save_to_csv(facilities, 'facilities.csv')

    diagnoses, procedures, payers = generator.generate_reference_tables()
    generator.save_to_csv(diagnoses, 'diagnoses.csv')
    generator.save_to_csv(procedures, 'procedures.csv')
    generator.save_to_csv(payers, 'payers.csv')

    # Generate encounters
    encounters = generator.generate_encounters(hospitals, patients, providers, facilities)
    generator.save_to_csv(encounters, 'encounters.csv')

    # Generate billing
    billing = generator.generate_billing_transactions(encounters, payers)
    generator.save_to_csv(billing, 'billing_transactions.csv')

    # Vital signs
    vitals = generator.generate_vital_signs(encounters)
    generator.save_to_csv(vitals, 'vital_signs.csv')

    # Clinical orders
    orders = generator.generate_clinical_orders(encounters)
    generator.save_to_csv(orders, 'clinical_orders.csv')

    # Lab results
    results = generator.generate_clinical_results(orders)
    generator.save_to_csv(results, 'clinical_results.csv')

    # Medication administration
    med_admin = generator.generate_medication_administration(orders)
    generator.save_to_csv(med_admin, 'medication_administration.csv')

    # Patient allergies
    allergies = generator.generate_patient_allergies(patients)
    generator.save_to_csv(allergies, 'patient_allergies.csv')

    # Problem list
    problems = generator.generate_problem_list(patients)
    generator.save_to_csv(problems, 'problem_list.csv')

    # Patient coverage
    coverage = generator.generate_patient_coverage(patients, payers)
    generator.save_to_csv(coverage, 'patient_coverage.csv')

    # SDOH screenings
    sdoh = generator.generate_sdoh_screenings(patients)
    generator.save_to_csv(sdoh, 'sdoh_screenings.csv')

    print("\n" + "=" * 70)
    print("✓ GENERATION COMPLETE - ALL FILES!")
    print("=" * 70)
    print(f"Hospitals:              {len(hospitals):,}")
    print(f"Patients:               {len(patients):,}")
    print(f"Providers:              {len(providers):,}")
    print(f"Facilities:             {len(facilities):,}")
    print(f"Encounters:             {len(encounters):,}")
    print(f"Billing:                {len(billing):,}")
    print(f"Vital Signs:            {len(vitals):,}")
    print(f"Clinical Orders:        {len(orders):,}")
    print(f"Lab Results:            {len(results):,}")
    print(f"Medication Admin:       {len(med_admin):,}")
    print(f"Allergies:              {len(allergies):,}")
    print(f"Problem List:           {len(problems):,}")
    print(f"Patient Coverage:       {len(coverage):,}")
    print(f"SDOH Screenings:        {len(sdoh):,}")
    print("\n⚠️  All PHI is synthetic - HIPAA-safe for demonstration")
    print("=" * 70)

if __name__ == "__main__":
    main()