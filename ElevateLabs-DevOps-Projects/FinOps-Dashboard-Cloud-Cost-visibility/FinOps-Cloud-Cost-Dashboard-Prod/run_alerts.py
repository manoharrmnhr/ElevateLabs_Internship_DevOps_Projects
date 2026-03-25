#!/usr/bin/env python3
"""
run_alerts.py — CLI for alert evaluation
Usage: python -m scripts.run_alerts
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from src.config import setup_logging, LOGS_DIR
from src.alert_engine import run_alert_engine

def main():
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    setup_logging("INFO", str(LOGS_DIR / "finops.log"))
    run_alert_engine(print_output=True)

if __name__ == "__main__":
    main()
