"""
fetcher.py
----------
Production-grade data ingestion layer for the FinOps Dashboard.

Modes:
  1. AWS   – Calls the real AWS Cost Explorer API (GetCostAndUsage).
             Requires: AWS credentials configured via env vars or ~/.aws/credentials
             IAM permission: ce:GetCostAndUsage
  2. GCP   – Placeholder for GCP Billing API (BigQuery Export method).
  3. Simulate – Generates statistically realistic data using Gaussian profiles.
               Perfect for CI, demos, and local development without cloud credentials.

Usage (CLI):
    python -m scripts.run_fetch --mode simulate --days 30
    python -m scripts.run_fetch --mode aws --days 14
"""

import logging
import random
import time
from datetime import date, datetime, timedelta
from typing import List, Dict, Any, Optional

from src.config import FREE_TIER_LIMITS, CONFIG
from src import db

logger = logging.getLogger("finops.fetcher")

# ── Simulation Profiles ────────────────────────────────────────────────────────
# Each profile defines a realistic usage pattern that reflects a dev team
# actively using AWS with some services near / over free tier limits.
#
# Format: { base_daily: float, std_dev: float, trend: float }
#   trend > 0 → usage grows each day (e.g., growing S3 bucket)
#   trend < 0 → usage shrinks (e.g., EC2 stopped mid-month)
SIM_PROFILES: Dict[str, Dict[str, float]] = {
    "AmazonEC2":        {"base": 21.0,   "std": 1.5,    "trend":  0.05},
    "AmazonRDS":        {"base": 23.5,   "std": 1.2,    "trend":  0.10},
    "AmazonS3":         {"base": 0.185,  "std": 0.025,  "trend":  0.008},
    "AWSLambda":        {"base": 28000,  "std": 4500,   "trend": -200},
    "AmazonDynamoDB":   {"base": 0.72,   "std": 0.08,   "trend":  0.005},
    "AWSDataTransfer":  {"base": 0.52,   "std": 0.08,   "trend":  0.012},
    "AmazonCloudWatch": {"base": 0.28,   "std": 0.03,   "trend":  0.0},
    "AWSCloudTrail":    {"base": 2400,   "std": 280,    "trend":  10},
    "AmazonSNS":        {"base": 18000,  "std": 3000,   "trend":  50},
    "AmazonSQS":        {"base": 22000,  "std": 4000,   "trend":  80},
}

# ── Simulator ──────────────────────────────────────────────────────────────────
def simulate_usage(days: int = 30) -> List[Dict[str, Any]]:
    """
    Generate realistic daily usage records for all tracked services.
    Applies Gaussian noise + linear trend to simulate organic cloud usage growth.
    """
    logger.info(f"[SIMULATE] Generating {days}-day usage simulation...")
    records = []
    today   = date.today()

    for service_key, svc in FREE_TIER_LIMITS.items():
        profile = SIM_PROFILES.get(service_key)
        if not profile:
            continue

        for day_offset in range(days):
            record_date = today - timedelta(days=(days - day_offset - 1))
            # Linear trend component
            trend_component = profile["trend"] * day_offset
            # Gaussian noise around base
            daily_usage = max(
                0.0,
                random.gauss(profile["base"] + trend_component, profile["std"])
            )
            records.append({
                "date":         str(record_date),
                "service_key":  service_key,
                "service_name": svc.service_name,
                "category":     svc.category,
                "usage_amount": round(daily_usage, 6),
                "usage_unit":   svc.unit,
                "blended_cost": 0.0,   # zero until free tier exceeded
                "data_source":  "simulate",
                "fetched_at":   datetime.utcnow().isoformat(),
            })

    logger.info(f"[SIMULATE] Generated {len(records)} records across {len(SIM_PROFILES)} services")
    return records


# ── AWS Cost Explorer ──────────────────────────────────────────────────────────
def fetch_aws_cost_explorer(start_date: str, end_date: str,
                            max_retries: int = 3) -> List[Dict[str, Any]]:
    """
    Fetch real usage from AWS Cost Explorer GetCostAndUsage API.

    Parameters
    ----------
    start_date : str  YYYY-MM-DD inclusive start
    end_date   : str  YYYY-MM-DD exclusive end
    max_retries: int  Retry attempts on transient failures

    Returns
    -------
    List of usage record dicts ready for db.upsert_usage()
    """
    try:
        import boto3
        from botocore.exceptions import ClientError, NoCredentialsError
    except ImportError:
        logger.error("[AWS] boto3 not installed. Run: pip install boto3")
        return simulate_usage()

    for attempt in range(1, max_retries + 1):
        try:
            logger.info(f"[AWS] Fetching Cost Explorer data: {start_date} → {end_date} (attempt {attempt})")
            session = boto3.Session(
                aws_access_key_id=CONFIG.aws_access_key_id or None,
                aws_secret_access_key=CONFIG.aws_secret_key or None,
                region_name=CONFIG.aws_region,
            )
            client = session.client("ce")

            # Fetch usage quantities grouped by SERVICE
            response = client.get_cost_and_usage(
                TimePeriod={"Start": start_date, "End": end_date},
                Granularity="DAILY",
                Metrics=["UsageQuantity", "UnblendedCost"],
                GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
            )

            records = []
            for result in response["ResultsByTime"]:
                record_date = result["TimePeriod"]["Start"]
                for group in result["Groups"]:
                    raw_name = group["Keys"][0]
                    usage    = float(group["Metrics"]["UsageQuantity"]["Amount"])
                    cost     = float(group["Metrics"]["UnblendedCost"]["Amount"])
                    unit     = group["Metrics"]["UsageQuantity"]["Unit"]

                    # Map to internal service key (best-effort)
                    svc_key  = _map_aws_service_name(raw_name)
                    svc_info = FREE_TIER_LIMITS.get(svc_key)

                    records.append({
                        "date":         record_date,
                        "service_key":  svc_key,
                        "service_name": svc_info.service_name if svc_info else raw_name,
                        "category":     svc_info.category if svc_info else "other",
                        "usage_amount": round(usage, 6),
                        "usage_unit":   unit,
                        "blended_cost": round(cost, 6),
                        "data_source":  "aws-cost-explorer",
                        "fetched_at":   datetime.utcnow().isoformat(),
                    })

            logger.info(f"[AWS] Retrieved {len(records)} records from Cost Explorer")
            return records

        except Exception as exc:
            logger.warning(f"[AWS] Attempt {attempt} failed: {exc}")
            if attempt < max_retries:
                time.sleep(2 ** attempt)
            else:
                logger.error("[AWS] All retries exhausted. Falling back to simulation.")
                return simulate_usage()

    return simulate_usage()


def _map_aws_service_name(aws_name: str) -> str:
    """Fuzzy-map AWS display names to internal service keys."""
    mapping = {
        "Amazon Elastic Compute Cloud": "AmazonEC2",
        "Amazon Simple Storage Service": "AmazonS3",
        "AWS Lambda": "AWSLambda",
        "Amazon Relational Database Service": "AmazonRDS",
        "Amazon DynamoDB": "AmazonDynamoDB",
        "AWS Data Transfer": "AWSDataTransfer",
        "Amazon CloudWatch": "AmazonCloudWatch",
        "AWS CloudTrail": "AWSCloudTrail",
        "Amazon Simple Notification Service": "AmazonSNS",
        "Amazon Simple Queue Service": "AmazonSQS",
    }
    for prefix, key in mapping.items():
        if prefix.lower() in aws_name.lower():
            return key
    # Fallback: strip spaces
    return aws_name.replace(" ", "").replace("-", "")


# ── GCP Billing (Placeholder) ──────────────────────────────────────────────────
def fetch_gcp_billing(project_id: str, dataset: str) -> List[Dict[str, Any]]:
    """
    Placeholder: Fetch GCP usage from Cloud Billing BigQuery export.

    To enable:
    1. Enable Cloud Billing export to BigQuery in GCP Console.
    2. Install: pip install google-cloud-bigquery
    3. Authenticate: gcloud auth application-default login

    Query template:
        SELECT service.description, usage.unit, SUM(usage.amount) as total,
               SUM(cost) as cost, DATE(usage_start_time) as date
        FROM `{project_id}.{dataset}.gcp_billing_export_v1_*`
        WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY 1,2,4
    """
    logger.warning("[GCP] GCP Billing integration not yet configured. Using simulation.")
    return simulate_usage()


# ── Public Interface ───────────────────────────────────────────────────────────
def run_fetch(mode: str = "simulate", days: int = 30) -> int:
    """
    Main entry point for data ingestion.
    Fetches data based on mode and persists to SQLite.

    Returns
    -------
    int  Number of records stored
    """
    db.init_db()

    if mode == "aws":
        end_date   = date.today().isoformat()
        start_date = (date.today() - timedelta(days=days)).isoformat()
        records    = fetch_aws_cost_explorer(start_date, end_date)
    elif mode == "gcp":
        records = fetch_gcp_billing(
            project_id=os.getenv("GCP_PROJECT_ID", ""),
            dataset=os.getenv("GCP_BILLING_DATASET", ""),
        )
    else:
        records = simulate_usage(days)

    count = db.upsert_usage(records)
    stats = db.get_db_stats()
    logger.info(f"[FETCH] DB now has {stats['usage_records']} usage records "
                f"({stats['earliest_date']} → {stats['latest_date']})")
    return count
