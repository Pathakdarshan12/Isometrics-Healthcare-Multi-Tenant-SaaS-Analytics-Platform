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
        'count': 25,
        'bed_count': (100, 400),
        'daily_encounters': (50, 150),
        'patients': (5000, 20000),
        'providers': (50, 150),
        'specialties': 10,
        'contract_tier': 'Advanced',
        'emr_system': ['Epic', 'Cerner']
    },
    'rural_hospital': {
        'count': 15,
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