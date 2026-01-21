# ============================================
# CLINICAL CODE LIBRARIES
# ============================================

# Common lab tests with LOINC codes and normal ranges
LAB_TESTS = {
    # Complete Blood Count
    '718-7': {'name': 'Hemoglobin', 'units': 'g/dL', 'range': (12.0, 17.0), 'critical_low': 6.0, 'critical_high': 20.0},
    '4544-3': {'name': 'Hematocrit', 'units': '%', 'range': (36.0, 50.0), 'critical_low': 20.0, 'critical_high': 60.0},
    '6690-2': {'name': 'White Blood Cell Count', 'units': 'K/uL', 'range': (4.0, 11.0), 'critical_low': 1.0,
               'critical_high': 40.0},
    '777-3': {'name': 'Platelet Count', 'units': 'K/uL', 'range': (150, 400), 'critical_low': 20,
              'critical_high': 1000},

    # Basic Metabolic Panel
    '2345-7': {'name': 'Glucose', 'units': 'mg/dL', 'range': (70, 100), 'critical_low': 40, 'critical_high': 500},
    '2951-2': {'name': 'Sodium', 'units': 'mEq/L', 'range': (135, 145), 'critical_low': 120, 'critical_high': 160},
    '2823-3': {'name': 'Potassium', 'units': 'mEq/L', 'range': (3.5, 5.0), 'critical_low': 2.5, 'critical_high': 6.5},
    '2075-0': {'name': 'Chloride', 'units': 'mEq/L', 'range': (96, 106), 'critical_low': 80, 'critical_high': 115},
    '2028-9': {'name': 'CO2', 'units': 'mEq/L', 'range': (23, 29), 'critical_low': 15, 'critical_high': 40},
    '38483-4': {'name': 'Creatinine', 'units': 'mg/dL', 'range': (0.6, 1.2), 'critical_low': 0.3,
                'critical_high': 10.0},
    '3094-0': {'name': 'BUN', 'units': 'mg/dL', 'range': (7, 20), 'critical_low': 2, 'critical_high': 100},

    # Liver Function
    '1742-6': {'name': 'ALT', 'units': 'U/L', 'range': (7, 56), 'critical_low': None, 'critical_high': 1000},
    '1920-8': {'name': 'AST', 'units': 'U/L', 'range': (10, 40), 'critical_low': None, 'critical_high': 1000},
    '1975-2': {'name': 'Total Bilirubin', 'units': 'mg/dL', 'range': (0.1, 1.2), 'critical_low': None,
               'critical_high': 12.0},

    # Cardiac Markers
    '10839-9': {'name': 'Troponin I', 'units': 'ng/mL', 'range': (0.0, 0.04), 'critical_low': None,
                'critical_high': 0.5},

    # Coagulation
    '5902-2': {'name': 'PT', 'units': 'sec', 'range': (11, 13.5), 'critical_low': None, 'critical_high': 30},
    '6301-6': {'name': 'INR', 'units': '', 'range': (0.8, 1.2), 'critical_low': None, 'critical_high': 5.0},
}

# Medication list with routes and frequencies
MEDICATIONS = [
    # Cardiac
    {'name': 'Metoprolol', 'dose': '25 mg', 'routes': ['PO'], 'frequency': 'BID', 'is_high_risk': False},
    {'name': 'Lisinopril', 'dose': '10 mg', 'routes': ['PO'], 'frequency': 'Daily', 'is_high_risk': False},
    {'name': 'Aspirin', 'dose': '81 mg', 'routes': ['PO'], 'frequency': 'Daily', 'is_high_risk': False},
    {'name': 'Furosemide', 'dose': '40 mg', 'routes': ['PO', 'IV'], 'frequency': 'Daily', 'is_high_risk': False},

    # Diabetes (HIGH RISK)
    {'name': 'Insulin Aspart', 'dose': '10 units', 'routes': ['Subcutaneous'], 'frequency': 'AC', 'is_high_risk': True},
    {'name': 'Insulin Glargine', 'dose': '20 units', 'routes': ['Subcutaneous'], 'frequency': 'Daily',
     'is_high_risk': True},

    # Antibiotics
    {'name': 'Ceftriaxone', 'dose': '1 g', 'routes': ['IV'], 'frequency': 'Daily', 'is_high_risk': False},
    {'name': 'Vancomycin', 'dose': '1 g', 'routes': ['IV'], 'frequency': 'Q12H', 'is_high_risk': False},

    # Pain (HIGH RISK - Opioids)
    {'name': 'Morphine', 'dose': '4 mg', 'routes': ['IV'], 'frequency': 'Q4H PRN', 'is_high_risk': True},
    {'name': 'Hydromorphone', 'dose': '2 mg', 'routes': ['PO', 'IV'], 'frequency': 'Q4H PRN', 'is_high_risk': True},
    {'name': 'Acetaminophen', 'dose': '650 mg', 'routes': ['PO'], 'frequency': 'Q6H PRN', 'is_high_risk': False},

    # Anticoagulation (HIGH RISK)
    {'name': 'Warfarin', 'dose': '5 mg', 'routes': ['PO'], 'frequency': 'Daily', 'is_high_risk': True},
    {'name': 'Heparin', 'dose': '5000 units', 'routes': ['IV'], 'frequency': 'Continuous', 'is_high_risk': True},

    # GI
    {'name': 'Omeprazole', 'dose': '20 mg', 'routes': ['PO'], 'frequency': 'Daily', 'is_high_risk': False},
]

# Common allergies
COMMON_ALLERGENS = [
    {'name': 'Penicillin', 'reactions': ['Rash', 'Anaphylaxis'], 'severity': ['MODERATE', 'LIFE_THREATENING']},
    {'name': 'Sulfa', 'reactions': ['Rash', 'Stevens-Johnson Syndrome'], 'severity': ['MODERATE', 'SEVERE']},
    {'name': 'Morphine', 'reactions': ['Nausea', 'Itching'], 'severity': ['MILD', 'MODERATE']},
    {'name': 'Shellfish', 'reactions': ['Hives', 'Anaphylaxis'], 'severity': ['MODERATE', 'LIFE_THREATENING']},
]

# Common diagnoses for problem list
CHRONIC_DIAGNOSES = [
    ('E11.9', 'Type 2 Diabetes Mellitus', True, 'MODERATE'),
    ('I10', 'Essential Hypertension', True, 'MODERATE'),
    ('J44.9', 'COPD', True, 'HIGH'),
    ('I50.9', 'Heart Failure', True, 'HIGH'),
    ('N18.3', 'Chronic Kidney Disease Stage 3', True, 'HIGH'),
    ('F32.9', 'Major Depression', True, 'MODERATE'),
]