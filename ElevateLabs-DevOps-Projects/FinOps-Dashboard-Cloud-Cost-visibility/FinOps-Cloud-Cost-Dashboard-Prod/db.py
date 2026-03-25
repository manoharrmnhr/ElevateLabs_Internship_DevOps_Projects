"""
db.py
-----
Production-grade SQLite database layer for the FinOps Dashboard.

Features:
  - Schema versioned migrations (idempotent)
  - Context-manager connection handling
  - Full CRUD + analytics query methods
  - WAL mode for concurrent reads during Grafana queries
"""

import sqlite3
import json
import logging
from contextlib import contextmanager
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Generator, List, Optional, Dict, Any

from src.config import CONFIG, DATA_DIR

logger = logging.getLogger("finops.db")

# ── Schema Version ─────────────────────────────────────────────────────────────
SCHEMA_VERSION = 3

DDL = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS schema_version (
    version     INTEGER PRIMARY KEY,
    applied_at  TEXT NOT NULL
);

-- Raw daily usage per service per day
CREATE TABLE IF NOT EXISTS usage_data (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    date            TEXT    NOT NULL,
    service_key     TEXT    NOT NULL,
    service_name    TEXT    NOT NULL,
    category        TEXT    NOT NULL DEFAULT 'unknown',
    usage_amount    REAL    NOT NULL,
    usage_unit      TEXT    NOT NULL,
    blended_cost    REAL    NOT NULL DEFAULT 0.0,
    data_source     TEXT    NOT NULL DEFAULT 'simulate',
    fetched_at      TEXT    NOT NULL,
    UNIQUE(date, service_key)
);

-- Risk-classified alerts per service per evaluation run
CREATE TABLE IF NOT EXISTS alerts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    evaluated_at    TEXT    NOT NULL,
    service_key     TEXT    NOT NULL,
    service_name    TEXT    NOT NULL,
    month_to_date   REAL    NOT NULL,
    projected_usage REAL    NOT NULL,
    free_tier_limit REAL    NOT NULL,
    usage_unit      TEXT    NOT NULL,
    usage_pct       REAL    NOT NULL,
    risk_level      TEXT    NOT NULL CHECK(risk_level IN ('SAFE','AT-RISK','BREACH')),
    overage_cost    REAL    NOT NULL DEFAULT 0.0,
    message         TEXT    NOT NULL
);

-- Daily rolled-up summary for dashboard stat panels
CREATE TABLE IF NOT EXISTS daily_summary (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    summary_date    TEXT    NOT NULL UNIQUE,
    total_services  INTEGER NOT NULL,
    safe_count      INTEGER NOT NULL,
    at_risk_count   INTEGER NOT NULL,
    breach_count    INTEGER NOT NULL,
    total_overage   REAL    NOT NULL DEFAULT 0.0,
    summary_json    TEXT,
    created_at      TEXT    NOT NULL
);

-- Useful indexes
CREATE INDEX IF NOT EXISTS idx_usage_date         ON usage_data(date);
CREATE INDEX IF NOT EXISTS idx_usage_service_date ON usage_data(service_key, date);
CREATE INDEX IF NOT EXISTS idx_alerts_evaluated   ON alerts(evaluated_at);
CREATE INDEX IF NOT EXISTS idx_alerts_risk        ON alerts(risk_level, evaluated_at);
CREATE INDEX IF NOT EXISTS idx_summary_date       ON daily_summary(summary_date);
"""


# ── Connection Manager ─────────────────────────────────────────────────────────
@contextmanager
def get_conn() -> Generator[sqlite3.Connection, None, None]:
    """Yield an auto-committing, row-factory-enabled SQLite connection."""
    path = Path(CONFIG.db_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path), timeout=30, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# ── Migrations ─────────────────────────────────────────────────────────────────
def init_db() -> None:
    """Apply DDL (idempotent). Records schema version."""
    with get_conn() as conn:
        conn.executescript(DDL)
        cur = conn.execute("SELECT MAX(version) FROM schema_version")
        row = cur.fetchone()
        current = row[0] if row[0] else 0
        if current < SCHEMA_VERSION:
            conn.execute(
                "INSERT INTO schema_version(version, applied_at) VALUES (?,?)",
                (SCHEMA_VERSION, datetime.utcnow().isoformat())
            )
            logger.info(f"[DB] Schema migrated to v{SCHEMA_VERSION}")
        else:
            logger.debug(f"[DB] Schema already at v{current}")
    logger.info(f"[DB] Database ready → {CONFIG.db_path}")


# ── Usage Data ─────────────────────────────────────────────────────────────────
def upsert_usage(records: List[Dict[str, Any]]) -> int:
    """
    Upsert daily usage records.
    Uses INSERT OR REPLACE to handle re-runs on the same day gracefully.
    """
    sql = """
        INSERT OR REPLACE INTO usage_data
            (date, service_key, service_name, category, usage_amount,
             usage_unit, blended_cost, data_source, fetched_at)
        VALUES
            (:date, :service_key, :service_name, :category, :usage_amount,
             :usage_unit, :blended_cost, :data_source, :fetched_at)
    """
    with get_conn() as conn:
        conn.executemany(sql, records)
    logger.info(f"[DB] Upserted {len(records)} usage records")
    return len(records)


def get_month_to_date(month_start: str) -> List[sqlite3.Row]:
    """Aggregate usage per service from month_start to today."""
    sql = """
        SELECT
            service_key,
            service_name,
            category,
            usage_unit,
            SUM(usage_amount)   AS total_usage,
            AVG(usage_amount)   AS avg_daily,
            MAX(usage_amount)   AS peak_daily,
            MIN(usage_amount)   AS min_daily,
            COUNT(DISTINCT date) AS days_tracked
        FROM usage_data
        WHERE date >= ?
        GROUP BY service_key, service_name, category, usage_unit
        ORDER BY service_name
    """
    with get_conn() as conn:
        return conn.execute(sql, (month_start,)).fetchall()


def get_daily_trend(service_key: str, days: int = 14) -> List[sqlite3.Row]:
    """Last N days of daily usage for a specific service."""
    since = (date.today() - timedelta(days=days)).isoformat()
    sql = """
        SELECT date, usage_amount, blended_cost
        FROM usage_data
        WHERE service_key = ? AND date >= ?
        ORDER BY date
    """
    with get_conn() as conn:
        return conn.execute(sql, (service_key, since)).fetchall()


def get_all_services_trend(days: int = 30) -> List[sqlite3.Row]:
    """Daily totals across all services — used for dashboard time-series."""
    since = (date.today() - timedelta(days=days)).isoformat()
    sql = """
        SELECT date, service_name, SUM(usage_amount) AS total
        FROM usage_data
        WHERE date >= ?
        GROUP BY date, service_name
        ORDER BY date, service_name
    """
    with get_conn() as conn:
        return conn.execute(sql, (since,)).fetchall()


# ── Alerts ─────────────────────────────────────────────────────────────────────
def insert_alerts(alerts: List[Dict[str, Any]]) -> None:
    sql = """
        INSERT INTO alerts
            (evaluated_at, service_key, service_name, month_to_date,
             projected_usage, free_tier_limit, usage_unit, usage_pct,
             risk_level, overage_cost, message)
        VALUES
            (:evaluated_at, :service_key, :service_name, :month_to_date,
             :projected_usage, :free_tier_limit, :usage_unit, :usage_pct,
             :risk_level, :overage_cost, :message)
    """
    with get_conn() as conn:
        conn.executemany(sql, alerts)
    logger.info(f"[DB] Inserted {len(alerts)} alert records")


def get_latest_alerts() -> List[sqlite3.Row]:
    """Fetch alert records from the most recent evaluation run."""
    sql = """
        SELECT * FROM alerts
        WHERE evaluated_at = (SELECT MAX(evaluated_at) FROM alerts)
        ORDER BY usage_pct DESC
    """
    with get_conn() as conn:
        return conn.execute(sql).fetchall()


def get_alert_history(days: int = 30) -> List[sqlite3.Row]:
    """Get alert history for trend analysis."""
    since = (datetime.utcnow() - timedelta(days=days)).isoformat()
    sql = """
        SELECT evaluated_at, service_name, risk_level, usage_pct, overage_cost
        FROM alerts
        WHERE evaluated_at >= ?
        ORDER BY evaluated_at DESC
    """
    with get_conn() as conn:
        return conn.execute(sql, (since,)).fetchall()


# ── Daily Summary ──────────────────────────────────────────────────────────────
def upsert_daily_summary(summary: Dict[str, Any]) -> None:
    sql = """
        INSERT INTO daily_summary
            (summary_date, total_services, safe_count, at_risk_count,
             breach_count, total_overage, summary_json, created_at)
        VALUES
            (:summary_date, :total_services, :safe_count, :at_risk_count,
             :breach_count, :total_overage, :summary_json, :created_at)
        ON CONFLICT(summary_date) DO UPDATE SET
            total_services = excluded.total_services,
            safe_count     = excluded.safe_count,
            at_risk_count  = excluded.at_risk_count,
            breach_count   = excluded.breach_count,
            total_overage  = excluded.total_overage,
            summary_json   = excluded.summary_json,
            created_at     = excluded.created_at
    """
    with get_conn() as conn:
        conn.execute(sql, summary)


def get_summary_history(days: int = 30) -> List[sqlite3.Row]:
    since = (date.today() - timedelta(days=days)).isoformat()
    sql = """
        SELECT summary_date, safe_count, at_risk_count, breach_count, total_overage
        FROM daily_summary
        WHERE summary_date >= ?
        ORDER BY summary_date
    """
    with get_conn() as conn:
        return conn.execute(sql, (since,)).fetchall()


def get_db_stats() -> Dict[str, Any]:
    """Health-check style DB statistics."""
    with get_conn() as conn:
        return {
            "usage_records":   conn.execute("SELECT COUNT(*) FROM usage_data").fetchone()[0],
            "alert_records":   conn.execute("SELECT COUNT(*) FROM alerts").fetchone()[0],
            "summary_records": conn.execute("SELECT COUNT(*) FROM daily_summary").fetchone()[0],
            "earliest_date":   conn.execute("SELECT MIN(date) FROM usage_data").fetchone()[0],
            "latest_date":     conn.execute("SELECT MAX(date) FROM usage_data").fetchone()[0],
            "schema_version":  conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0],
        }
