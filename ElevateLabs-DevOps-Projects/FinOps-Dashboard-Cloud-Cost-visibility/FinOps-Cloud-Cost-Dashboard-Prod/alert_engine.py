"""
alert_engine.py
---------------
Production-grade alert engine for the FinOps Dashboard.

Risk Classification Rules
─────────────────────────
1. PROJECTION RULE (primary):
   project usage to month-end: projected = (mtd_usage / current_day) × 30
   - SAFE     → projected < 70% of limit
   - AT-RISK  → 70% ≤ projected < 100% of limit
   - BREACH   → projected ≥ 100% of limit (billing expected)

2. VELOCITY RULE (secondary):
   If 7-day average daily usage × remaining_days_in_month > remaining_limit,
   escalate SAFE → AT-RISK even if current projection looks safe.

3. TREND RULE (informational):
   Compare last 7 days vs prior 7 days. Annotate as ↑ Accelerating / ↓ Slowing / → Stable.

Outputs
───────
  - Console rich table
  - SQLite alerts table
  - SQLite daily_summary table
  - Returns structured alert dicts for downstream consumers (email, Slack, etc.)
"""

import json
import logging
from datetime import date, datetime, timedelta
from typing import List, Dict, Any, Tuple

from src.config import FREE_TIER_LIMITS, THRESHOLDS, ServiceLimit
from src import db

logger = logging.getLogger("finops.alert_engine")


# ── Risk Classification ────────────────────────────────────────────────────────
def classify_risk(usage_pct: float) -> str:
    if usage_pct >= 100.0:
        return "BREACH"
    elif usage_pct >= THRESHOLDS.safe_max + 0.01:
        return "AT-RISK"
    return "SAFE"


def compute_overage_cost(svc: ServiceLimit, projected_usage: float) -> float:
    """Estimate USD cost for projected overage above the free tier."""
    overage = max(0.0, projected_usage - svc.monthly_limit)
    return round(overage * svc.cost_per_unit, 6)


def compute_velocity_risk(service_key: str, remaining_days: int, remaining_limit: float) -> bool:
    """
    Returns True if recent 7-day velocity projects a limit breach
    even when the primary projection rule says SAFE.
    """
    rows = db.get_daily_trend(service_key, days=7)
    if not rows:
        return False
    recent_avg = sum(r["usage_amount"] for r in rows) / len(rows)
    velocity_projected = recent_avg * remaining_days
    return velocity_projected > remaining_limit


def compute_trend(service_key: str) -> str:
    """Compare last 7 days vs prior 7 days. Returns trend symbol + label."""
    rows = db.get_daily_trend(service_key, days=14)
    if len(rows) < 6:
        return "→ Stable"
    mid   = len(rows) // 2
    first = sum(r["usage_amount"] for r in rows[:mid])
    last  = sum(r["usage_amount"] for r in rows[mid:])
    if first == 0:
        return "→ Stable"
    change_pct = ((last - first) / first) * 100
    if change_pct > 8:
        return f"↑ Accelerating (+{change_pct:.1f}%)"
    elif change_pct < -8:
        return f"↓ Slowing ({change_pct:.1f}%)"
    return f"→ Stable ({change_pct:+.1f}%)"


# ── Main Engine ────────────────────────────────────────────────────────────────
def run_alert_engine(print_output: bool = True) -> List[Dict[str, Any]]:
    """
    Evaluate all tracked services against free-tier limits.

    Returns list of alert dicts for each service.
    """
    today        = date.today()
    month_start  = today.replace(day=1).isoformat()
    day_of_month = today.day
    days_in_month = 30   # approximate; accurate enough for projection
    remaining_days = max(1, days_in_month - day_of_month)
    proj_factor   = days_in_month / day_of_month
    evaluated_at  = datetime.utcnow().isoformat()

    mtd_rows = db.get_month_to_date(month_start)
    if not mtd_rows:
        logger.warning("[ALERT] No usage data found for current month. Run fetcher first.")
        return []

    # Build lookup by service_key
    mtd_map: Dict[str, Any] = {r["service_key"]: dict(r) for r in mtd_rows}

    alerts_out: List[Dict[str, Any]] = []
    safe_count = at_risk_count = breach_count = 0
    total_overage = 0.0

    if print_output:
        _print_header(today, day_of_month, proj_factor)

    for service_key, svc in FREE_TIER_LIMITS.items():
        row = mtd_map.get(service_key)
        if not row:
            logger.debug(f"[ALERT] No MTD data for {service_key} — skipping")
            continue

        mtd_usage     = row["total_usage"]
        projected     = mtd_usage * proj_factor
        usage_pct     = (projected / svc.monthly_limit) * 100
        risk          = classify_risk(usage_pct)
        overage_cost  = compute_overage_cost(svc, projected)
        trend         = compute_trend(service_key)
        total_overage += overage_cost

        # Velocity escalation: override SAFE → AT-RISK if velocity says breach incoming
        velocity_flag = False
        if risk == "SAFE":
            remaining_limit = svc.monthly_limit - mtd_usage
            if remaining_limit > 0 and compute_velocity_risk(service_key, remaining_days, remaining_limit):
                risk          = "AT-RISK"
                velocity_flag = True

        # Update counters
        if risk == "SAFE":    safe_count    += 1
        elif risk == "AT-RISK": at_risk_count += 1
        else:                 breach_count  += 1

        message = _build_message(svc, mtd_usage, projected, usage_pct, risk, overage_cost, velocity_flag)

        alert = {
            "evaluated_at":   evaluated_at,
            "service_key":    service_key,
            "service_name":   svc.service_name,
            "month_to_date":  round(mtd_usage, 4),
            "projected_usage": round(projected, 4),
            "free_tier_limit": svc.monthly_limit,
            "usage_unit":     svc.unit,
            "usage_pct":      round(usage_pct, 2),
            "risk_level":     risk,
            "overage_cost":   overage_cost,
            "message":        message,
            "_trend":         trend,
            "_velocity_flag": velocity_flag,
            "_category":      svc.category,
        }
        alerts_out.append(alert)

        if print_output:
            _print_service_row(alert, svc, trend, velocity_flag)

    # Persist to DB (strip internal _ keys)
    db_alerts = [{k: v for k, v in a.items() if not k.startswith("_")} for a in alerts_out]
    db.insert_alerts(db_alerts)

    # Daily summary
    summary = {
        "summary_date":  today.isoformat(),
        "total_services": len(alerts_out),
        "safe_count":    safe_count,
        "at_risk_count": at_risk_count,
        "breach_count":  breach_count,
        "total_overage": round(total_overage, 6),
        "summary_json":  json.dumps([
            {k: v for k, v in a.items() if not k.startswith("_")}
            for a in alerts_out
        ]),
        "created_at":    evaluated_at,
    }
    db.upsert_daily_summary(summary)

    if print_output:
        _print_summary(len(alerts_out), safe_count, at_risk_count, breach_count, total_overage)

    logger.info(f"[ALERT] Evaluation complete: {safe_count} SAFE | {at_risk_count} AT-RISK | {breach_count} BREACH")
    return alerts_out


# ── Output Formatters ──────────────────────────────────────────────────────────
def _print_header(today: date, day: int, proj_factor: float) -> None:
    print()
    print("╔" + "═" * 66 + "╗")
    print("║   FinOps Alert Engine  —  Free Tier Risk Classification        ║")
    print("╠" + "═" * 66 + "╣")
    print(f"║  Evaluation Date : {today}                                     ║")
    print(f"║  Day of Month    : {day}/30  (projection factor: {proj_factor:.2f}x)               ║")
    print(f"║  Thresholds      : SAFE <70%  |  AT-RISK 70–99%  |  BREACH ≥100%  ║")
    print("╚" + "═" * 66 + "╝")


def _build_message(svc: ServiceLimit, mtd: float, projected: float,
                   pct: float, risk: str, cost: float, velocity: bool) -> str:
    base = (
        f"{svc.service_name} is {risk}. "
        f"MTD: {mtd:.2f} {svc.unit} | "
        f"Projected month-end: {projected:.1f}/{svc.monthly_limit} {svc.unit} "
        f"({pct:.1f}% of free tier)."
    )
    if cost > 0:
        base += f" Est. overage: ${cost:.4f}."
    if velocity:
        base += " [Velocity Rule triggered: recent growth rate may exceed limit ahead of projection.]"
    return base


def _print_service_row(alert: Dict, svc: ServiceLimit, trend: str, velocity: bool) -> None:
    icons = {"SAFE": "✅", "AT-RISK": "⚠️ ", "BREACH": "🔴"}
    icon  = icons.get(alert["risk_level"], "❓")
    pct   = alert["usage_pct"]
    bar   = "█" * int(min(pct, 100) / 5) + "░" * max(0, 20 - int(min(pct, 100) / 5))
    vflag = "  [VELOCITY]" if velocity else ""

    print(f"\n{icon} {alert['service_name']}  [{alert['_category']}]{vflag}")
    print(f"   MTD      : {alert['month_to_date']:.3f} {alert['usage_unit']}")
    print(f"   Projected: {alert['projected_usage']:.2f} / {alert['free_tier_limit']} "
          f"{alert['usage_unit']}  ({pct:.1f}%)")
    print(f"   Progress : [{bar}]  {alert['risk_level']}")
    print(f"   Trend    : {trend}")
    if alert["overage_cost"] > 0:
        print(f"   Est Cost : ${alert['overage_cost']:.5f} overage")


def _print_summary(total: int, safe: int, at_risk: int, breach: int, cost: float) -> None:
    print()
    print("┌" + "─" * 66 + "┐")
    print(f"│  SUMMARY: {total} services evaluated                              │")
    print(f"│  ✅ SAFE: {safe:>3}  │  ⚠️  AT-RISK: {at_risk:>3}  │  🔴 BREACH: {breach:>3}  │  Cost: ${cost:.4f}  │")
    print("└" + "─" * 66 + "┘")

    if breach > 0:
        print(f"\n🚨 ACTION REQUIRED: {breach} service(s) projected to EXCEED free tier!")
        print("   Immediate action required to prevent unexpected AWS charges.\n")
    elif at_risk > 0:
        print(f"\n⚠️  WARNING: {at_risk} service(s) approaching free tier limits.")
        print("   Review usage and optimize before month-end.\n")
    else:
        print("\n✅ All services within safe free-tier thresholds. No action required.\n")
