"""
IsoMetrics Healthcare Data Generator - FIXED VERSION
Fixes:
1. Proper patient-hospital relationship tracking
2. Correct encounter-patient-provider-facility relationships
3. Proper readmission logic
4. Correct LOS validation
5. Proper date handling
6. Fixed billing transaction relationships
"""

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

# Import configurations from existing code
from medical_codes_library import (
    HOSPITAL_DISTRIBUTION, ICD10_CODES, CPT_CODES, SPECIALTIES,
    FACILITY_TYPES, PAYERS, ADMISSION_TYPES, DISCHARGE_DISPOSITIONS,
    DENIAL_REASONS, ADJUSTMENT_REASONS, CLAIM_STATUS, US_REGIONS,
)

BATCH_SIZE = 50000

class HealthcareDataGenerator:
    """Fixed healthcare data generator with proper relationships"""

    def __init__(self, start_date='2025-01-01', end_date='2025-01-31'):
        self.start_date = pd.to_datetime(start_date)
        self.end_date = pd.to_datetime(end_date)
        self.days = (self.end_date - self.start_date).days + 1

        # Track relationships for data integrity
        self.hospital_patients = {}  # {hospital_id: [patient_ids]}
        self.hospital_providers = {}  # {hospital_id: [provider_ids]}
        self.hospital_facilities = {}  # {hospital_id: [facility_ids]}
        self.patient_encounters = {}  # {patient_id: [encounter_data]}

        print("=" * 70)
        print("IsoMetrics Healthcare Data Generator - FIXED VERSION")
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


def main():
    # Initialize
    generator = HealthcareDataGenerator(
        start_date='2025-01-01',
        end_date='2025-12-31'
    )

    # Generate data in correct order
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

    encounters = generator.generate_encounters(hospitals, patients, providers, facilities)
    generator.save_to_csv(encounters, 'encounters.csv')

    billing = generator.generate_billing_transactions(encounters, payers)
    generator.save_to_csv(billing, 'billing_transactions.csv')

    print("\n" + "=" * 70)
    print("✓ GENERATION COMPLETE!")
    print("=" * 70)
    print(f"Hospitals:    {len(hospitals):,}")
    print(f"Patients:     {len(patients):,}")
    print(f"Providers:    {len(providers):,}")
    print(f"Facilities:   {len(facilities):,}")
    print(f"Diagnoses:    {len(diagnoses):,}")
    print(f"Procedures:   {len(procedures):,}")
    print(f"Payers:       {len(payers):,}")
    print(f"Encounters:   {len(encounters):,}")
    print(f"Billing:      {len(billing):,}")
    print("\n⚠️  All PHI is synthetic - HIPAA-safe for demonstration")
    print("=" * 70)


if __name__ == "__main__":
    main()