#!/usr/bin/env python3
"""
run_fetch.py — CLI for data ingestion
Usage: python -m scripts.run_fetch --mode simulate --days 30
"""
import argparse
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from src.config import setup_logging, LOGS_DIR
from src.fetcher import run_fetch

def main():
    parser = argparse.ArgumentParser(description="FinOps Data Fetcher")
    parser.add_argument("--mode",  choices=["simulate","aws","gcp"], default="simulate",
                        help="Data source mode (default: simulate)")
    parser.add_argument("--days",  type=int, default=30,
                        help="Number of historical days to fetch/simulate (default: 30)")
    parser.add_argument("--log-level", default="INFO",
                        help="Logging level (default: INFO)")
    args = parser.parse_args()

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    setup_logging(args.log_level, str(LOGS_DIR / "finops.log"))

    print(f"\n{'='*60}")
    print(f"  FinOps Dashboard — Data Fetcher")
    print(f"  Mode: {args.mode.upper()}  |  Days: {args.days}")
    print(f"{'='*60}\n")

    count = run_fetch(mode=args.mode, days=args.days)
    print(f"\n✅  Done. {count} records stored.\n")

if __name__ == "__main__":
    main()
