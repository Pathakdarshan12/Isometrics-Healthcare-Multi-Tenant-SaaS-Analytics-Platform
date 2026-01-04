"""
IsoMetrics Healthcare Data Generator - OPTIMIZED VERSION
Generates realistic multi-tenant healthcare data with HIPAA compliance considerations

Key Optimizations:
- Batch processing to reduce memory overhead
- Generator functions instead of loading all data in memory
- Efficient date generation
- Optimized data structures
- Progress tracking with tqdm
"""

import pandas as pd
import numpy as np
from faker import Faker
from datetime import timedelta
import random
import os
import hashlib
from tqdm import tqdm
from typing import Generator, Dict
import gc

# Reproducible results
np.random.seed(42)
Faker.seed(42)
fake = Faker()

# ============================================
# HOSPITAL DISTRIBUTION (Tenant Configuration)
# ============================================

HOSPITAL_DISTRIBUTION = {
    'academic_medical_center': {
        'count': 10,
        'bed_count': (500, 1000),
        'daily_encounters': (200, 500),
        'patients': (10000, 50000),
        'providers': (200, 500),
        'specialties': 15,
        'contract_tier': 'Enterprise',
        'emr_system': 'Epic'
    },
    'community_hospital': {
        'count': 60,
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

# Comprehensive ICD-10 diagnosis codes
ICD10_CODES = {
    # Cardiovascular
    'I10': {'description': 'Essential (primary) hypertension', 'category': 'Cardiovascular', 'severity': 'Moderate'},
    'I50.9': {'description': 'Heart failure, unspecified', 'category': 'Cardiovascular', 'severity': 'High'},
    'I21.9': {'description': 'Acute myocardial infarction, unspecified', 'category': 'Cardiovascular','severity': 'Critical'},
    'I63.9': {'description': 'Cerebral infarction, unspecified', 'category': 'Neurological', 'severity': 'Critical'},
    'I48.91': {'description': 'Atrial fibrillation, unspecified', 'category': 'Cardiovascular', 'severity': 'High'},
    'I25.10': {'description': 'Atherosclerotic heart disease without angina', 'category': 'Cardiovascular','severity': 'High'},
    'I73.9': {'description': 'Peripheral vascular disease, unspecified', 'category': 'Cardiovascular','severity': 'Moderate'},
    'I11.9': {'description': 'Hypertensive heart disease without heart failure', 'category': 'Cardiovascular','severity': 'Moderate'},

    # Endocrine/Metabolic
    'E11.9': {'description': 'Type 2 diabetes mellitus without complications', 'category': 'Endocrine','severity': 'Moderate'},
    'E11.65': {'description': 'Type 2 diabetes with hyperglycemia', 'category': 'Endocrine', 'severity': 'High'},
    'E10.9': {'description': 'Type 1 diabetes mellitus without complications', 'category': 'Endocrine','severity': 'Moderate'},
    'E78.5': {'description': 'Hyperlipidemia, unspecified', 'category': 'Endocrine', 'severity': 'Moderate'},
    'E66.9': {'description': 'Obesity, unspecified', 'category': 'Endocrine', 'severity': 'Moderate'},
    'E03.9': {'description': 'Hypothyroidism, unspecified', 'category': 'Endocrine', 'severity': 'Low'},
    'E05.90': {'description': 'Hyperthyroidism, unspecified', 'category': 'Endocrine', 'severity': 'Moderate'},

    # Respiratory
    'J44.9': {'description': 'COPD, unspecified', 'category': 'Respiratory', 'severity': 'High'},
    'J18.9': {'description': 'Pneumonia, unspecified organism', 'category': 'Respiratory', 'severity': 'High'},
    'J45.909': {'description': 'Asthma, unspecified, uncomplicated', 'category': 'Respiratory', 'severity': 'Moderate'},
    'J06.9': {'description': 'Acute upper respiratory infection, unspecified', 'category': 'Respiratory','severity': 'Low'},
    'J20.9': {'description': 'Acute bronchitis, unspecified', 'category': 'Respiratory', 'severity': 'Low'},
    'J96.90': {'description': 'Respiratory failure, unspecified', 'category': 'Respiratory', 'severity': 'Critical'},
    'J90': {'description': 'Pleural effusion', 'category': 'Respiratory', 'severity': 'High'},

    # Renal/Genitourinary
    'N18.9': {'description': 'Chronic kidney disease, unspecified', 'category': 'Renal', 'severity': 'High'},
    'N17.9': {'description': 'Acute kidney failure, unspecified', 'category': 'Renal', 'severity': 'Critical'},
    'N39.0': {'description': 'Urinary tract infection, site not specified', 'category': 'Renal','severity': 'Moderate'},
    'N18.3': {'description': 'Chronic kidney disease, stage 3', 'category': 'Renal', 'severity': 'High'},
    'N20.0': {'description': 'Calculus of kidney', 'category': 'Renal', 'severity': 'Moderate'},

    # Digestive/Gastrointestinal
    'K92.2': {'description': 'Gastrointestinal hemorrhage, unspecified', 'category': 'Digestive', 'severity': 'High'},
    'K21.9': {'description': 'Gastroesophageal reflux disease without esophagitis', 'category': 'Digestive','severity': 'Low'},
    'K80.20': {'description': 'Calculus of gallbladder without cholecystitis', 'category': 'Digestive','severity': 'Moderate'},
    'K29.70': {'description': 'Gastritis, unspecified', 'category': 'Digestive', 'severity': 'Low'},
    'K57.90': {'description': 'Diverticulosis of intestine', 'category': 'Digestive', 'severity': 'Moderate'},
    'K52.9': {'description': 'Noninfective gastroenteritis and colitis', 'category': 'Digestive', 'severity': 'Low'},
    'K50.90': {'description': "Crohn's disease, unspecified", 'category': 'Digestive', 'severity': 'Moderate'},
    'K51.90': {'description': 'Ulcerative colitis, unspecified', 'category': 'Digestive', 'severity': 'Moderate'},

    # Mental Health
    'F32.9': {'description': 'Major depressive disorder, single episode', 'category': 'Mental Health','severity': 'Moderate'},
    'F41.9': {'description': 'Anxiety disorder, unspecified', 'category': 'Mental Health', 'severity': 'Moderate'},
    'F10.20': {'description': 'Alcohol dependence, uncomplicated', 'category': 'Mental Health', 'severity': 'High'},
    'F33.9': {'description': 'Major depressive disorder, recurrent', 'category': 'Mental Health', 'severity': 'High'},
    'F31.9': {'description': 'Bipolar disorder, unspecified', 'category': 'Mental Health', 'severity': 'High'},
    'F43.10': {'description': 'Post-traumatic stress disorder', 'category': 'Mental Health', 'severity': 'Moderate'},
    'F20.9': {'description': 'Schizophrenia, unspecified', 'category': 'Mental Health', 'severity': 'High'},

    # Musculoskeletal
    'M17.9': {'description': 'Osteoarthritis of knee, unspecified', 'category': 'Musculoskeletal','severity': 'Moderate'},
    'M54.5': {'description': 'Low back pain', 'category': 'Musculoskeletal', 'severity': 'Low'},
    'M19.90': {'description': 'Osteoarthritis, unspecified site', 'category': 'Musculoskeletal','severity': 'Moderate'},
    'M81.0': {'description': 'Osteoporosis without current pathological fracture', 'category': 'Musculoskeletal','severity': 'Moderate'},
    'M79.3': {'description': 'Panniculitis, unspecified', 'category': 'Musculoskeletal', 'severity': 'Low'},
    'M25.561': {'description': 'Pain in right knee', 'category': 'Musculoskeletal', 'severity': 'Low'},

    # Injury/Trauma
    'S72.001A': {'description': 'Fracture of unspecified part of neck of right femur', 'category': 'Injury','severity': 'High'},
    'S06.9X0A': {'description': 'Unspecified intracranial injury', 'category': 'Injury', 'severity': 'Critical'},
    'S82.001A': {'description': 'Fracture of right patella', 'category': 'Injury', 'severity': 'High'},
    'T14.90XA': {'description': 'Injury, unspecified', 'category': 'Injury', 'severity': 'Moderate'},
    'S42.001A': {'description': 'Fracture of right clavicle', 'category': 'Injury', 'severity': 'Moderate'},

    # Infectious Diseases
    'A41.9': {'description': 'Sepsis, unspecified organism', 'category': 'Infectious', 'severity': 'Critical'},
    'B34.9': {'description': 'Viral infection, unspecified', 'category': 'Infectious', 'severity': 'Low'},
    'A09': {'description': 'Infectious gastroenteritis and colitis', 'category': 'Infectious', 'severity': 'Moderate'},
    'U07.1': {'description': 'COVID-19', 'category': 'Infectious', 'severity': 'High'},
    'B37.9': {'description': 'Candidiasis, unspecified', 'category': 'Infectious', 'severity': 'Low'},

    # Neurological
    'G40.909': {'description': 'Epilepsy, unspecified', 'category': 'Neurological', 'severity': 'High'},
    'G43.909': {'description': 'Migraine, unspecified', 'category': 'Neurological', 'severity': 'Moderate'},
    'G20': {'description': "Parkinson's disease", 'category': 'Neurological', 'severity': 'High'},
    'G30.9': {'description': "Alzheimer's disease, unspecified", 'category': 'Neurological', 'severity': 'High'},
    'G35': {'description': 'Multiple sclerosis', 'category': 'Neurological', 'severity': 'High'},
    'G47.33': {'description': 'Obstructive sleep apnea', 'category': 'Neurological', 'severity': 'Moderate'},

    # Oncology
    'C50.919': {'description': 'Malignant neoplasm of breast', 'category': 'Oncology', 'severity': 'Critical'},
    'C34.90': {'description': 'Malignant neoplasm of lung', 'category': 'Oncology', 'severity': 'Critical'},
    'C61': {'description': 'Malignant neoplasm of prostate', 'category': 'Oncology', 'severity': 'Critical'},
    'C18.9': {'description': 'Malignant neoplasm of colon', 'category': 'Oncology', 'severity': 'Critical'},
    'D64.9': {'description': 'Anemia, unspecified', 'category': 'Hematology', 'severity': 'Moderate'},

    # Obstetric
    'O80': {'description': 'Encounter for full-term uncomplicated delivery', 'category': 'Obstetric','severity': 'Moderate'},
    'O09.90': {'description': 'Supervision of high risk pregnancy', 'category': 'Obstetric', 'severity': 'High'},
    'O26.90': {'description': 'Pregnancy complication, unspecified', 'category': 'Obstetric', 'severity': 'Moderate'},

    # Preventive/Screening
    'Z00.00': {'description': 'Encounter for general adult medical examination', 'category': 'Wellness','severity': 'Low'},
    'Z12.11': {'description': 'Encounter for screening for malignant neoplasm of colon', 'category': 'Prevention','severity': 'Low'},
    'Z23': {'description': 'Encounter for immunization', 'category': 'Prevention', 'severity': 'Low'},
    'Z13.89': {'description': 'Encounter for screening for other disorder', 'category': 'Prevention','severity': 'Low'},
    'Z01.419': {'description': 'Encounter for gynecological examination', 'category': 'Prevention', 'severity': 'Low'},

    # Dermatology
    'L50.9': {'description': 'Urticaria, unspecified', 'category': 'Dermatology', 'severity': 'Low'},
    'L20.9': {'description': 'Atopic dermatitis, unspecified', 'category': 'Dermatology', 'severity': 'Low'},
    'L30.9': {'description': 'Dermatitis, unspecified', 'category': 'Dermatology', 'severity': 'Low'},
    'L03.90': {'description': 'Cellulitis, unspecified', 'category': 'Dermatology', 'severity': 'Moderate'},

    # Hematology
    'D50.9': {'description': 'Iron deficiency anemia, unspecified', 'category': 'Hematology', 'severity': 'Moderate'},
    'D68.9': {'description': 'Coagulation defect, unspecified', 'category': 'Hematology', 'severity': 'High'},
    'D69.6': {'description': 'Thrombocytopenia, unspecified', 'category': 'Hematology', 'severity': 'High'}
}

# Comprehensive CPT procedure codes
CPT_CODES = {
    # Emergency Department
    '99285': {'description': 'Emergency department visit, high severity', 'category': 'Emergency','typical_charge': (800, 1500)},
    '99284': {'description': 'Emergency department visit, moderate severity', 'category': 'Emergency','typical_charge': (500, 900)},
    '99283': {'description': 'Emergency department visit, moderate complexity', 'category': 'Emergency','typical_charge': (300, 600)},
    '99282': {'description': 'Emergency department visit, low complexity', 'category': 'Emergency','typical_charge': (150, 350)},
    '99281': {'description': 'Emergency department visit, minimal', 'category': 'Emergency','typical_charge': (100, 200)},

    # Inpatient Hospital Care
    '99223': {'description': 'Initial hospital care, high complexity', 'category': 'Inpatient','typical_charge': (300, 600)},
    '99222': {'description': 'Initial hospital care, moderate complexity', 'category': 'Inpatient','typical_charge': (200, 450)},
    '99221': {'description': 'Initial hospital care, low complexity', 'category': 'Inpatient','typical_charge': (150, 350)},
    '99233': {'description': 'Subsequent hospital care, high complexity', 'category': 'Inpatient','typical_charge': (150, 350)},
    '99232': {'description': 'Subsequent hospital care, moderate complexity', 'category': 'Inpatient','typical_charge': (100, 250)},
    '99231': {'description': 'Subsequent hospital care, low complexity', 'category': 'Inpatient','typical_charge': (75, 175)},
    '99238': {'description': 'Hospital discharge day management', 'category': 'Inpatient','typical_charge': (100, 250)},
    '99239': {'description': 'Hospital discharge, >30 minutes', 'category': 'Inpatient', 'typical_charge': (150, 300)},

    # Critical Care
    '99291': {'description': 'Critical care, first hour', 'category': 'Critical Care', 'typical_charge': (500, 1000)},
    '99292': {'description': 'Critical care, each additional 30 minutes', 'category': 'Critical Care','typical_charge': (250, 500)},

    # Office/Outpatient Visits
    '99215': {'description': 'Office visit, established patient, high complexity', 'category': 'Office Visit','typical_charge': (150, 300)},
    '99214': {'description': 'Office visit, established patient, moderate complexity', 'category': 'Office Visit','typical_charge': (100, 200)},
    '99213': {'description': 'Office visit, established patient, low complexity', 'category': 'Office Visit','typical_charge': (75, 150)},
    '99212': {'description': 'Office visit, established patient, straightforward', 'category': 'Office Visit','typical_charge': (50, 100)},
    '99205': {'description': 'Office visit, new patient, high complexity', 'category': 'Office Visit','typical_charge': (200, 400)},
    '99204': {'description': 'Office visit, new patient, moderate complexity', 'category': 'Office Visit','typical_charge': (150, 300)},
    '99203': {'description': 'Office visit, new patient, low complexity', 'category': 'Office Visit','typical_charge': (100, 200)},
    '99202': {'description': 'Office visit, new patient, straightforward', 'category': 'Office Visit','typical_charge': (75, 150)},

    # Laboratory
    '36415': {'description': 'Routine venipuncture', 'category': 'Lab', 'typical_charge': (10, 25)},
    '80053': {'description': 'Comprehensive metabolic panel', 'category': 'Lab', 'typical_charge': (30, 75)},
    '85025': {'description': 'Complete blood count with differential', 'category': 'Lab', 'typical_charge': (20, 50)},
    '84443': {'description': 'TSH test', 'category': 'Lab', 'typical_charge': (25, 60)},
    '82947': {'description': 'Glucose blood test', 'category': 'Lab', 'typical_charge': (10, 25)},
    '83036': {'description': 'Hemoglobin A1C', 'category': 'Lab', 'typical_charge': (20, 50)},
    '84550': {'description': 'Uric acid blood test', 'category': 'Lab', 'typical_charge': (15, 35)},
    '84478': {'description': 'Triglycerides test', 'category': 'Lab', 'typical_charge': (20, 45)},
    '82465': {'description': 'Cholesterol test', 'category': 'Lab', 'typical_charge': (20, 45)},
    '87086': {'description': 'Urine culture', 'category': 'Lab', 'typical_charge': (30, 70)},
    '87070': {'description': 'Bacterial culture', 'category': 'Lab', 'typical_charge': (40, 90)},
    '81001': {'description': 'Urinalysis, automated', 'category': 'Lab', 'typical_charge': (10, 25)},
    '83718': {'description': 'Lipoprotein panel', 'category': 'Lab', 'typical_charge': (35, 80)},
    '84153': {'description': 'PSA test', 'category': 'Lab', 'typical_charge': (30, 70)},

    # Diagnostic Testing
    '93000': {'description': 'Electrocardiogram, complete', 'category': 'Diagnostic', 'typical_charge': (50, 150)},
    '94010': {'description': 'Spirometry', 'category': 'Diagnostic', 'typical_charge': (50, 125)},
    '93005': {'description': 'Electrocardiogram, tracing only', 'category': 'Diagnostic', 'typical_charge': (25, 75)},
    '93306': {'description': 'Echocardiography, complete', 'category': 'Diagnostic', 'typical_charge': (300, 800)},
    '93015': {'description': 'Cardiovascular stress test', 'category': 'Diagnostic', 'typical_charge': (200, 500)},
    '95860': {'description': 'Needle EMG, one extremity', 'category': 'Diagnostic', 'typical_charge': (150, 400)},
    '95886': {'description': 'Nerve conduction study', 'category': 'Diagnostic', 'typical_charge': (200, 500)},

    # Imaging - X-Ray
    '71046': {'description': 'Chest X-ray, 2 views', 'category': 'Imaging', 'typical_charge': (100, 300)},
    '71045': {'description': 'Chest X-ray, single view', 'category': 'Imaging', 'typical_charge': (75, 200)},
    '73030': {'description': 'Shoulder X-ray', 'category': 'Imaging', 'typical_charge': (80, 250)},
    '73060': {'description': 'Humerus X-ray', 'category': 'Imaging', 'typical_charge': (80, 250)},
    '73110': {'description': 'Wrist X-ray, complete', 'category': 'Imaging', 'typical_charge': (75, 225)},
    '73610': {'description': 'Ankle X-ray, complete', 'category': 'Imaging', 'typical_charge': (75, 225)},
    '72040': {'description': 'Cervical spine X-ray', 'category': 'Imaging', 'typical_charge': (100, 300)},
    '72100': {'description': 'Lumbar spine X-ray', 'category': 'Imaging', 'typical_charge': (100, 300)},

    # Imaging - CT
    '70450': {'description': 'CT scan, head without contrast', 'category': 'Imaging', 'typical_charge': (500, 1200)},
    '70460': {'description': 'CT scan, head with contrast', 'category': 'Imaging', 'typical_charge': (700, 1600)},
    '71250': {'description': 'CT scan, chest without contrast', 'category': 'Imaging', 'typical_charge': (600, 1400)},
    '71260': {'description': 'CT scan, chest with contrast', 'category': 'Imaging', 'typical_charge': (800, 1800)},
    '74160': {'description': 'CT scan, abdomen with contrast', 'category': 'Imaging', 'typical_charge': (800, 1800)},
    '74177': {'description': 'CT scan, abdomen and pelvis with contrast', 'category': 'Imaging','typical_charge': (1000, 2500)},
    '72193': {'description': 'CT scan, pelvis with contrast', 'category': 'Imaging', 'typical_charge': (700, 1600)},

    # Imaging - MRI
    '70551': {'description': 'MRI brain without contrast', 'category': 'Imaging', 'typical_charge': (800, 2000)},
    '70553': {'description': 'MRI brain with and without contrast', 'category': 'Imaging','typical_charge': (1200, 3000)},
    '72141': {'description': 'MRI cervical spine without contrast', 'category': 'Imaging','typical_charge': (800, 2000)},
    '72148': {'description': 'MRI lumbar spine without contrast', 'category': 'Imaging', 'typical_charge': (800, 2000)},
    '73221': {'description': 'MRI upper extremity without contrast', 'category': 'Imaging','typical_charge': (700, 1800)},
    '73721': {'description': 'MRI lower extremity without contrast', 'category': 'Imaging','typical_charge': (700, 1800)},

    # Imaging - Ultrasound
    '76700': {'description': 'Ultrasound, abdominal, complete', 'category': 'Imaging', 'typical_charge': (200, 500)},
    '76770': {'description': 'Ultrasound, retroperitoneal', 'category': 'Imaging', 'typical_charge': (200, 500)},
    '76805': {'description': 'Ultrasound, pregnant uterus', 'category': 'Imaging', 'typical_charge': (200, 500)},
    '93880': {'description': 'Duplex scan of extracranial arteries', 'category': 'Imaging','typical_charge': (300, 700)},

    # Procedures - GI
    '43239': {'description': 'Upper GI endoscopy with biopsy', 'category': 'Procedure', 'typical_charge': (800, 2000)},
    '45378': {'description': 'Colonoscopy, diagnostic', 'category': 'Procedure', 'typical_charge': (1000, 2500)},
    '45380': {'description': 'Colonoscopy with biopsy', 'category': 'Procedure', 'typical_charge': (1200, 2800)},
    '45385': {'description': 'Colonoscopy with polyp removal', 'category': 'Procedure', 'typical_charge': (1500, 3500)},
    '43235': {'description': 'Upper GI endoscopy, diagnostic', 'category': 'Procedure', 'typical_charge': (600, 1500)},

    # Procedures - Cardiovascular
    '92928': {'description': 'Coronary angioplasty with stent', 'category': 'Procedure','typical_charge': (15000, 40000)},
    '93458': {'description': 'Cardiac catheterization', 'category': 'Procedure', 'typical_charge': (5000, 15000)},
    '33533': {'description': 'Coronary artery bypass, single graft', 'category': 'Surgery','typical_charge': (30000, 80000)},

    # Procedures - Respiratory
    '31623': {'description': 'Bronchoscopy with brushings', 'category': 'Procedure', 'typical_charge': (800, 2000)},
    '94640': {'description': 'Nebulizer treatment', 'category': 'Procedure', 'typical_charge': (25, 75)},
    '94060': {'description': 'Bronchodilation test', 'category': 'Procedure', 'typical_charge': (75, 200)},

    # Surgery - Orthopedic
    '27447': {'description': 'Total knee arthroplasty', 'category': 'Surgery', 'typical_charge': (15000, 35000)},
    '27130': {'description': 'Total hip arthroplasty', 'category': 'Surgery', 'typical_charge': (15000, 40000)},
    '29881': {'description': 'Arthroscopy, knee with meniscectomy', 'category': 'Surgery','typical_charge': (3000, 8000)},
    '23472': {'description': 'Shoulder arthroplasty', 'category': 'Surgery', 'typical_charge': (12000, 30000)},
    '63030': {'description': 'Lumbar laminectomy', 'category': 'Surgery', 'typical_charge': (10000, 25000)},
    '25600': {'description': 'Closed treatment of distal radius fracture', 'category': 'Surgery','typical_charge': (800, 2000)},

    # Surgery - General
    '47562': {'description': 'Laparoscopic cholecystectomy', 'category': 'Surgery', 'typical_charge': (5000, 15000)},
    '49505': {'description': 'Inguinal hernia repair', 'category': 'Surgery', 'typical_charge': (3000, 8000)},
    '44970': {'description': 'Laparoscopic appendectomy', 'category': 'Surgery', 'typical_charge': (5000, 12000)},
    '19307': {'description': 'Mastectomy, modified radical', 'category': 'Surgery', 'typical_charge': (8000, 20000)},
    '58150': {'description': 'Total abdominal hysterectomy', 'category': 'Surgery', 'typical_charge': (7000, 18000)},

    # Anesthesia
    '01992': {'description': 'Anesthesia for procedures on nerves', 'category': 'Anesthesia','typical_charge': (300, 800)},
    '00740': {'description': 'Anesthesia for upper GI endoscopy', 'category': 'Anesthesia','typical_charge': (400, 1000)},
    '01382': {'description': 'Anesthesia for diagnostic arthroscopy', 'category': 'Anesthesia', 'typical_charge': (500, 1200)},

    # Injections/Infusions
    '96372': {'description': 'Therapeutic injection, subcutaneous/intramuscular', 'category': 'Injection','typical_charge': (25, 75)},
    '96365': {'description': 'IV infusion, first hour', 'category': 'Infusion', 'typical_charge': (100, 300)},
    '96366': {'description': 'IV infusion, each additional hour', 'category': 'Infusion', 'typical_charge': (50, 150)},
    '96374': {'description': 'IV push, single or initial substance', 'category': 'Injection','typical_charge': (75, 200)},
    '20610': {'description': 'Joint aspiration/injection, major joint', 'category': 'Injection','typical_charge': (100, 300)},

    # Physical Medicine
    '97110': {'description': 'Physical therapy, therapeutic exercises', 'category': 'Therapy','typical_charge': (50, 150)},
    '97140': {'description': 'Manual therapy techniques', 'category': 'Therapy', 'typical_charge': (50, 150)},
    '97530': {'description': 'Therapeutic activities', 'category': 'Therapy', 'typical_charge': (50, 150)},
    '97112': {'description': 'Neuromuscular reeducation', 'category': 'Therapy', 'typical_charge': (50, 150)},

    # Dialysis
    '90935': {'description': 'Hemodialysis, single session', 'category': 'Dialysis', 'typical_charge': (300, 800)},
    '90945': {'description': 'Dialysis, other than hemodialysis', 'category': 'Dialysis', 'typical_charge': (250, 700)},

    # Preventive Services
    '99385': {'description': 'Preventive visit, new patient, 18-39 years', 'category': 'Preventive','typical_charge': (150, 300)},
    '99395': {'description': 'Preventive visit, established patient, 18-39 years', 'category': 'Preventive','typical_charge': (125, 250)},
    '99396': {'description': 'Preventive visit, established patient, 40-64 years', 'category': 'Preventive','typical_charge': (150, 300)},
    '90471': {'description': 'Immunization administration, first vaccine', 'category': 'Preventive','typical_charge': (20, 50)},
    '90472': {'description': 'Immunization administration, each additional', 'category': 'Preventive','typical_charge': (15, 40)},

    # Miscellaneous
    '99000': {'description': 'Specimen handling', 'category': 'Miscellaneous', 'typical_charge': (10, 30)},
    '99070': {'description': 'Supplies and materials', 'category': 'Miscellaneous', 'typical_charge': (10, 100)},
    '99211': {'description': 'Office visit, nurse only', 'category': 'Office Visit', 'typical_charge': (25, 75)}
}

# Medical specialties
SPECIALTIES = [
    # Primary Care
    'Internal Medicine', 'Family Medicine', 'General Practice', 'Pediatrics',

    # Emergency & Critical Care
    'Emergency Medicine', 'Critical Care Medicine', 'Trauma Surgery',

    # Cardiovascular
    'Cardiology', 'Cardiothoracic Surgery', 'Vascular Surgery', 'Interventional Cardiology',

    # Surgical Specialties
    'General Surgery', 'Orthopedic Surgery', 'Neurosurgery', 'Plastic Surgery', 'Urological Surgery', 'Colorectal Surgery', 'Transplant Surgery', 'Pediatric Surgery', 'Oral and Maxillofacial Surgery', 'Hand Surgery', 'Bariatric Surgery',

    # Medical Specialties
    'Pulmonology', 'Gastroenterology', 'Nephrology', 'Endocrinology', 'Rheumatology', 'Infectious Disease', 'Hematology', 'Oncology', 'Neurology', 'Geriatrics', 'Hospitalist', 'Palliative Care', 'Pain Management', 'Physical Medicine and Rehabilitation',

    # Women's Health
    'Obstetrics', 'Gynecology', 'Obstetrics and Gynecology', 'Maternal-Fetal Medicine', 'Reproductive Endocrinology', 'Gynecologic Oncology',

    # Mental Health & Behavioral
    'Psychiatry', 'Child and Adolescent Psychiatry', 'Addiction Medicine', 'Psychology', 'Behavioral Health',

    # Diagnostic Specialties
    'Radiology', 'Interventional Radiology', 'Neuroradiology', 'Nuclear Medicine', 'Pathology', 'Clinical Pathology', 'Anatomical Pathology',

    # Procedural Specialties
    'Anesthesiology', 'Pain Medicine', 'Dermatology', 'Ophthalmology', 'Otolaryngology (ENT)', 'Allergy and Immunology',

    # Specialized Medicine
    'Sleep Medicine', 'Sports Medicine', 'Occupational Medicine', 'Preventive Medicine', 'Medical Genetics', 'Clinical Pharmacology',

    # Pediatric Subspecialties
    'Pediatric Cardiology', 'Pediatric Pulmonology', 'Pediatric Gastroenterology', 'Pediatric Neurology', 'Pediatric Oncology', 'Pediatric Intensive Care', 'Neonatology', 'Pediatric Emergency Medicine',

    # Other Specialties
    'Wound Care', 'Hyperbaric Medicine', 'Telemedicine', 'Integrative Medicine'
]

# Facility types
FACILITY_TYPES = [
    # Emergency & Acute Care
    'Emergency Department', 'Trauma Center Level I', 'Trauma Center Level II', 'Urgent Care', 'Fast Track/Minor Care', 'Observation Unit',

    # Intensive Care Units
    'Intensive Care Unit', 'Medical ICU', 'Surgical ICU', 'Cardiac ICU', 'Neurological ICU', 'Pediatric ICU', 'Neonatal ICU', 'Burn ICU', 'Trauma ICU',

    # Inpatient Units
    'Medical-Surgical Unit', 'Progressive Care Unit', 'Step-Down Unit', 'Telemetry Unit', 'Oncology Unit', 'Orthopedic Unit', 'Neurology Unit', 'Cardiac Unit', 'Pulmonary Unit', 'Renal Unit', 'Rehabilitation Unit', 'Geriatric Unit', 'Palliative Care Unit', 'Hospice Unit',

    # Maternal & Child Health
    'Labor & Delivery', 'Postpartum Unit', 'Antepartum Unit', 'Newborn Nursery', 'Pediatric Unit', 'Pediatric Medical-Surgical Unit',

    # Surgical Services
    'Operating Room', 'Pre-Operative Area', 'Post-Anesthesia Care Unit (PACU)', 'Ambulatory Surgery Center', 'Day Surgery Unit', 'Same-Day Surgery',

    # Diagnostic & Imaging
    'Radiology', 'CT Scan Suite', 'MRI Suite', 'Ultrasound', 'Mammography', 'Nuclear Medicine', 'PET Scan Center', 'X-Ray', 'Fluoroscopy', 'Interventional Radiology',

    # Procedural Areas
    'Cardiac Catheterization Lab', 'Electrophysiology Lab', 'Endoscopy Suite', 'Bronchoscopy Suite', 'Dialysis Center', 'Infusion Center', 'Chemotherapy Suite', 'Blood Bank', 'Transfusion Services',

    # Outpatient Services
    'Outpatient Clinic', 'Primary Care Clinic', 'Specialty Clinic', 'Multi-Specialty Clinic', 'Walk-In Clinic', 'Retail Clinic', 'Community Health Center', 'Federally Qualified Health Center',

    # Therapy & Rehabilitation
    'Physical Therapy', 'Occupational Therapy', 'Speech Therapy', 'Cardiac Rehabilitation', 'Pulmonary Rehabilitation', 'Wound Care Center', 'Pain Management Clinic',

    # Mental Health & Behavioral
    'Psychiatric Unit', 'Behavioral Health Unit', 'Crisis Stabilization Unit', 'Substance Abuse Treatment Center', 'Detoxification Unit', 'Partial Hospitalization Program', 'Intensive Outpatient Program',

    # Specialized Services
    'Sleep Center', 'Bariatric Center', 'Burn Center', 'Stroke Center', 'Chest Pain Center', 'Cancer Center', 'Comprehensive Cancer Center', 'Heart & Vascular Center', 'Neuroscience Center', 'Orthopedic Center', 'Womens Health Center', 'Birthing Center',

    # Support Service
    'Laboratory', 'Pathology Lab', 'Blood Draw Station', 'Pharmacy','Central Supply', 'Sterilization Services',

    # Long-Term & Skilled Care
    'Skilled Nursing Facility', 'Long-Term Acute Care Hospital', 'Subacute Rehabilitation', 'Extended Care Facility',

    # Home & Community
    'Home Health', 'Hospice Home Care', 'Telemedicine Center', 'Mobile Health Unit', 'Occupational Health Clinic',

    # Academic & Research
    'Teaching Hospital', 'Academic Medical Center', 'Research Hospital', 'Clinical Trials Unit'
]

# Insurance types
INSURANCE_TYPES = [
    # Government Programs
    'Medicare', 'Medicare Advantage', 'Medicare Part A', 'Medicare Part B', 'Medicare Part D', 'Medicaid', 'Medicaid Managed Care', 'CHIP', 'Tricare', 'VA Benefits', 'Indian Health Service',

    # Commercial Insurance
    'Blue Cross Blue Shield', 'Aetna', 'Cigna', 'UnitedHealthcare', 'Humana', 'Anthem', 'Kaiser Permanente', 'Centene', 'Molina Healthcare', 'WellCare', 'Health Net', 'Ambetter',

    # Plan Types
    'HMO', 'PPO', 'EPO', 'POS', 'High Deductible Health Plan', 'HSA-Compatible Plan', 'Catastrophic Plan',

    # Employer-Sponsored
    'Employer Group Health Plan', 'Self-Insured Plan', 'Union Health Plan',

    # Individual Market
    'Individual Marketplace Plan', 'ACA Marketplace Plan', 'Direct Purchase Plan',

    # Supplemental
    'Medicare Supplement', 'Medigap', 'Dental Insurance', 'Vision Insurance', 'Prescription Drug Plan',

    # Other
    'Workers Compensation', 'Auto Insurance (Medical)', 'Liability Insurance', 'Self-Pay', 'Charity Care', 'Financial Assistance', 'Uninsured/Indigent'
]

# Admission types
ADMISSION_TYPES = [
    'Emergency', 'Urgent', 'Elective', 'Trauma', 'Newborn',
    'Observation', 'Direct Admit', 'Transfer', 'Scheduled Surgery',
    'Labor and Delivery', 'Same Day Surgery', 'Outpatient to Inpatient',
    'Readmission', 'Court/Law Enforcement'
]

# Discharge dispositions
DISCHARGE_DISPOSITIONS = [
    'Home', 'Home with Home Health', 'Skilled Nursing Facility',
    'Inpatient Rehabilitation', 'Long-Term Care Hospital', 'Hospice Home',
    'Hospice Facility', 'Psychiatric Facility', 'Against Medical Advice',
    'Transfer to Another Hospital', 'Left Without Being Seen',
    'Expired', 'Expired in Emergency Department', 'Swing Bed',
    'Short-Term Hospital', 'Assisted Living Facility'
]

# Fictional payer types with reimbursement rates for synthetic data generation
PAYERS = [
    # Government Programs - Lower reimbursement rates
    {'payer_name': 'Federal Health Program', 'payer_type': 'Government', 'reimbursement_rate': 0.85},
    {'payer_name': 'Senior Care Advantage', 'payer_type': 'Government', 'reimbursement_rate': 0.87},
    {'payer_name': 'Golden Years Health Plan', 'payer_type': 'Government', 'reimbursement_rate': 0.86},
    {'payer_name': 'National Senior Insurance', 'payer_type': 'Government', 'reimbursement_rate': 0.88},
    {'payer_name': 'State Medical Assistance', 'payer_type': 'Government', 'reimbursement_rate': 0.70},
    {'payer_name': 'State Care Managed', 'payer_type': 'Government', 'reimbursement_rate': 0.72},
    {'payer_name': 'Public Health Partners', 'payer_type': 'Government', 'reimbursement_rate': 0.71},
    {'payer_name': 'Community Care Network', 'payer_type': 'Government', 'reimbursement_rate': 0.73},
    {'payer_name': 'Children Health Initiative', 'payer_type': 'Government', 'reimbursement_rate': 0.75},
    {'payer_name': 'Military Family Health', 'payer_type': 'Government', 'reimbursement_rate': 0.82},
    {'payer_name': 'Veterans Medical Benefits', 'payer_type': 'Government', 'reimbursement_rate': 0.80},

    # Major Commercial Payers - Higher reimbursement rates
    {'payer_name': 'American Health Shield', 'payer_type': 'Commercial', 'reimbursement_rate': 0.95},
    {'payer_name': 'Premier Health Insurance', 'payer_type': 'Commercial', 'reimbursement_rate': 0.94},
    {'payer_name': 'National Healthcare Alliance', 'payer_type': 'Commercial', 'reimbursement_rate': 0.96},
    {'payer_name': 'Liberty Health Group', 'payer_type': 'Commercial', 'reimbursement_rate': 0.92},
    {'payer_name': 'United Medical Coverage', 'payer_type': 'Commercial', 'reimbursement_rate': 0.93},
    {'payer_name': 'Summit Health Insurance', 'payer_type': 'Commercial', 'reimbursement_rate': 0.90},
    {'payer_name': 'Horizon Healthcare', 'payer_type': 'Commercial', 'reimbursement_rate': 0.88},
    {'payer_name': 'Apex Medical Plans', 'payer_type': 'Commercial', 'reimbursement_rate': 0.91},
    {'payer_name': 'Cornerstone Health Network', 'payer_type': 'Commercial', 'reimbursement_rate': 0.89},
    {'payer_name': 'Pinnacle Insurance Group', 'payer_type': 'Commercial', 'reimbursement_rate': 0.87},

    # Regional Commercial Payers
    {'payer_name': 'Regional Health Partners', 'payer_type': 'Commercial', 'reimbursement_rate': 0.93},
    {'payer_name': 'Tri-State Medical Insurance', 'payer_type': 'Commercial', 'reimbursement_rate': 0.94},
    {'payer_name': 'Metro Health Alliance', 'payer_type': 'Commercial', 'reimbursement_rate': 0.92},
    {'payer_name': 'Coastal Healthcare Plans', 'payer_type': 'Commercial', 'reimbursement_rate': 0.91},
    {'payer_name': 'Mountain States Insurance', 'payer_type': 'Commercial', 'reimbursement_rate': 0.93},
    {'payer_name': 'Midwest Healthcare Collective', 'payer_type': 'Commercial', 'reimbursement_rate': 0.94},
    {'payer_name': 'Pacific Health Services', 'payer_type': 'Commercial', 'reimbursement_rate': 0.92},
    {'payer_name': 'Atlantic Medical Group', 'payer_type': 'Commercial', 'reimbursement_rate': 0.91},

    # Marketplace/ACA Plans - Moderate reimbursement
    {'payer_name': 'Marketplace Health Options', 'payer_type': 'Marketplace', 'reimbursement_rate': 0.78},
    {'payer_name': 'Affordable Care Solutions', 'payer_type': 'Marketplace', 'reimbursement_rate': 0.76},
    {'payer_name': 'Choice Health Exchange', 'payer_type': 'Marketplace', 'reimbursement_rate': 0.77},
    {'payer_name': 'Community Health Marketplace', 'payer_type': 'Marketplace', 'reimbursement_rate': 0.75},
    {'payer_name': 'Essential Health Plans', 'payer_type': 'Marketplace', 'reimbursement_rate': 0.79},

    # Employer Self-Funded Plans - Variable rates
    {'payer_name': 'Corporate Self-Funded Plan A', 'payer_type': 'Self-Funded', 'reimbursement_rate': 0.95},
    {'payer_name': 'Corporate Self-Funded Plan B', 'payer_type': 'Self-Funded', 'reimbursement_rate': 0.90},
    {'payer_name': 'Union Health Trust', 'payer_type': 'Self-Funded', 'reimbursement_rate': 0.92},
    {'payer_name': 'Employer Coalition Health Plan', 'payer_type': 'Self-Funded', 'reimbursement_rate': 0.93},
    {'payer_name': 'Multi-Employer Benefits Fund', 'payer_type': 'Self-Funded', 'reimbursement_rate': 0.91},

    # Workers Compensation - Higher rates for work-related injuries
    {'payer_name': 'State Workers Compensation Fund', 'payer_type': 'Workers Comp', 'reimbursement_rate': 1.10},
    {'payer_name': 'Industrial Injury Insurance', 'payer_type': 'Workers Comp', 'reimbursement_rate': 1.15},
    {'payer_name': 'Occupational Health Coverage', 'payer_type': 'Workers Comp', 'reimbursement_rate': 1.12},
    {'payer_name': 'Workplace Injury Protection', 'payer_type': 'Workers Comp', 'reimbursement_rate': 1.13},

    # Auto/Liability Insurance - Higher rates
    {'payer_name': 'Auto Medical Coverage Inc', 'payer_type': 'Auto/Liability', 'reimbursement_rate': 1.20},
    {'payer_name': 'Personal Injury Medical Fund', 'payer_type': 'Auto/Liability', 'reimbursement_rate': 1.18},
    {'payer_name': 'Liability Medical Insurance', 'payer_type': 'Auto/Liability', 'reimbursement_rate': 1.25},
    {'payer_name': 'Accident Medical Protection', 'payer_type': 'Auto/Liability', 'reimbursement_rate': 1.22},

    # Other Payer Types
    {'payer_name': 'Self-Pay', 'payer_type': 'Self-Pay', 'reimbursement_rate': 0.30},
    {'payer_name': 'Self-Pay with Financial Assistance', 'payer_type': 'Self-Pay', 'reimbursement_rate': 0.50},
    {'payer_name': 'Charity Care Program', 'payer_type': 'Charity', 'reimbursement_rate': 0.00},
    {'payer_name': 'Uninsured Patient Fund', 'payer_type': 'Uninsured', 'reimbursement_rate': 0.15},
    {'payer_name': 'Sliding Scale Program', 'payer_type': 'Financial Assistance', 'reimbursement_rate': 0.40},

    # International/Travel Insurance
    {'payer_name': 'Global Travel Medical Insurance', 'payer_type': 'International', 'reimbursement_rate': 0.85},
    {'payer_name': 'International Visitor Coverage', 'payer_type': 'International', 'reimbursement_rate': 0.80},
    {'payer_name': 'Worldwide Health Protection', 'payer_type': 'International', 'reimbursement_rate': 0.83},

    # Specialty Payers
    {'payer_name': 'Dental Benefits Corporation', 'payer_type': 'Specialty', 'reimbursement_rate': 0.70},
    {'payer_name': 'Vision Care Insurance', 'payer_type': 'Specialty', 'reimbursement_rate': 0.65},
    {'payer_name': 'Prescription Drug Plan', 'payer_type': 'Specialty', 'reimbursement_rate': 0.75},
    {'payer_name': 'Mental Health Coverage Network', 'payer_type': 'Specialty', 'reimbursement_rate': 0.80}
]

# Payer contract types for more realistic synthetic data
PAYER_CONTRACT_TYPES = [
    {'contract_type': 'Fee-for-Service', 'payment_method': 'Per procedure'},
    {'contract_type': 'Capitation', 'payment_method': 'Per member per month'},
    {'contract_type': 'DRG-Based', 'payment_method': 'Per discharge'},
    {'contract_type': 'Bundled Payment', 'payment_method': 'Per episode'},
    {'contract_type': 'Value-Based', 'payment_method': 'Quality incentives'},
    {'contract_type': 'Shared Savings', 'payment_method': 'Cost sharing'},
    {'contract_type': 'Case Rate', 'payment_method': 'Per case'},
    {'contract_type': 'Per Diem', 'payment_method': 'Per day'}
]

# Denial reasons for realistic claim denials
DENIAL_REASONS = [
    'Prior authorization not obtained',
    'Service not covered under plan',
    'Out of network provider',
    'Medical necessity not established',
    'Timely filing limit exceeded',
    'Duplicate claim',
    'Incorrect patient information',
    'Incorrect coding',
    'Missing documentation',
    'Coordination of benefits issue',
    'Pre-existing condition exclusion',
    'Benefit maximum exceeded',
    'Service not medically necessary',
    'Experimental/investigational procedure',
    'Non-covered service',
    'Incorrect modifier',
    'Bundling issue',
    'Incorrect place of service',
    'Missing referral'
]

# Payment adjustment reasons
ADJUSTMENT_REASONS = [
    'Contractual adjustment',
    'Sequestration reduction',
    'Coordination of benefits',
    'Patient responsibility',
    'Deductible',
    'Coinsurance',
    'Copayment',
    'Non-covered charges',
    'Over the limit',
    'Prompt payment discount',
    'Volume discount',
    'Quality bonus',
    'Penalty adjustment',
    'Outlier payment',
    'Transfer adjustment',
    'Readmission penalty'
]

# Claim status codes
CLAIM_STATUS = [
    'Submitted',
    'In Review',
    'Pending',
    'Approved',
    'Partially Approved',
    'Denied',
    'Appealed',
    'Paid',
    'Partially Paid',
    'Adjusted',
    'Resubmitted',
    'Voided',
    'Under Investigation',
    'Pending Additional Information'
]

# US Regions for geographic distribution
US_REGIONS = {
    'Northeast': ['CT', 'ME', 'MA', 'NH', 'RI', 'VT', 'NJ', 'NY', 'PA'],
    'Midwest': ['IL', 'IN', 'MI', 'OH', 'WI', 'IA', 'KS', 'MN', 'MO', 'NE', 'ND', 'SD'],
    'South': ['DE', 'FL', 'GA', 'MD', 'NC', 'SC', 'VA', 'WV', 'AL', 'KY', 'MS', 'TN', 'AR', 'LA', 'OK', 'TX'],
    'West': ['AZ', 'CO', 'ID', 'MT', 'NV', 'NM', 'UT', 'WY', 'AK', 'CA', 'HI', 'OR', 'WA']
}

# Batch size for memory-efficient processing
BATCH_SIZE = 10000

class OptimizedHealthcareDataGenerator:
    """
    Memory-efficient healthcare data generator with batch processing
    """

    def __init__(self, start_date='2025-01-01', end_date='2025-12-31'):
        self.start_date = pd.to_datetime(start_date)
        self.end_date = pd.to_datetime(end_date)
        self.days = (self.end_date - self.start_date).days + 1

        print("=" * 70)
        print("IsoMetrics Healthcare Data Generator - OPTIMIZED")
        print("=" * 70)
        print(f"Date Range: {start_date} to {end_date}")
        print(f"Total Days: {self.days}")
        print(f"Batch Size: {BATCH_SIZE:,}")
        print("=" * 70)

    @staticmethod
    def get_region(state: str) -> str:
        """Fast region lookup"""
        for region, states in US_REGIONS.items():
            if state in states:
                return region
        return 'Other'

    def generate_hospitals(self) -> pd.DataFrame:
        """Generate hospital master data efficiently"""
        print("\n🏥 Generating hospitals (tenants)...")

        hospitals = []
        hospital_id = 1

        for h_type, config in HOSPITAL_DISTRIBUTION.items():
            for _ in range(config['count']):
                state = fake.state_abbr()
                city = fake.city()

                emr = (random.choice(config['emr_system'])
                       if isinstance(config['emr_system'], list)
                       else config['emr_system'])

                hospitals.append({
                    'hospital_id': f'HOSP_{hospital_id:04d}',
                    'hospital_name': f"{city} {h_type.replace('_', ' ').title()}",
                    'hospital_type': h_type,
                    'bed_count': random.randint(*config['bed_count']),
                    'city': city,
                    'state': state,
                    'region': self.get_region(state),
                    'emr_system': emr,
                    'contract_tier': config['contract_tier'],
                    'contract_start_date': self.start_date - timedelta(days=random.randint(0, 730)),
                    'is_active': True,
                    'teaching_hospital': h_type == 'academic_medical_center'
                })
                hospital_id += 1

        df = pd.DataFrame(hospitals)
        print(f"✓ Generated {len(df)} hospitals")
        return df

    def generate_patients_batch(self, hospital: pd.Series, num_patients: int,
                                start_id: int) -> Generator[Dict, None, None]:
        """Generator function for memory-efficient patient creation"""
        for i in range(num_patients):
            gender = random.choice(['M', 'F', 'Other'])
            dob = fake.date_of_birth(minimum_age=0, maximum_age=95)
            patient_id = start_id + i

            yield {
                'patient_id': f'PAT_{patient_id:010d}',
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
            }

    def generate_patients(self, hospitals_df: pd.DataFrame) -> pd.DataFrame:
        """Generate patients with batch processing"""
        print("\n👥 Generating patients (PHI) with batching...")

        output_file = 'data_generation/2025/patients.csv'
        os.makedirs('data', exist_ok=True)

        patient_id = 1
        first_batch = True

        for _, hospital in tqdm(hospitals_df.iterrows(), total=len(hospitals_df), desc="Hospitals"):
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]
            num_patients = random.randint(*config['patients'])

            # Process in batches
            for batch_start in range(0, num_patients, BATCH_SIZE):
                batch_size = min(BATCH_SIZE, num_patients - batch_start)

                # Generate batch using generator
                batch_data = list(self.generate_patients_batch(
                    hospital, batch_size, patient_id
                ))

                # Write batch to CSV
                batch_df = pd.DataFrame(batch_data)
                batch_df.to_csv(
                    output_file,
                    mode='w' if first_batch else 'a',
                    header=first_batch,
                    index=False
                )

                patient_id += batch_size
                first_batch = False

                # Clear memory
                del batch_data, batch_df
                gc.collect()

        # Return summary info
        total_patients = patient_id - 1
        print(f"✓ Generated {total_patients:,} patients in batches")
        print(f"  Written to: {output_file}")

        # Return empty df with correct schema for downstream use
        return pd.DataFrame(columns=['patient_id', 'hospital_id'])

    def generate_providers(self, hospitals_df: pd.DataFrame) -> pd.DataFrame:
        """Generate providers efficiently"""
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

                providers.append({
                    'provider_id': f'PROV_{provider_id:08d}',
                    'hospital_id': hospital['hospital_id'],
                    'npi': f"{random.randint(1000000000, 9999999999)}",
                    'provider_first_name': fake.first_name(),
                    'provider_last_name': fake.last_name(),
                    'specialty': specialty,
                    'department': self._get_department(specialty),
                    'provider_type': random.choice(['MD', 'DO', 'NP', 'PA']),
                    'hire_date': hire_date,
                    'is_active': random.random() < 0.75,
                    'accepts_new_patients': random.choice([True, False])
                })
                provider_id += 1

        df = pd.DataFrame(providers)
        print(f"✓ Generated {len(df):,} providers")
        return df

    @staticmethod
    def _get_department(specialty: str) -> str:
        """Fast department mapping"""
        dept_map = {
            'Emergency Medicine': 'Emergency Department',
            'Internal Medicine': 'Medicine',
            'Family Medicine': 'Primary Care',
            'Cardiology': 'Cardiology',
            'General Surgery': 'Surgery',
            'Orthopedics': 'Surgery',
            'Obstetrics': "Women's Health"
        }
        return dept_map.get(specialty, 'Medicine')

    def generate_facilities(self, hospitals_df: pd.DataFrame) -> pd.DataFrame:
        """Generate facilities"""
        print("\n🏢 Generating facilities...")

        facilities = []
        facility_id = 1

        for _, hospital in tqdm(hospitals_df.iterrows(), total=len(hospitals_df), desc="Hospitals"):
            for facility_type in FACILITY_TYPES:
                capacity = self._get_facility_capacity(facility_type, hospital['bed_count'])

                facilities.append({
                    'facility_id': f'FAC_{facility_id:08d}',
                    'hospital_id': hospital['hospital_id'],
                    'facility_name': f"{hospital['hospital_name']} - {facility_type}",
                    'facility_type': facility_type,
                    'bed_capacity': capacity,
                    'is_active': True,
                    'opened_date': hospital['contract_start_date']
                })
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
            'Labor & Delivery': 0.05
        }
        ratio = ratios.get(facility_type, 0.10)
        return max(int(hospital_beds * ratio), 5)

    def generate_reference_tables(self) -> tuple:
        """Generate all reference tables"""
        print("\n📚 Generating reference tables...")

        # Diagnoses
        diagnoses = [{
            'diagnosis_code': code,
            'diagnosis_description': details['description'],
            'category': details['category'],
            'severity_level': details['severity'],
            'is_chronic': details['severity'] in ['High', 'Critical']
        } for code, details in ICD10_CODES.items()]

        # Procedures
        procedures = [{
            'procedure_code': code,
            'procedure_description': details['description'],
            'category': details['category'],
            'typical_charge_min': details['typical_charge'][0],
            'typical_charge_max': details['typical_charge'][1]
        } for code, details in CPT_CODES.items()]

        # Payers (updated for dictionary structure)
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

    def generate_encounters_optimized(self, hospitals_df: pd.DataFrame,
                                      patients_df: pd.DataFrame,
                                      providers_df: pd.DataFrame,
                                      facilities_df: pd.DataFrame) -> pd.DataFrame:
        """
        Generate encounters with extreme optimization
        Uses batch processing and generator functions
        """
        print("\n🏥 Generating encounters (optimized batching)...")
        print("  This will take several minutes...")

        output_file = 'data_generation/2025/encounters.csv'
        os.makedirs('data', exist_ok=True)

        encounter_id = 1
        first_batch = True
        total_encounters = 0

        # Pre-compute diagnosis codes list for faster sampling
        diagnosis_codes = list(ICD10_CODES.keys())
        diagnosis_weights = [1.0] * len(diagnosis_codes)

        # Create date range array once
        date_range = pd.date_range(self.start_date, self.end_date, freq='D')

        for _, hospital in tqdm(hospitals_df.iterrows(), total=len(hospitals_df),
                                desc="Hospitals", position=0):
            config = HOSPITAL_DISTRIBUTION[hospital['hospital_type']]

            # Filter data for this hospital
            hosp_providers = providers_df[
                (providers_df['hospital_id'] == hospital['hospital_id']) &
                (providers_df['is_active'] == True)
                ]
            hosp_facilities = facilities_df[
                facilities_df['hospital_id'] == hospital['hospital_id']
                ]

            if len(hosp_providers) == 0:
                continue

            # Process each day
            for date in tqdm(date_range, desc="Days", position=1, leave=False):
                if date < hospital['contract_start_date']:
                    continue

                # Calculate encounters for this day
                base_encounters = random.randint(*config['daily_encounters'])
                seasonality = self._calculate_seasonality(date)
                num_encounters = int(base_encounters * seasonality)

                if num_encounters == 0:
                    continue

                # Generate batch for this day
                batch_data = []

                for _ in range(num_encounters):
                    # Random provider and facility
                    provider = hosp_providers.sample(1).iloc[0]

                    # Encounter type
                    enc_type = random.choices(
                        ['Inpatient', 'Outpatient', 'Emergency', 'Observation'],
                        weights=[0.20, 0.50, 0.25, 0.05]
                    )[0]

                    # Admission time
                    hour = np.random.choice(24, p=self._get_hourly_dist_fast())
                    admission_dt = date + timedelta(hours=hour, minutes=random.randint(0, 59))

                    # LOS and discharge
                    los = self._calculate_los_fast(enc_type)
                    discharge_dt = admission_dt + timedelta(days=los, hours=random.randint(0, 23))

                    # Facility
                    facility = self._assign_facility_fast(enc_type, hosp_facilities)

                    # Diagnosis
                    diagnosis_code = random.choice(diagnosis_codes)

                    # Charges
                    total_charges = self._calculate_charges_fast(enc_type, los)

                    batch_data.append({
                        'encounter_id': f'ENC_{encounter_id:012d}',
                        'hospital_id': hospital['hospital_id'],
                        'patient_id': f'PAT_{random.randint(1, 100000):010d}',  # Placeholder
                        'provider_id': provider['provider_id'],
                        'facility_id': facility['facility_id'],
                        'admission_date': admission_dt,
                        'discharge_date': discharge_dt,
                        'length_of_stay': los,
                        'encounter_type': enc_type,
                        'admission_source': random.choice(ADMISSION_TYPES),
                        'discharge_disposition': random.choice(DISCHARGE_DISPOSITIONS),
                        'primary_diagnosis_code': diagnosis_code,
                        'total_charges': total_charges,
                        'is_readmission': random.random() < 0.05
                    })
                    encounter_id += 1

                # Write batch
                if batch_data:
                    batch_df = pd.DataFrame(batch_data)
                    batch_df.to_csv(
                        output_file,
                        mode='w' if first_batch else 'a',
                        header=first_batch,
                        index=False
                    )
                    total_encounters += len(batch_data)
                    first_batch = False

                    del batch_data, batch_df
                    gc.collect()

        print(f"✓ Generated {total_encounters:,} encounters")
        print(f"  Written to: {output_file}")
        return pd.DataFrame(columns=['encounter_id', 'hospital_id'])

    @staticmethod
    def _calculate_seasonality(date) -> float:
        """Fast seasonality calculation"""
        month = date.month
        if month in [12, 1, 2]:
            return 1.3
        elif month in [7, 8]:
            return 0.85
        return 1.0

    @staticmethod
    def _get_hourly_dist_fast() -> np.ndarray:
        """Pre-computed hourly distribution"""
        hours = np.array([
            0.01, 0.01, 0.01, 0.02, 0.02, 0.03,
            0.04, 0.06, 0.08, 0.09, 0.10, 0.09,
            0.08, 0.07, 0.06, 0.05, 0.04, 0.04,
            0.05, 0.04, 0.03, 0.02, 0.02, 0.01
        ])
        return hours / hours.sum()

    @staticmethod
    def _calculate_los_fast(encounter_type: str) -> int:
        """Fast LOS calculation"""
        if encounter_type == 'Inpatient':
            return max(1, int(np.random.lognormal(1.2, 0.8)))
        elif encounter_type == 'Observation':
            return random.choice([0, 1])
        return 0

    @staticmethod
    def _assign_facility_fast(enc_type: str, facilities_df: pd.DataFrame) -> pd.Series:
        """Fast facility assignment"""
        if enc_type == 'Emergency':
            fac = facilities_df[facilities_df['facility_type'] == 'Emergency Department']
        elif enc_type == 'Inpatient':
            fac = facilities_df[facilities_df['facility_type'].isin([
                'Medical-Surgical Unit', 'Intensive Care Unit'
            ])]
        else:
            fac = facilities_df[facilities_df['facility_type'] == 'Outpatient Clinic']

        return fac.sample(1).iloc[0] if len(fac) > 0 else facilities_df.sample(1).iloc[0]

    @staticmethod
    def _calculate_charges_fast(enc_type: str, los: int) -> float:
        """Fast charge calculation"""
        if enc_type == 'Inpatient':
            return round(random.uniform(2000, 5000) * max(los, 1), 2)
        elif enc_type == 'Emergency':
            return round(random.uniform(500, 3000), 2)
        elif enc_type == 'Observation':
            return round(random.uniform(1000, 2500), 2)
        return round(random.uniform(100, 800), 2)

    def generate_billing_transactions(self, encounters_df: pd.DataFrame,
                                      payers_df: pd.DataFrame) -> pd.DataFrame:
        """Generate billing with batch processing"""
        print("\n💰 Generating billing transactions...")

        # If encounters is empty (streaming mode), read from file
        if len(encounters_df) == 0:
            print("  Reading encounters from file...")
            encounters_df = pd.read_csv(
                'data_generation/2025/encounters.csv',
                parse_dates=['admission_date', 'discharge_date']  # Parse dates
            )

        # Ensure dates are datetime objects (in case they weren't parsed)
        if encounters_df['discharge_date'].dtype == 'object':
            encounters_df['discharge_date'] = pd.to_datetime(encounters_df['discharge_date'])
        if encounters_df['admission_date'].dtype == 'object':
            encounters_df['admission_date'] = pd.to_datetime(encounters_df['admission_date'])

        transactions = []
        transaction_id = 1

        for _, encounter in tqdm(encounters_df.iterrows(), total=len(encounters_df), desc="Encounters"):
            payer = payers_df.sample(1).iloc[0]
            charge = encounter['total_charges']
            payment = round(charge * payer['reimbursement_rate'], 2)
            adjustment = round(charge - payment, 2)

            status = random.choices(
                CLAIM_STATUS[:8],  # Use first 8 statuses for primary selection
                weights=[0.05, 0.10, 0.10, 0.15, 0.05, 0.10, 0.05, 0.40]  # Paid is most common
            )[0]

            # Map status to payment status for compatibility
            if status in ['Paid', 'Partially Paid']:
                payment_status = 'Paid' if status == 'Paid' else 'Partial'
            elif status == 'Denied':
                payment_status = 'Denied'
            else:
                payment_status = 'Pending'

            denial_reason = None
            if payment_status == 'Denied':
                denial_reason = random.choice(DENIAL_REASONS)

            # Convert to timestamp if it's a pandas Timestamp
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
                'payment_amount': payment if payment_status == 'Paid' else 0,
                'adjustment_amount': adjustment,
                'denial_reason': denial_reason,
                'payment_status': payment_status,
                'claim_status': status,
                'adjustment_reason': random.choice(ADJUSTMENT_REASONS) if adjustment > 0 else None
            })
            transaction_id += 1

        df = pd.DataFrame(transactions)
        print(f"✓ Generated {len(df):,} billing transactions")
        return df

    @staticmethod
    def save_to_csv(df: pd.DataFrame, filename: str, output_dir: str = 'data_generation/2025'):
        """Save with progress indication"""
        os.makedirs(output_dir, exist_ok=True)
        filepath = os.path.join(output_dir, filename)

        print(f"  Saving {filename}...", end=" ")
        df.to_csv(filepath, index=False)

        size_mb = os.path.getsize(filepath) / (1024 * 1024)
        print(f"✓ ({len(df):,} rows, {size_mb:.2f} MB)")


def main():
    print("\n" + "=" * 70)
    print("IsoMetrics Healthcare Data Generator - OPTIMIZED")
    print("=" * 70)

    # Initialize
    generator = OptimizedHealthcareDataGenerator(
        start_date='2025-01-01',
        end_date='2025-01-31'
    )

    # Generate data
    hospitals = generator.generate_hospitals()
    generator.save_to_csv(hospitals, 'hospitals.csv')

    patients = generator.generate_patients(hospitals)  # Streams to file

    providers = generator.generate_providers(hospitals)
    generator.save_to_csv(providers, 'providers.csv')

    facilities = generator.generate_facilities(hospitals)
    generator.save_to_csv(facilities, 'facilities.csv')

    diagnoses, procedures, payers = generator.generate_reference_tables()
    generator.save_to_csv(diagnoses, 'diagnoses.csv')
    generator.save_to_csv(procedures, 'procedures.csv')
    generator.save_to_csv(payers, 'payers.csv')

    encounters = generator.generate_encounters_optimized(
        hospitals, patients, providers, facilities
    )  # Streams to file

    billing = generator.generate_billing_transactions(encounters, payers)
    generator.save_to_csv(billing, 'billing_transactions.csv')

    print("\n" + "=" * 70)
    print("✓ GENERATION COMPLETE!")
    print("=" * 70)
    print(f"Hospitals:    {len(hospitals):,}")
    print(f"Providers:    {len(providers):,}")
    print(f"Facilities:   {len(facilities):,}")
    print(f"Diagnoses:    {len(diagnoses):,}")
    print(f"Procedures:   {len(procedures):,}")
    print(f"Payers:       {len(payers):,}")
    print("\nNote: Patients and Encounters written directly to CSV files")
    print("  - data/patients.csv")
    print("  - data/encounters.csv")
    print("\n⚠️  All PHI is synthetic - HIPAA-safe for demonstration")
    print("=" * 70)


if __name__ == "__main__":
    main()