# ☁️ FinOps Dashboard — Cloud Free Tier Usage Tracker

> **Production-grade pipeline to monitor AWS resource consumption, project month-end usage, classify risk in real time, and prevent surprise billing — before the first charge hits.**

<div align="center">

![Python](https://img.shields.io/badge/Python-3.11+-3776AB?logo=python&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-3.x-003B57?logo=sqlite&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-10.x-F46800?logo=grafana&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-Cost_Explorer-FF9900?logo=amazonaws&logoColor=white)
![Tests](https://img.shields.io/badge/Tests-15_passing-brightgreen)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-22c55e)

</div>

---

## 📋 Table of Contents

1. [Overview](#-overview)
2. [Architecture](#-architecture)
3. [Project Structure](#-project-structure)
4. [Services & Free-Tier Limits Tracked](#-services--free-tier-limits-tracked)
5. [Alert & Risk Classification Logic](#-alert--risk-classification-logic)
6. [Prerequisites](#-prerequisites)
7. [Quick Start (5 Minutes)](#-quick-start-5-minutes)
8. [Step-by-Step Execution Guide](#-step-by-step-execution-guide)
9. [Grafana Dashboard Setup](#-grafana-dashboard-setup)
10. [Docker Deployment](#-docker-deployment)
11. [Automated Scheduling](#-automated-scheduling)
12. [Running Tests](#-running-tests)
13. [AWS API Configuration](#-aws-api-configuration)
14. [Configuration Reference](#-configuration-reference)
15. [Extending the Project](#-extending-the-project)
16. [Troubleshooting](#-troubleshooting)

---

## 🎯 Overview

The **FinOps Dashboard** solves a critical problem: AWS Free Tier limits are invisible until billing starts. This project provides:

| Feature | Description |
|---|---|
| **Multi-service monitoring** | 10 AWS services tracked with real free-tier limits |
| **Projection engine** | Projects month-end usage from current-day data |
| **3-tier risk classification** | SAFE / AT-RISK / BREACH with velocity rule |
| **Live Grafana dashboard** | 10 panels: gauges, time-series, tables, stat cards |
| **Weekly text reports** | 6-section report with heatmap, trends, recommendations |
| **Dual data source** | Real AWS Cost Explorer API or realistic simulator |
| **Automated scheduling** | APScheduler daemon for daily fetch + alert evaluation |
| **Docker deployment** | Full docker-compose with Grafana pre-configured |
| **Unit tested** | 15 tests covering classification, cost, projection logic |

**Live output sample (from a real pipeline run):**
```
🔴 S3 Storage        MTD: 7.12 GB  →  Projected: 10.17/5.0 GB  (203.4%)  BREACH  ↑
🔴 Data Transfer Out MTD: 15.4 GB  →  Projected: 22.06/15.0 GB (147.1%)  BREACH  ↑
⚠️  DynamoDB Storage  MTD: 17.1 GB  →  Projected: 24.40/25.0 GB (97.6%)   AT-RISK ↑
✅  SNS Notifications MTD: 413K     →  Projected: 590K/1M      (59.0%)   SAFE    ↑

SUMMARY: 10 services | 2 SAFE | 5 AT-RISK | 3 BREACH | Est. overage: $1.0053/mo
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                                 │
│                                                                     │
│  ┌──────────────────┐   ┌──────────────────┐   ┌───────────────┐  │
│  │ AWS Cost Explorer│   │  GCP Billing API │   │  Simulator    │  │
│  │ (GetCostAndUsage)│   │  (BigQuery export│   │  (Gaussian    │  │
│  │                  │   │   placeholder)   │   │   profiles)   │  │
│  └────────┬─────────┘   └────────┬─────────┘   └──────┬────────┘  │
└───────────┼────────────────────────────────────────────┼───────────┘
            │                                            │
            ▼                                            ▼
┌───────────────────────────────────────────────────────────────────┐
│                    src/fetcher.py                                  │
│  • boto3 Cost Explorer client  • Retry logic (3x backoff)         │
│  • Service name normalization  • Gaussian simulation profiles      │
└───────────────────────────────┬───────────────────────────────────┘
                                │ upsert_usage()
                                ▼
┌───────────────────────────────────────────────────────────────────┐
│                    SQLite (data/finops.db)                         │
│  • usage_data      — daily per-service records (UNIQUE date+key)  │
│  • alerts          — risk-classified evaluation results            │
│  • daily_summary   — aggregated stat panel data                   │
│  • schema_version  — migration tracking                           │
│  WAL mode enabled for concurrent Grafana reads                    │
└─────────────────┬──────────────────────────┬──────────────────────┘
                  │                          │
                  ▼                          ▼
┌─────────────────────────┐   ┌────────────────────────────────────┐
│  src/alert_engine.py    │   │  src/report.py                     │
│  • Projection rule      │   │  • 6-section weekly text report    │
│  • Velocity rule        │   │  • ASCII bar heatmap               │
│  • Trend analysis       │   │  • Remaining budget per service    │
│  • Overage cost calc    │   │  • Prioritized recommendations     │
└─────────────────────────┘   └────────────────────────────────────┘
                  │
                  ▼
┌───────────────────────────────────────────────────────────────────┐
│                         Grafana 10.x                              │
│  SQLite datasource (frser-sqlite-datasource plugin)               │
│  10 panels: Stat cards | Time-series | Gauges | Tables            │
└───────────────────────────────────────────────────────────────────┘
                  │
                  ▼
┌───────────────────────────────────────────────────────────────────┐
│                   src/scheduler.py  (APScheduler)                 │
│  07:00 UTC daily  → run_fetch (incremental, 1 day)               │
│  07:30 UTC daily  → run_alert_engine                              │
│  08:00 UTC Monday → generate_weekly_report                        │
└───────────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
finops-dashboard/
├── src/                          # Core application package
│   ├── __init__.py
│   ├── config.py                 # Free-tier limits, thresholds, typed config
│   ├── db.py                     # SQLite layer: schema migrations, CRUD, analytics
│   ├── fetcher.py                # AWS Cost Explorer + GCP + simulator
│   ├── alert_engine.py           # Risk classification engine (3 rules)
│   ├── report.py                 # Weekly 6-section report generator
│   └── scheduler.py              # APScheduler daemon
├── scripts/                      # CLI entry points
│   ├── run_fetch.py              # python scripts/run_fetch.py --mode simulate
│   ├── run_alerts.py             # python scripts/run_alerts.py
│   └── run_report.py             # python scripts/run_report.py
├── tests/
│   └── test_alert_engine.py      # 15 unit tests (pytest)
├── grafana/
│   └── dashboard.json            # Importable Grafana dashboard (10 panels)
├── docker/
│   ├── Dockerfile                # Multi-stage Python 3.11 slim image
│   └── docker-compose.yml        # Grafana + pipeline + scheduler services
├── data/                         # SQLite database (auto-created, gitignored)
├── reports/                      # Weekly .txt reports (auto-created)
├── logs/                         # Structured logs (auto-created)
├── .env.example                  # Environment variable template
├── requirements.txt
└── README.md
```

---

## 📊 Services & Free-Tier Limits Tracked

| Service | Free Tier Limit | Unit | Category | Over-Limit Rate |
|---|---|---|---|---|
| EC2 t2.micro | 750 hrs/month | Hrs | compute | $0.0116/hr |
| RDS db.t2.micro | 750 hrs/month | Hrs | database | $0.017/hr |
| S3 Storage | 5 GB/month | GB | storage | $0.023/GB |
| Lambda | 1,000,000 reqs/month | Requests | compute | $0.0000002/req |
| DynamoDB | 25 GB/month | GB | database | $0.25/GB |
| Data Transfer Out | 15 GB/month | GB | network | $0.09/GB |
| CloudWatch Metrics | 10 metrics/month | Metrics | ops | $0.30/metric |
| CloudTrail Events | 90,000 events/month | Events | ops | $0.000002/event |
| SNS Notifications | 1,000,000/month | Publishes | ops | $0.0000005/publish |
| SQS Requests | 1,000,000/month | Requests | ops | $0.0000004/req |

---

## 🚨 Alert & Risk Classification Logic

### Rule 1 — Projection Rule (Primary)

```
projection_factor = 30 / day_of_month
projected_usage   = month_to_date_usage × projection_factor
usage_pct         = (projected_usage / free_tier_limit) × 100
```

| Status | Condition | Action |
|---|---|---|
| ✅ **SAFE** | `usage_pct < 70%` | No action needed |
| ⚠️ **AT-RISK** | `70% ≤ usage_pct < 100%` | Monitor & optimize |
| 🔴 **BREACH** | `usage_pct ≥ 100%` | Immediate action — billing may start |

### Rule 2 — Velocity Rule (Escalation)

Even if the primary projection says SAFE, the velocity rule escalates to AT-RISK if:
```
(7-day average daily usage) × remaining_days_in_month > remaining_free_tier_budget
```
This catches services whose usage is suddenly accelerating.

### Rule 3 — Trend Analysis (Informational)

Compares last 7 days vs prior 7 days usage:
- `↑ Accelerating` — >8% growth (high risk)
- `↓ Slowing`      — >8% decline (improving)
- `→ Stable`       — ±8% range

---

## 🛠️ Prerequisites

| Tool | Version | Install |
|---|---|---|
| Python | 3.11+ | [python.org](https://python.org) |
| pip | Latest | Included with Python |
| Git | Any | [git-scm.com](https://git-scm.com) |
| Grafana | 10.x | [grafana.com](https://grafana.com/grafana/download) |
| Docker + Compose | Optional | [docker.com](https://docker.com) |
| AWS Account | Optional | For real API mode |

---

## ⚡ Quick Start (5 Minutes)

```bash
# 1. Clone repository
git clone https://github.com/yourorg/finops-dashboard.git
cd finops-dashboard

# 2. Create virtual environment
python -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Run the full pipeline (simulation mode — no AWS credentials needed)
python scripts/run_fetch.py --mode simulate --days 30
python scripts/run_alerts.py
python scripts/run_report.py

# 5. View your weekly report
cat reports/weekly_report_$(date +%Y-%m-%d).txt
```

You now have:
- `data/finops.db` — populated SQLite database
- `reports/weekly_report_*.txt` — full weekly analysis
- `logs/finops.log` — structured pipeline logs

---

## 📖 Step-by-Step Execution Guide

### Step 1 — Clone and Set Up the Environment

```bash
git clone https://github.com/yourorg/finops-dashboard.git
cd finops-dashboard

# Create isolated Python environment
python -m venv venv

# Activate (choose your OS):
source venv/bin/activate           # macOS/Linux
venv\Scripts\activate              # Windows PowerShell

# Install all dependencies
pip install -r requirements.txt

# Verify installation
python -c "import boto3, apscheduler, reportlab; print('✅ All packages installed')"
```

---

### Step 2 — Configure Environment Variables

```bash
# Copy the example env file
cp .env.example .env
```

Edit `.env`:
```bash
# For simulation mode (default — no credentials needed):
LOG_LEVEL=INFO
FINOPS_DB_PATH=./data/finops.db

# For real AWS mode, add:
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_DEFAULT_REGION=us-east-1
```

---

### Step 3 — Initialize Database and Fetch Usage Data

**Option A — Simulation (recommended for first run):**
```bash
python scripts/run_fetch.py --mode simulate --days 30
```

**Option B — Real AWS Cost Explorer:**
```bash
# Ensure AWS credentials are configured, then:
python scripts/run_fetch.py --mode aws --days 30
```

Expected output:
```
============================================================
  FinOps Dashboard — Data Fetcher
  Mode: SIMULATE  |  Days: 30
============================================================
[DB] Schema migrated to v3
[DB] Database ready → ./data/finops.db
[SIMULATE] Generated 300 records across 10 services
[DB] Upserted 300 usage records
[FETCH] DB now has 300 usage records (2026-01-23 → 2026-02-21)
✅  Done. 300 records stored.
```

What happens internally:
- `db.init_db()` creates the SQLite schema (WAL mode, 4 tables, indexes)
- Simulator applies Gaussian noise + linear growth trends per service
- Records are upserted with `INSERT OR REPLACE` — safe to re-run

---

### Step 4 — Run the Alert Engine

```bash
python scripts/run_alerts.py
```

Expected output (truncated):
```
╔══════════════════════════════════════════════════════════════════╗
║   FinOps Alert Engine  —  Free Tier Risk Classification        ║
║  Day of Month: 21/30  (projection factor: 1.43x)               ║
╚══════════════════════════════════════════════════════════════════╝

🔴 S3 Storage  [storage]
   MTD     : 7.12 GB
   Projected: 10.17 / 5.0 GB  (203.4%)   ← BREACH
   Trend   : ↑ Accelerating (+36.0%)
   Est Cost: $0.11894 overage

⚠️  DynamoDB Storage  [database]
   MTD     : 17.08 GB
   Projected: 24.40 / 25.0 GB  (97.6%)   ← AT-RISK
   Trend   : ↑ Accelerating (+14.0%)

SUMMARY: 10 services | 2 SAFE | 5 AT-RISK | 3 BREACH | Cost: $1.0053
🚨 ACTION REQUIRED: 3 service(s) projected to EXCEED free tier!
```

The engine stores results in `alerts` and `daily_summary` tables for Grafana.

---

### Step 5 — Generate the Weekly Report

```bash
python scripts/run_report.py
```

The report (`reports/weekly_report_YYYY-MM-DD.txt`) contains 6 sections:

1. **Executive Summary** — breach/at-risk counts, total estimated cost
2. **Service Usage Table** — MTD | Projected | Limit | %Used | Trend | Status for all services
3. **Category Breakdown** — risk grouped by compute/storage/network/ops/database
4. **7-Day Daily Heatmap** — ASCII bar chart of daily aggregate volume
5. **Remaining Budget** — per-service free-tier headroom + daily budget
6. **Actionable Recommendations** — ordered by urgency with specific actions

---

### Step 6 — Import the Grafana Dashboard

See [Grafana Dashboard Setup](#-grafana-dashboard-setup) below.

---

### Step 7 — Set Up Automated Scheduling (Production)

```bash
# Start the scheduler daemon (runs daily fetch + alerts + weekly report)
python -m scripts.run_scheduler

# Or run the pipeline once and exit (for CI/CD or cron):
python -m scripts.run_scheduler --run-once
```

---

### Step 8 — Validate the Pipeline End-to-End

```bash
# Run all unit tests
python -m pytest tests/ -v

# Check database health
python -c "
from src import db
stats = db.get_db_stats()
print('DB Health Check:')
for k, v in stats.items():
    print(f'  {k}: {v}')
"
```

---

## 📈 Grafana Dashboard Setup

### Install Grafana

**macOS:**
```bash
brew install grafana && brew services start grafana
```

**Ubuntu/Debian:**
```bash
sudo apt-get install -y adduser libfontconfig1 musl
wget https://dl.grafana.com/oss/release/grafana_10.2.0_amd64.deb
sudo dpkg -i grafana_10.2.0_amd64.deb
sudo systemctl enable --now grafana-server
```

**Docker (easiest):**
```bash
docker run -d -p 3000:3000 \
  -e GF_INSTALL_PLUGINS=frser-sqlite-datasource \
  -v $(pwd)/data:/data/finops \
  --name finops-grafana grafana/grafana:10.2.0
```

Access: `http://localhost:3000` (login: `admin` / `admin`)

### Install the SQLite Datasource Plugin

```bash
# If Grafana is installed locally:
grafana-cli plugins install frser-sqlite-datasource
sudo systemctl restart grafana-server

# Verify plugin installed:
grafana-cli plugins ls | grep sqlite
```

### Add the SQLite Datasource

1. Go to **⚙️ Configuration → Data Sources → Add data source**
2. Search for **SQLite** → select it
3. Set **Path**: `/absolute/path/to/finops-dashboard/data/finops.db`
4. Click **Save & Test** → should see "Database Connected ✓"

### Import the Dashboard

1. Go to **☰ Dashboards → Import**
2. Click **Upload JSON file**
3. Select `grafana/dashboard.json`
4. Select **FinOps SQLite** as the datasource
5. Click **Import**

### Dashboard Panels

| Panel | Type | Data Source Query |
|---|---|---|
| Total Services | Stat | `SELECT total_services FROM daily_summary ORDER BY date DESC LIMIT 1` |
| Safe / At-Risk / Breach | Stat | `SELECT safe_count / at_risk_count / breach_count FROM daily_summary` |
| Estimated Overage Cost | Stat (time-series) | `SELECT summary_date, total_overage FROM daily_summary` |
| Daily Usage Trend | Time Series | `SELECT date, service_name, SUM(usage_amount) FROM usage_data GROUP BY date, service_name` |
| Free Tier Usage % | Gauge | `SELECT service_name, usage_pct FROM alerts WHERE evaluated_at = MAX(evaluated_at)` |
| Current Alert Status | Table | Full alert details with color-coded risk_level column |
| Risk Count Over Time | Time Series | `SELECT summary_date, safe_count, at_risk_count, breach_count FROM daily_summary` |
| Overage Cost Trend | Time Series | `SELECT summary_date, total_overage FROM daily_summary` |
| Alert History | Table | Last 50 alert events |

---

## 🐳 Docker Deployment

### Start Grafana Only

```bash
cd docker
docker compose up -d grafana
# Access at http://localhost:3000 (admin/finops123)
```

### Run Pipeline (One-Shot)

```bash
# Fetch 30 days of simulated data
docker compose run --rm finops

# Run alert evaluation
docker compose run --rm finops python scripts/run_alerts.py

# Generate weekly report
docker compose run --rm finops python scripts/run_report.py
```

### Start Full Automated Stack

```bash
# Start Grafana + automated scheduler
docker compose --profile scheduler up -d

# View logs
docker compose logs -f finops-scheduler
```

### Environment Variables for Docker

```bash
# Create .env from template
cp .env.example .env
# Edit with real AWS credentials if using aws mode
docker compose up -d
```

---

## ⏰ Automated Scheduling

The scheduler (`src/scheduler.py`) uses APScheduler with these cron jobs:

| Job | Schedule (UTC) | Description |
|---|---|---|
| `job_fetch` | Daily 07:00 | Fetch yesterday's usage (incremental, 1 day) |
| `job_alert` | Daily 07:30 | Evaluate risk, update alerts + summary |
| `job_report` | Monday 08:00 | Generate and save weekly report |

**Run as a background service on Linux:**

```bash
# Create systemd service
sudo cat > /etc/systemd/system/finops-scheduler.service << 'EOF'
[Unit]
Description=FinOps Dashboard Scheduler
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/finops-dashboard
ExecStart=/home/ubuntu/finops-dashboard/venv/bin/python -m scripts.run_scheduler
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now finops-scheduler
sudo journalctl -u finops-scheduler -f   # Watch logs
```

**Alternative — cron (simpler):**

```bash
crontab -e
# Add:
0  7 * * *   /path/to/venv/bin/python /path/to/finops-dashboard/scripts/run_fetch.py --mode aws --days 1
30 7 * * *   /path/to/venv/bin/python /path/to/finops-dashboard/scripts/run_alerts.py
0  8 * * 1   /path/to/venv/bin/python /path/to/finops-dashboard/scripts/run_report.py
```

---

## 🧪 Running Tests

```bash
# Run all tests
python -m pytest tests/ -v

# Run with coverage
pip install pytest-cov
python -m pytest tests/ -v --cov=src --cov-report=term-missing

# Run specific test class
python -m pytest tests/test_alert_engine.py::TestClassifyRisk -v
```

**Test Coverage:**

| Test Class | Tests | Coverage Area |
|---|---|---|
| `TestClassifyRisk` | 4 | Risk level boundary conditions |
| `TestComputeOverageCost` | 4 | Overage USD cost calculations |
| `TestProjectionLogic` | 3 | Month-end projection formula |
| `TestFreeTierConfig` | 4 | Service limit config validation |
| **Total** | **15** | **Core business logic** |

---

## 🔐 AWS API Configuration

### IAM Permissions Required

Create an IAM policy with minimum permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "FinOpsCostExplorerReadOnly",
      "Effect": "Allow",
      "Action": [
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "ce:DescribeCostCategoryDefinition"
      ],
      "Resource": "*"
    }
  ]
}
```

### Configure Credentials

**Option A — AWS CLI:**
```bash
aws configure
# AWS Access Key ID: YOUR_KEY
# AWS Secret Access Key: YOUR_SECRET
# Default region: us-east-1
```

**Option B — Environment Variables:**
```bash
export AWS_ACCESS_KEY_ID=YOUR_KEY
export AWS_SECRET_ACCESS_KEY=YOUR_SECRET
export AWS_DEFAULT_REGION=us-east-1
```

**Option C — IAM Role (EC2/ECS recommended for production):**
```bash
# Attach the FinOps IAM policy to the EC2 instance role
# boto3 automatically picks up the instance role — no credentials needed in code
```

---

## ⚙️ Configuration Reference

All settings in `src/config.py` can be overridden via environment variables:

| Variable | Default | Description |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `""` | AWS access key (optional) |
| `AWS_SECRET_ACCESS_KEY` | `""` | AWS secret key (optional) |
| `AWS_DEFAULT_REGION` | `us-east-1` | AWS region |
| `FINOPS_DB_PATH` | `./data/finops.db` | SQLite database path |
| `LOG_LEVEL` | `INFO` | Logging level (DEBUG/INFO/WARNING/ERROR) |

**Risk Thresholds** (edit `src/config.py` → `AlertThresholds`):
```python
@dataclass
class AlertThresholds:
    safe_max:    float = 69.99   # Below this % → SAFE
    at_risk_max: float = 99.99   # Above safe_max, below this → AT-RISK
    # Above at_risk_max → BREACH
```

---

## 🔧 Extending the Project

### Add a New AWS Service

In `src/config.py`, add to `FREE_TIER_LIMITS`:
```python
"AmazonSES": ServiceLimit(
    service_name="SES Emails",
    service_key="AmazonSES",
    monthly_limit=62_000,   # 62,000 emails/month free
    unit="Emails",
    cost_per_unit=0.0001,
    category="ops",
),
```
Add a simulation profile in `src/fetcher.py`:
```python
"AmazonSES": {"base": 1200, "std": 200, "trend": 20},
```

### Add Email/Slack Alerts

In `src/alert_engine.py`, after `db.insert_alerts(db_alerts)`:
```python
from src.notifiers import send_slack_alert, send_email_alert

breach_alerts = [a for a in alerts_out if a["risk_level"] == "BREACH"]
if breach_alerts:
    send_slack_alert(
        webhook_url=os.getenv("SLACK_WEBHOOK_URL"),
        alerts=breach_alerts
    )
```

### Add GCP Billing API

Replace the placeholder in `src/fetcher.py`:
```python
from google.cloud import bigquery

def fetch_gcp_billing(project_id: str, dataset: str):
    client = bigquery.Client()
    query = f"""
        SELECT service.description AS service_key,
               DATE(usage_start_time) AS date,
               SUM(usage.amount) AS usage_amount,
               usage.unit,
               SUM(cost) AS blended_cost
        FROM `{project_id}.{dataset}.gcp_billing_export_v1_*`
        WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
        GROUP BY 1, 2, 4
    """
    return [dict(row) for row in client.query(query)]
```

---

## 🐛 Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `NoCredentialsError` in aws mode | Missing AWS credentials | Run `aws configure` or set env vars |
| `No data for current month` | fetch not run yet | Run `python scripts/run_fetch.py` first |
| Grafana panel shows "No data" | Wrong DB path in datasource | Use **absolute** path to `finops.db` |
| Grafana can't install SQLite plugin | Network restriction | Try offline install from Grafana marketplace |
| `ModuleNotFoundError` | venv not activated | Run `source venv/bin/activate` |
| All services show BREACH day 1 | Simulation data for full month | Normal — 30 days of data projected on day 1 |
| Database locked error | Multiple processes | WAL mode handles this; check for zombie processes |
| Scheduler not running | APScheduler not installed | `pip install apscheduler` |

---

## 📜 License

MIT License — see [LICENSE](LICENSE) for details. Free to use, modify, and distribute.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/slack-notifications`
3. Write tests for your feature: `tests/test_notifiers.py`
4. Ensure tests pass: `python -m pytest tests/ -v`
5. Submit a pull request with description of changes

---

*Built with Python 3.11 · SQLite 3 · Grafana 10 · APScheduler · AWS Cost Explorer API*
*No proprietary tools, no ongoing costs — just open-source FinOps visibility.*
