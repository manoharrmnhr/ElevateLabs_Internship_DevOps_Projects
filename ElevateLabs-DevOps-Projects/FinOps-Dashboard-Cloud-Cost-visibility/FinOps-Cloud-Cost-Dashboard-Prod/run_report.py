#!/usr/bin/env python3
"""
run_report.py — CLI for weekly report generation
Usage: python -m scripts.run_report
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from src.config import setup_logging, LOGS_DIR
from src.report import generate_weekly_report

def main():
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    setup_logging("INFO", str(LOGS_DIR / "finops.log"))
    path = generate_weekly_report()
    print(f"\n✅  Report saved to: {path}\n")

if __name__ == "__main__":
    main()
