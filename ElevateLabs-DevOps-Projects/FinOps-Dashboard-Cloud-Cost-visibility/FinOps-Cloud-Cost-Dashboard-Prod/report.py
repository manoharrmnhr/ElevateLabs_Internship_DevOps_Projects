"""
report.py
---------
Production weekly usage report generator for the FinOps Dashboard.

Output Sections
───────────────
  1. Executive Summary    — breach/at-risk/safe counts, total projected cost
  2. Service Usage Table  — MTD, projected, %, trend, status for every service
  3. Category Breakdown   — usage grouped by compute / storage / network / ops / database
  4. 7-Day Daily Heatmap  — ASCII bar chart showing daily aggregate usage volume
  5. Month Projection     — remaining budget per service
  6. Actionable Recommendations — ordered by urgency

Saved as:
  reports/weekly_report_YYYY-MM-DD.txt
"""

import logging
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import List, Dict, Any

from src.config import FREE_TIER_LIMITS, REPORTS_DIR
from src import db

logger = logging.getLogger("finops.report")

# ── Trend Helper ───────────────────────────────────────────────────────────────
def _trend_arrow(service_key: str) -> str:
    rows = db.get_daily_trend(service_key, days=14)
    if len(rows) < 6:
        return "→"
    mid   = len(rows) // 2
    first = sum(r["usage_amount"] for r in rows[:mid]) or 1
    last  = sum(r["usage_amount"] for r in rows[mid:])
    pct   = ((last - first) / first) * 100
    if pct > 8:   return "↑"
    if pct < -8:  return "↓"
    return "→"


def _risk_emoji(pct: float) -> str:
    if pct >= 100: return "🔴"
    if pct >= 70:  return "⚠️ "
    return "✅"


# ── Report Builder ─────────────────────────────────────────────────────────────
def generate_weekly_report(output_path: str = None) -> Path:
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    today      = date.today()
    week_start = today - timedelta(days=6)
    out_path   = Path(output_path) if output_path else \
                 REPORTS_DIR / f"weekly_report_{today.isoformat()}.txt"

    day_of_month  = today.day
    proj_factor   = 30 / max(day_of_month, 1)
    month_start   = today.replace(day=1).isoformat()

    # Pull data
    mtd_rows    = db.get_month_to_date(month_start)
    alerts      = db.get_latest_alerts()
    weekly_rows = db.get_month_to_date((today - timedelta(days=6)).isoformat())

    mtd_map    = {r["service_key"]: dict(r) for r in mtd_rows}
    weekly_map = {r["service_key"]: dict(r) for r in weekly_rows}
    alert_map  = {a["service_key"]: dict(a) for a in alerts}

    lines: List[str] = []
    L = lines.append

    W = 74  # line width

    def rule(char="═"):   L(char * W)
    def hrule(char="─"):  L(char * W)
    def blank():          L("")
    def head(text):       L(f"  {text}")
    def subhead(text):    L(f"\n  ◆ {text}"); hrule("─")

    # ─────────────────────────────────────────────────────────
    # HEADER
    # ─────────────────────────────────────────────────────────
    rule("═")
    L(f"  FINOPS CLOUD COST VISIBILITY — WEEKLY REPORT")
    L(f"  Period   : {week_start}  →  {today}  (week of {week_start.strftime('%B %d, %Y')})")
    L(f"  Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}")
    L(f"  Month Day: {day_of_month}/30  |  Projection Factor: {proj_factor:.2f}x")
    rule("═")

    # ─────────────────────────────────────────────────────────
    # SECTION 1 — EXECUTIVE SUMMARY
    # ─────────────────────────────────────────────────────────
    subhead("EXECUTIVE SUMMARY")
    latest = {a["service_key"]: dict(a) for a in alerts}
    breach_svcs  = [a for a in latest.values() if a["risk_level"] == "BREACH"]
    at_risk_svcs = [a for a in latest.values() if a["risk_level"] == "AT-RISK"]
    safe_svcs    = [a for a in latest.values() if a["risk_level"] == "SAFE"]
    total_cost   = sum(a.get("overage_cost", 0) for a in latest.values())

    L(f"  Total Services Monitored : {len(latest)}")
    L(f"  🔴 BREACH                : {len(breach_svcs)} service(s)  ← BILLING MAY HAVE STARTED")
    L(f"  ⚠️  AT-RISK               : {len(at_risk_svcs)} service(s)  ← Approaching limit")
    L(f"  ✅ SAFE                  : {len(safe_svcs)} service(s)")
    L(f"  Estimated Monthly Overage: ${total_cost:.4f} USD")
    blank()

    if breach_svcs:
        L("  🚨 BREACH SERVICES:")
        for a in sorted(breach_svcs, key=lambda x: -x["usage_pct"]):
            L(f"     • {a['service_name']:<30} {a['usage_pct']:>7.1f}%  |  Est ${a['overage_cost']:.4f}")
    if at_risk_svcs:
        L("  ⚠️  AT-RISK SERVICES:")
        for a in sorted(at_risk_svcs, key=lambda x: -x["usage_pct"]):
            L(f"     • {a['service_name']:<30} {a['usage_pct']:>7.1f}%")

    # ─────────────────────────────────────────────────────────
    # SECTION 2 — SERVICE USAGE TABLE
    # ─────────────────────────────────────────────────────────
    subhead("SERVICE USAGE TABLE  (Month-to-Date vs Free Tier)")
    hdr = (f"  {'Service':<26} {'MTD':>9} {'Projected':>11} {'Limit':>8} "
           f"{'%Used':>7} {'Trend':>5} {'Status':>8}")
    L(hdr)
    hrule("-")

    for service_key, svc in FREE_TIER_LIMITS.items():
        row = mtd_map.get(service_key)
        if not row: continue
        mtd       = row["total_usage"]
        projected = mtd * proj_factor
        pct       = (projected / svc.monthly_limit) * 100
        trend     = _trend_arrow(service_key)
        emoji     = _risk_emoji(pct)
        risk      = "BREACH" if pct >= 100 else ("AT-RISK" if pct >= 70 else "SAFE")
        L(f"  {svc.service_name:<26} {mtd:>9.2f} {projected:>11.2f} {svc.monthly_limit:>8} "
          f"{pct:>6.1f}% {trend:>5}   {emoji} {risk}")

    blank()
    L("  Note: MTD = Month-to-Date actual  |  Projected = estimated month-end usage")

    # ─────────────────────────────────────────────────────────
    # SECTION 3 — CATEGORY BREAKDOWN
    # ─────────────────────────────────────────────────────────
    subhead("CATEGORY BREAKDOWN")
    categories: Dict[str, Dict] = {}
    for service_key, svc in FREE_TIER_LIMITS.items():
        row = mtd_map.get(service_key)
        if not row: continue
        cat = svc.category
        if cat not in categories:
            categories[cat] = {"services": 0, "breach": 0, "at_risk": 0, "cost": 0.0}
        alert = alert_map.get(service_key, {})
        categories[cat]["services"] += 1
        if alert.get("risk_level") == "BREACH":  categories[cat]["breach"] += 1
        if alert.get("risk_level") == "AT-RISK": categories[cat]["at_risk"] += 1
        categories[cat]["cost"] += alert.get("overage_cost", 0.0)

    L(f"  {'Category':<14} {'Services':>9} {'Breach':>8} {'At-Risk':>9} {'Est Cost':>10}")
    hrule("-")
    for cat, data in sorted(categories.items()):
        L(f"  {cat:<14} {data['services']:>9} {data['breach']:>8} {data['at_risk']:>9} "
          f"${data['cost']:>9.4f}")

    # ─────────────────────────────────────────────────────────
    # SECTION 4 — 7-DAY DAILY HEATMAP
    # ─────────────────────────────────────────────────────────
    subhead("7-DAY DAILY USAGE HEATMAP  (All Services Combined)")
    L(f"  {'Date':<12} {'Bar (scaled)':<42} {'Total Units':>12}")
    hrule("-")

    from src import db as _db
    since = (today - timedelta(days=6)).isoformat()
    with _db.get_conn() as conn:
        rows = conn.execute("""
            SELECT date, SUM(usage_amount) as total
            FROM usage_data WHERE date >= ? GROUP BY date ORDER BY date
        """, (since,)).fetchall()

    max_val = max((r["total"] for r in rows), default=1)
    for r in rows:
        bar_len = int((r["total"] / max_val) * 40)
        bar     = "█" * bar_len + "░" * (40 - bar_len)
        L(f"  {r['date']:<12} {bar}  {r['total']:>12,.1f}")

    # ─────────────────────────────────────────────────────────
    # SECTION 5 — REMAINING MONTHLY BUDGET
    # ─────────────────────────────────────────────────────────
    subhead("REMAINING FREE-TIER BUDGET  (Days left in month)")
    days_left = 30 - day_of_month
    L(f"  Days remaining in billing month: {days_left}")
    blank()
    L(f"  {'Service':<28} {'Used MTD':>10} {'Limit':>8} {'Remaining':>11} {'Daily Budget':>13}")
    hrule("-")
    for service_key, svc in FREE_TIER_LIMITS.items():
        row = mtd_map.get(service_key)
        if not row: continue
        mtd       = row["total_usage"]
        remaining = max(0, svc.monthly_limit - mtd)
        daily_bud = remaining / max(days_left, 1)
        flag      = "⚠️" if remaining < daily_bud * 3 else ""
        L(f"  {svc.service_name:<28} {mtd:>10.2f} {svc.monthly_limit:>8} "
          f"{remaining:>11.2f} {daily_bud:>13.3f} {flag}")

    # ─────────────────────────────────────────────────────────
    # SECTION 6 — RECOMMENDATIONS
    # ─────────────────────────────────────────────────────────
    subhead("ACTIONABLE RECOMMENDATIONS  (Ordered by Urgency)")

    recs: List[tuple] = []   # (urgency: int, text: str)
    for service_key, svc in FREE_TIER_LIMITS.items():
        row = mtd_map.get(service_key)
        if not row: continue
        mtd       = row["total_usage"]
        projected = mtd * proj_factor
        pct       = (projected / svc.monthly_limit) * 100

        if pct >= 100:
            recs.append((0, f"🔴 [{svc.category.upper()}] {svc.service_name}: BREACH ({pct:.1f}%). "
                            f"Projected {projected:.1f} {svc.unit} > limit {svc.monthly_limit}. "
                            f"STOP or right-size immediately."))
        elif pct >= 90:
            recs.append((1, f"🟠 [{svc.category.upper()}] {svc.service_name}: CRITICAL ({pct:.1f}%). "
                            f"Reduce usage by {projected - svc.monthly_limit * 0.85:.1f} {svc.unit}/mo within 48hrs."))
        elif pct >= 70:
            recs.append((2, f"⚠️  [{svc.category.upper()}] {svc.service_name}: AT-RISK ({pct:.1f}%). "
                            f"Monitor daily. Consider S3 lifecycle rules / Lambda optimization."))
        else:
            recs.append((3, f"✅ [{svc.category.upper()}] {svc.service_name}: SAFE ({pct:.1f}%). No action needed."))

    for _, text in sorted(recs):
        L(f"  {text}")

    # ─────────────────────────────────────────────────────────
    # FOOTER
    # ─────────────────────────────────────────────────────────
    blank()
    rule("═")
    L("  FinOps Dashboard  |  github.com/yourorg/finops-dashboard")
    L(f"  Report auto-generated: {datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}")
    rule("═")

    report_text = "\n".join(lines)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(report_text, encoding="utf-8")
    logger.info(f"[REPORT] Weekly report saved → {out_path}")
    print(report_text)
    return out_path
