"""
scheduler.py
------------
Production scheduler using APScheduler.
Runs the FinOps pipeline automatically on configured intervals.

Schedule:
  - fetch_usage  : Every day at 07:00 UTC
  - alert_engine : Every day at 07:30 UTC
  - weekly_report: Every Monday at 08:00 UTC

Usage:
    python -m scripts.run_scheduler       # start the daemon
    python -m scripts.run_scheduler --run-once   # one-shot execution for testing
"""

import logging
import sys
from datetime import datetime

logger = logging.getLogger("finops.scheduler")

try:
    from apscheduler.schedulers.blocking import BlockingScheduler
    from apscheduler.triggers.cron import CronTrigger
    HAS_APSCHEDULER = True
except ImportError:
    HAS_APSCHEDULER = False

from src.config import CONFIG
from src.fetcher import run_fetch
from src.alert_engine import run_alert_engine
from src.report import generate_weekly_report


def job_fetch():
    logger.info("=== [SCHEDULER] Starting: fetch_usage ===")
    try:
        count = run_fetch(mode="aws", days=1)   # fetch yesterday's data
        logger.info(f"[SCHEDULER] fetch_usage complete: {count} records")
    except Exception as e:
        logger.error(f"[SCHEDULER] fetch_usage FAILED: {e}", exc_info=True)


def job_alert():
    logger.info("=== [SCHEDULER] Starting: alert_engine ===")
    try:
        alerts = run_alert_engine(print_output=False)
        breach = sum(1 for a in alerts if a["risk_level"] == "BREACH")
        at_risk = sum(1 for a in alerts if a["risk_level"] == "AT-RISK")
        logger.info(f"[SCHEDULER] alert_engine complete: {breach} BREACH | {at_risk} AT-RISK")
        if breach > 0:
            logger.warning(f"[SCHEDULER] 🚨 {breach} service(s) in BREACH — notify team!")
    except Exception as e:
        logger.error(f"[SCHEDULER] alert_engine FAILED: {e}", exc_info=True)


def job_report():
    logger.info("=== [SCHEDULER] Starting: weekly_report ===")
    try:
        path = generate_weekly_report()
        logger.info(f"[SCHEDULER] weekly_report saved: {path}")
    except Exception as e:
        logger.error(f"[SCHEDULER] weekly_report FAILED: {e}", exc_info=True)


def run_once():
    """Execute the full pipeline once — useful for testing or CI."""
    print("\n[SCHEDULER] Running full pipeline (one-shot mode)...\n")
    job_fetch()
    job_alert()
    job_report()
    print("\n[SCHEDULER] Pipeline complete.")


def start_scheduler():
    if not HAS_APSCHEDULER:
        logger.error("APScheduler not installed. Run: pip install apscheduler")
        sys.exit(1)

    scheduler = BlockingScheduler(timezone="UTC")

    # Daily fetch at 07:00 UTC
    scheduler.add_job(job_fetch, CronTrigger(hour=7, minute=0),
                      id="fetch_usage", name="Daily Usage Fetch",
                      misfire_grace_time=3600)

    # Daily alert evaluation at 07:30 UTC
    scheduler.add_job(job_alert, CronTrigger(hour=7, minute=30),
                      id="alert_engine", name="Daily Alert Evaluation",
                      misfire_grace_time=3600)

    # Weekly report every Monday at 08:00 UTC
    scheduler.add_job(job_report, CronTrigger(day_of_week="mon", hour=8, minute=0),
                      id="weekly_report", name="Weekly Usage Report",
                      misfire_grace_time=7200)

    logger.info("[SCHEDULER] FinOps pipeline scheduler started (UTC)")
    logger.info("[SCHEDULER] Jobs: fetch=07:00 | alert=07:30 | report=Mon 08:00")

    try:
        scheduler.start()
    except (KeyboardInterrupt, SystemExit):
        logger.info("[SCHEDULER] Scheduler stopped.")
