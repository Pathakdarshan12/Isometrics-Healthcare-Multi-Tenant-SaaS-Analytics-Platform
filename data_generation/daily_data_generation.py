"""
Lightweight Daily Healthcare Data Generator
Generates data for a single day and saves as Parquet files
"""

import pandas as pd
import numpy as np
from faker import Faker
from datetime import datetime, timedelta
import random
import os
import hashlib
import argparse

# Reproducible results
np.random.seed(42)
Faker.seed(42)
fake = Faker()

class DailyHealthcareDataGenerator:
    """Generates healthcare data for a single day"""

    def __init__(self, target_date: str):
        self.target_date = pd.to_datetime(target_date)
        self.output_dir = 'data_generation/parquet'
        os.makedirs(self.output_dir, exist_ok=True)

        print(f"🗓️  Loading data: ")

        # Initialize all reference data attributes
        self.hospitals = pd.DataFrame()
        self.providers = pd.DataFrame()
        self.facilities = pd.DataFrame()
        self.diagnoses = pd.DataFrame()
        self.payers = pd.DataFrame()

        hosp_file = os.path.join(self.output_dir, 'hospitals.parquet')
        if os.path.exists(hosp_file):
            self.hospitals = pd.read_parquet(hosp_file)
            print(f"  ✓ Loaded {len(self.hospitals)} hospitals")

        prov_file = os.path.join(self.output_dir, 'providers.parquet')
        if os.path.exists(prov_file):
            self.providers = pd.read_parquet(prov_file)
            print(f"  ✓ Loaded {len(self.providers)} providers")

        fac_file = os.path.join(self.output_dir, 'facilities.parquet')
        if os.path.exists(fac_file):
            self.facilities = pd.read_parquet(fac_file)
            print(f"  ✓ Loaded {len(self.facilities)} facilities")

        diag_file = os.path.join(self.output_dir, 'diagnoses.parquet')
        if os.path.exists(diag_file):
            self.diagnoses = pd.read_parquet(diag_file)
            print(f"  ✓ Loaded {len(self.diagnoses)} diagnoses")

        payer_file = os.path.join(self.output_dir, 'payers.parquet')
        if os.path.exists(payer_file):
            self.payers = pd.read_parquet(payer_file)
            print(f"  ✓ Loaded {len(self.payers)} payers")

        # Validate required reference data exists
        if self.hospitals.empty or self.providers.empty or self.facilities.empty or \
           self.diagnoses.empty or self.payers.empty:
            raise ValueError("Missing required reference data. Please ensure all reference tables exist.")

    def generate_daily_encounters(self):
        """Generate encounters for the target date"""
        encounters = []
        encounter_id = self._get_next_encounter_id()

        for _, hospital in self.hospitals.iterrows():
            # Calculate number of encounters for this hospital today
            num_encounters = random.randint(
                5,                  # minimum
                hospital['bed_count']  # max
            )

            # Get providers for this hospital
            hosp_providers = self.providers[
                self.providers['hospital_id'] == hospital['hospital_id']
            ]

            # Get facilities for this hospital
            hosp_facilities = self.facilities[
                self.facilities['hospital_id'] == hospital['hospital_id']
            ]

            if len(hosp_providers) == 0 or len(hosp_facilities) == 0:
                continue

            for _ in range(num_encounters):
                # Random encounter type
                enc_type = random.choices(
                    ['Inpatient', 'Outpatient', 'Emergency', 'Observation'],
                    weights=[0.20, 0.50, 0.25, 0.05]
                )[0]

                # Random time today
                hour = random.randint(0, 23)
                minute = random.randint(0, 59)
                admission_dt = self.target_date + timedelta(hours=hour, minutes=minute)

                # Length of stay
                if enc_type == 'Inpatient':
                    los = max(1, int(np.random.lognormal(1.2, 0.8)))
                elif enc_type == 'Observation':
                    los = random.choice([0, 1])
                else:
                    los = 0

                discharge_dt = admission_dt + timedelta(days=los, hours=random.randint(0, 23))

                # Random provider and facility
                provider = hosp_providers.sample(1).iloc[0]
                facility = hosp_facilities.sample(1).iloc[0]
                diagnosis = self.diagnoses.sample(1).iloc[0]

                # Charges
                if enc_type == 'Inpatient':
                    charges = round(random.uniform(2000, 5000) * max(los, 1), 2)
                elif enc_type == 'Emergency':
                    charges = round(random.uniform(500, 3000), 2)
                elif enc_type == 'Observation':
                    charges = round(random.uniform(1000, 2500), 2)
                else:
                    charges = round(random.uniform(100, 800), 2)

                encounters.append({
                    'encounter_id': f'ENC_{encounter_id:012d}',
                    'hospital_id': hospital['hospital_id'],
                    'patient_id': f'PAT_{random.randint(1, 100000):010d}',
                    'provider_id': provider['provider_id'],
                    'facility_id': facility['facility_id'],
                    'admission_date': admission_dt,
                    'discharge_date': discharge_dt,
                    'length_of_stay': los,
                    'encounter_type': enc_type,
                    'admission_source': random.choice(['Emergency', 'Elective', 'Transfer']),
                    'discharge_disposition': random.choice(['Home', 'SNF', 'Rehab', 'Deceased']),
                    'primary_diagnosis_code': diagnosis['diagnosis_code'],
                    'total_charges': charges,
                    'is_readmission': random.random() < 0.05,
                    '_source_updated_at': self.target_date
                })
                encounter_id += 1

        return pd.DataFrame(encounters)

    def _get_next_encounter_id(self):
        """Get next encounter ID from existing data"""
        enc_pattern = os.path.join(self.output_dir, 'encounters_*.parquet')
        import glob
        existing_files = glob.glob(enc_pattern)

        if not existing_files:
            return 1

        max_id = 0
        for file in existing_files:
            df = pd.read_parquet(file)
            if len(df) > 0:
                ids = df['encounter_id'].str.extract(r'ENC_(\d+)')[0].astype(int)
                if not ids.empty:
                    max_id = max(max_id, ids.max())

        return max_id + 1

    def _get_next_transaction_id(self):
        """Get next transaction ID from existing data"""
        txn_pattern = os.path.join(self.output_dir, 'billing_transactions_*.parquet')
        import glob
        existing_files = glob.glob(txn_pattern)

        if not existing_files:
            return 1

        max_id = 0
        for file in existing_files:
            df = pd.read_parquet(file)
            if len(df) > 0:
                ids = df['transaction_id'].str.extract(r'TXN_(\d+)')[0].astype(int)
                if not ids.empty:
                    max_id = max(max_id, ids.max())

        return max_id + 1

    def generate_daily_billing(self, encounters_df):
        """Generate billing transactions for today's encounters"""
        if len(encounters_df) == 0:
            return pd.DataFrame()

        transactions = []
        transaction_id = self._get_next_transaction_id()

        for _, encounter in encounters_df.iterrows():
            # Generate 1-3 transactions per encounter
            num_txns = random.randint(1, 3)

            for _ in range(num_txns):
                payer = self.payers.sample(1).iloc[0]
                charge = encounter['total_charges'] / num_txns
                payment = round(charge * payer['reimbursement_rate'], 2)
                adjustment = round(charge - payment, 2)

                status = random.choices(
                    ['Paid', 'Pending', 'Denied'],
                    weights=[0.70, 0.20, 0.10]
                )[0]

                # Transaction date is 1-45 days after discharge
                txn_date = encounter['discharge_date'] + timedelta(days=random.randint(1, 45))

                transactions.append({
                    'transaction_id': f'TXN_{transaction_id:012d}',
                    'hospital_id': encounter['hospital_id'],
                    'encounter_id': encounter['encounter_id'],
                    'patient_id': encounter['patient_id'],
                    'payer_id': payer['payer_id'],
                    'transaction_date': txn_date,
                    'charge_amount': round(charge, 2),
                    'payment_amount': payment if status == 'Paid' else 0,
                    'adjustment_amount': adjustment,
                    'denial_reason': 'Prior authorization required' if status == 'Denied' else None,
                    'payment_status': status
                })
                transaction_id += 1

        return pd.DataFrame(transactions)

    def generate_and_save(self):
        """Generate all daily data and save to parquet files"""
        date_str = self.target_date.strftime('%Y-%m-%d')
        date_folder = os.path.join(self.output_dir, date_str)
        os.makedirs(date_folder, exist_ok=True)

        print(f"\n📊 Generating encounters...")
        encounters = self.generate_daily_encounters()
        enc_file = os.path.join(date_folder, f'encounters_{date_str}.parquet')
        encounters.to_parquet(enc_file, index=False)
        print(f"✓ Generated {len(encounters):,} encounters → {enc_file}")

        print(f"\n💰 Generating billing transactions...")
        billing = self.generate_daily_billing(encounters)
        bill_file = os.path.join(date_folder, f'billing_transactions_{date_str}.parquet')
        billing.to_parquet(bill_file, index=False)
        print(f"✓ Generated {len(billing):,} billing transactions → {bill_file}")

        return {
            'date': date_str,
            'encounters': len(encounters),
            'billing': len(billing),
            'encounters_file': enc_file,
            'billing_file': bill_file
        }


def main():
    parser = argparse.ArgumentParser(description='Generate daily healthcare data')
    parser.add_argument(
        '--date',
        type=str,
        default=(datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d'),
        help='Target date (YYYY-MM-DD), defaults to yesterday'
    )
    parser.add_argument(
        '--output-dir',
        type=str,
        default='/opt/airflow/data/staging',
        help='Output directory for parquet files'
    )

    args = parser.parse_args()

    print("=" * 70)
    print("🏥 Daily Healthcare Data Generator")
    print("=" * 70)

    try:
        generator = DailyHealthcareDataGenerator(
            target_date=args.date
        )

        result = generator.generate_and_save()

        print("\n" + "=" * 70)
        print("✓ Generation Complete!")
        print(f"  Date: {result['date']}")
        print(f"  Encounters: {result['encounters']:,}")
        print(f"  Billing Transactions: {result['billing']:,}")
        print("=" * 70)
    except Exception as e:
        print(f"\n❌ Error: {str(e)}")
        raise


if __name__ == "__main__":
    main()