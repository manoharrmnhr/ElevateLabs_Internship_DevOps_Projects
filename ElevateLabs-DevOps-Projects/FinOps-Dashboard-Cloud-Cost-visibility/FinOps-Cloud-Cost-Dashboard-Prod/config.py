"""
config.py
---------
Central configuration for the FinOps Dashboard.
Loads from config.yaml and .env overrides.

Production-grade: typed dataclasses, validation, environment override support.
"""

import os
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional

# ── Logging Setup ──────────────────────────────────────────────────────────────
LOG_FORMAT = "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
LOG_DATE   = "%Y-%m-%d %H:%M:%S"

def setup_logging(level: str = "INFO", log_file: Optional[str] = None) -> logging.Logger:
    handlers = [logging.StreamHandler()]
    if log_file:
        Path(log_file).parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_file))
    logging.basicConfig(level=getattr(logging, level.upper(), logging.INFO),
                        format=LOG_FORMAT, datefmt=LOG_DATE, handlers=handlers)
    return logging.getLogger("finops")


# ── Paths ──────────────────────────────────────────────────────────────────────
BASE_DIR    = Path(__file__).parent.parent
DATA_DIR    = BASE_DIR / "data"
REPORTS_DIR = BASE_DIR / "reports"
LOGS_DIR    = BASE_DIR / "logs"
DB_PATH     = DATA_DIR / "finops.db"


# ── AWS Free-Tier Limits (per calendar month) ──────────────────────────────────
@dataclass
class ServiceLimit:
    service_name:  str
    service_key:   str
    monthly_limit: float
    unit:          str
    cost_per_unit: float   # USD charged per unit ABOVE the free tier
    category:      str     # compute | storage | network | database | ops


FREE_TIER_LIMITS: Dict[str, ServiceLimit] = {
    "AmazonEC2": ServiceLimit(
        service_name="EC2 t2.micro",
        service_key="AmazonEC2",
        monthly_limit=750,
        unit="Hrs",
        cost_per_unit=0.0116,
        category="compute",
    ),
    "AmazonRDS": ServiceLimit(
        service_name="RDS db.t2.micro",
        service_key="AmazonRDS",
        monthly_limit=750,
        unit="Hrs",
        cost_per_unit=0.017,
        category="database",
    ),
    "AmazonS3": ServiceLimit(
        service_name="S3 Storage",
        service_key="AmazonS3",
        monthly_limit=5.0,
        unit="GB",
        cost_per_unit=0.023,
        category="storage",
    ),
    "AWSLambda": ServiceLimit(
        service_name="Lambda Requests",
        service_key="AWSLambda",
        monthly_limit=1_000_000,
        unit="Requests",
        cost_per_unit=0.0000002,
        category="compute",
    ),
    "AmazonDynamoDB": ServiceLimit(
        service_name="DynamoDB Storage",
        service_key="AmazonDynamoDB",
        monthly_limit=25.0,
        unit="GB",
        cost_per_unit=0.25,
        category="database",
    ),
    "AWSDataTransfer": ServiceLimit(
        service_name="Data Transfer Out",
        service_key="AWSDataTransfer",
        monthly_limit=15.0,
        unit="GB",
        cost_per_unit=0.09,
        category="network",
    ),
    "AmazonCloudWatch": ServiceLimit(
        service_name="CloudWatch Metrics",
        service_key="AmazonCloudWatch",
        monthly_limit=10,
        unit="Metrics",
        cost_per_unit=0.30,
        category="ops",
    ),
    "AWSCloudTrail": ServiceLimit(
        service_name="CloudTrail Events",
        service_key="AWSCloudTrail",
        monthly_limit=90_000,
        unit="Events",
        cost_per_unit=0.000002,
        category="ops",
    ),
    "AmazonSNS": ServiceLimit(
        service_name="SNS Notifications",
        service_key="AmazonSNS",
        monthly_limit=1_000_000,
        unit="Publishes",
        cost_per_unit=0.0000005,
        category="ops",
    ),
    "AmazonSQS": ServiceLimit(
        service_name="SQS Requests",
        service_key="AmazonSQS",
        monthly_limit=1_000_000,
        unit="Requests",
        cost_per_unit=0.0000004,
        category="ops",
    ),
}


# ── Risk Thresholds ────────────────────────────────────────────────────────────
@dataclass
class AlertThresholds:
    safe_max:     float = 69.99   # 0–69% → SAFE
    at_risk_max:  float = 99.99   # 70–99% → AT-RISK
    # ≥100% → BREACH


THRESHOLDS = AlertThresholds()


# ── App Config ─────────────────────────────────────────────────────────────────
@dataclass
class AppConfig:
    # AWS
    aws_region:          str  = "us-east-1"
    aws_access_key_id:   str  = ""
    aws_secret_key:      str  = ""

    # Database
    db_path:             str  = str(DB_PATH)

    # Alerting
    alert_safe_pct:      float = 70.0
    alert_at_risk_pct:   float = 100.0

    # Scheduler
    fetch_cron_hour:     int   = 7
    fetch_cron_minute:   int   = 0
    alert_cron_hour:     int   = 7
    alert_cron_minute:   int   = 30
    report_cron_weekday: str   = "mon"

    # Logging
    log_level:           str   = "INFO"
    log_file:            str   = str(LOGS_DIR / "finops.log")

    # Simulation
    simulate_days:       int   = 30


def load_config() -> AppConfig:
    """Load config from environment variables (12-factor app style)."""
    cfg = AppConfig()
    cfg.aws_region        = os.getenv("AWS_DEFAULT_REGION", cfg.aws_region)
    cfg.aws_access_key_id = os.getenv("AWS_ACCESS_KEY_ID", cfg.aws_access_key_id)
    cfg.aws_secret_key    = os.getenv("AWS_SECRET_ACCESS_KEY", cfg.aws_secret_key)
    cfg.db_path           = os.getenv("FINOPS_DB_PATH", cfg.db_path)
    cfg.log_level         = os.getenv("LOG_LEVEL", cfg.log_level)
    return cfg


CONFIG = load_config()
