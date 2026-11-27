"""Whitelist of mart tables the API exposes.

Only aggregate, de-identified marts are listed. Row-level marts (fct_encounters,
fct_billing_transactions, fct_hipaa_audit_trail) are deliberately not exposed.
Table and column names here are trusted constants; they are the only identifiers
ever interpolated into SQL.
"""
from __future__ import annotations

from dataclasses import dataclass

from api.config import IDENTIFIER


@dataclass(frozen=True)
class Dataset:
    name: str
    table: str
    description: str
    date_column: str | None   # used for start_date/end_date filters; None = not filterable by date
    order_by: str             # newest first

    def __post_init__(self):
        for ident in (self.table, self.date_column or 'x', self.order_by):
            if not IDENTIFIER.match(ident):
                raise ValueError(f'invalid identifier in dataset {self.name}: {ident!r}')


DATASETS: dict[str, Dataset] = {d.name: d for d in [
    Dataset('clinical-quality', 'FCT_CLINICAL_QUALITY_METRICS',
            'Daily readmission, mortality and length-of-stay metrics', 'METRIC_DATE', 'METRIC_DATE'),
    Dataset('core-measures', 'FCT_QUALITY_MEASURE_PERFORMANCE',
            'Quarterly CMS core-measure performance (SEP-1, AMI-8a, STK-4, HF-2, PN-6)',
            None, 'REPORTING_QUARTER'),
    Dataset('early-warning', 'FCT_EARLY_WARNING_SURVEILLANCE',
            'Daily NEWS distribution, sepsis and deterioration alerts', 'METRIC_DATE', 'METRIC_DATE'),
    Dataset('laboratory-quality', 'FCT_LABORATORY_QUALITY_METRICS',
            'Daily lab turnaround and critical-value metrics', 'METRIC_DATE', 'METRIC_DATE'),
    Dataset('medication-safety', 'FCT_MEDICATION_SAFETY_METRICS',
            'Daily barcode compliance, allergy conflicts, high-risk med verification', 'METRIC_DATE', 'METRIC_DATE'),
    Dataset('financial-performance', 'FCT_FINANCIAL_PERFORMANCE',
            'Daily revenue cycle metrics: collections, denials, A/R', 'METRIC_DATE', 'METRIC_DATE'),
    Dataset('prior-authorizations', 'FCT_PRIOR_AUTHORIZATION_METRICS',
            'Monthly prior authorization approval, turnaround and charges at risk by payer',
            'REQUEST_MONTH', 'REQUEST_MONTH'),
    Dataset('operational', 'FCT_OPERATIONAL_METRICS',
            'Daily volumes, bed occupancy and patient flow', 'METRIC_DATE', 'METRIC_DATE'),
    Dataset('care-coordination', 'FCT_CARE_COORDINATION_METRICS',
            'Monthly referral access/closure and care plan management', 'METRIC_MONTH', 'METRIC_MONTH'),
    Dataset('cost-attribution', 'FCT_COST_ATTRIBUTION',
            'Daily Snowflake cost attributed per hospital', 'METRIC_DATE', 'METRIC_DATE'),
]}
