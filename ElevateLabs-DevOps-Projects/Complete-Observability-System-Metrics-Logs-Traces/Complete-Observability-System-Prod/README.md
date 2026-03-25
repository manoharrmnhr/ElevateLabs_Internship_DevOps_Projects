# 🔭 Complete Observability System

> **Production-grade monitoring stack** integrating Metrics (Prometheus), Logs (Loki), and Traces (Jaeger) — visualized in Grafana with a containerized Python microservice and automated load generation.

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://docs.docker.com/compose/)
[![Prometheus](https://img.shields.io/badge/Prometheus-2.51-E6522C?logo=prometheus)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana-10.4-F46800?logo=grafana)](https://grafana.com/)
[![Loki](https://img.shields.io/badge/Loki-3.0-F46800?logo=grafana)](https://grafana.com/oss/loki/)
[![Jaeger](https://img.shields.io/badge/Jaeger-1.57-66CFE3)](https://www.jaegertracing.io/)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python)](https://python.org/)

---

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     OBSERVABILITY STACK                         │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │  Sample App  │───▶│  Prometheus  │───▶│                  │  │
│  │  (Flask)     │    │  (Metrics)   │    │    G R A F A N A │  │
│  │              │───▶│  Loki        │───▶│                  │  │
│  │  /metrics    │    │  (Logs)      │    │  • Dashboards    │  │
│  │  /api/*      │───▶│  Jaeger      │───▶│  • Alerts        │  │
│  └──────────────┘    │  (Traces)    │    │  • Explore       │  │
│         ▲            └──────────────┘    └──────────────────┘  │
│  ┌──────┴───────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │ Load         │    │  Node        │    │  cAdvisor        │  │
│  │ Generator    │    │  Exporter    │    │  (Containers)    │  │
│  └──────────────┘    └──────────────┘    └──────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### The Three Pillars of Observability

| Pillar | Tool | Port | Purpose |
|--------|------|------|---------|
| **Metrics** | Prometheus + Node Exporter + cAdvisor | 9090, 9100, 8080 | Time-series performance data |
| **Logs** | Loki + Promtail | 3100, 9080 | Centralized structured log aggregation |
| **Traces** | Jaeger | 16686 | Distributed request tracing |
| **Visualization** | Grafana | 3000 | Unified dashboards & alerting |
| **App** | Flask (Python) | 5000 | Sample microservice with full instrumentation |

---

## 📁 Project Structure

```
observability-system/
├── docker-compose.yml              # Main orchestration file
├── app/
│   ├── app.py                      # Flask app (metrics + logs + traces)
│   ├── requirements.txt            # Python dependencies
│   ├── Dockerfile                  # App container definition
│   ├── Dockerfile.loadgen          # Load generator container
│   └── load_generator.py           # Traffic simulation script
├── prometheus/
│   ├── prometheus.yml              # Scrape configs + targets
│   └── alert_rules.yml             # Alerting rules (error rate, latency, uptime)
├── grafana/
│   ├── dashboards/
│   │   └── observability-dashboard.json  # Pre-built dashboard
│   └── provisioning/
│       ├── datasources/
│       │   └── datasources.yml     # Prometheus, Loki, Jaeger auto-config
│       └── dashboards/
│           └── dashboards.yml      # Dashboard auto-provisioning
├── loki/
│   └── loki-config.yml             # Loki storage and ingestion config
├── promtail/
│   └── promtail-config.yml         # Log scraping and label config
└── docs/
    └── sample-logs.txt             # Annotated sample log output
```

---

## 🚀 Quick Start

### Prerequisites

| Requirement | Minimum Version | Check Command |
|-------------|----------------|---------------|
| Docker | 24.0+ | `docker --version` |
| Docker Compose | 2.20+ | `docker compose version` |
| RAM | 4 GB free | `free -h` |
| Disk | 3 GB free | `df -h` |

### Step 1 — Clone the Repository

```bash
git clone https://github.com/<your-username>/observability-system.git
cd observability-system
```

### Step 2 — Start the Stack

```bash
# Start all services (builds app image on first run)
docker compose up -d

# Watch startup logs
docker compose logs -f --tail=50
```

> **Tip:** First startup takes ~60–90 seconds for image pulls and service initialization.

### Step 3 — Verify All Services Are Running

```bash
docker compose ps
```

Expected output — all services should show `healthy` or `running`:

```
NAME              IMAGE                           STATUS          PORTS
sample-app        observability-system-app        healthy         0.0.0.0:5000->5000/tcp
load-generator    observability-system-loadgen    running
prometheus        prom/prometheus:v2.51.2         healthy         0.0.0.0:9090->9090/tcp
grafana           grafana/grafana:10.4.2          healthy         0.0.0.0:3000->3000/tcp
loki              grafana/loki:3.0.0              healthy         0.0.0.0:3100->3100/tcp
promtail          grafana/promtail:3.0.0          running         0.0.0.0:9080->9080/tcp
jaeger            jaegertracing/all-in-one:1.57   healthy         0.0.0.0:16686->16686/tcp
node-exporter     prom/node-exporter:v1.8.0       running         0.0.0.0:9100->9100/tcp
cadvisor          gcr.io/cadvisor/cadvisor:v0.49  running         0.0.0.0:8080->8080/tcp
```

---

## 🌐 Service Access URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** (main UI) | http://localhost:3000 | admin / observability123 |
| **Sample App** | http://localhost:5000 | — |
| **Prometheus** | http://localhost:9090 | — |
| **Jaeger UI** | http://localhost:16686 | — |
| **Loki** | http://localhost:3100 | — |
| **Promtail** | http://localhost:9080 | — |
| **Node Exporter** | http://localhost:9100/metrics | — |
| **cAdvisor** | http://localhost:8080 | — |

---

## 📊 Using Grafana Dashboards

### Opening the Dashboard

1. Navigate to **http://localhost:3000**
2. Login: `admin` / `observability123`
3. Click **Dashboards** → **Observability** folder
4. Open **"Complete Observability Dashboard"**

### Dashboard Sections

| Section | Panels Included |
|---------|----------------|
| 🟢 **Service Health** | App status, request rate, error %, p95 latency, active requests |
| 📊 **HTTP Traffic** | Request rate by endpoint, latency percentiles (p50/p90/p95/p99), status code distribution |
| 📝 **Application Logs** | Live log stream, log volume by level (ERROR/WARN/INFO/DEBUG) |
| 🏗️ **Infrastructure** | CPU usage, memory usage, container CPU |
| 💼 **Business Metrics** | Orders by status (pie), order rate over time |

### Exploring Logs in Loki

Navigate to **Explore** → select **Loki** datasource:

```logql
# All logs from the app
{service="sample-app"}

# Only errors and warnings
{service="sample-app"} | json | level =~ "ERROR|WARNING"

# Requests slower than 500ms
{service="sample-app"} | json | latency_ms > 500

# Filter by trace ID (cross-signal correlation)
{service="sample-app"} | json | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"

# Count errors per minute
sum(count_over_time({service="sample-app"} | json | level="ERROR" [1m]))
```

### Exploring Traces in Jaeger

1. Open **http://localhost:16686**
2. Select **Service**: `sample-app`
3. Click **Find Traces**
4. Click any trace to see the full span waterfall

**Trace-to-Log correlation** (when configured in Grafana):
- Click a trace ID in Grafana → Jaeger opens the trace
- Click a log line with `trace_id` → Jaeger opens the matching trace

### Querying Prometheus Metrics

Navigate to **Explore** → select **Prometheus**:

```promql
# Request rate (per second) over last 5 minutes
rate(http_requests_total[5m])

# Error percentage
100 * sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# p95 latency in milliseconds
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)) * 1000

# Latency by endpoint
histogram_quantile(0.95, sum by (le, endpoint) (rate(http_request_duration_seconds_bucket[5m])))

# DB query latency p95
histogram_quantile(0.95, sum by (le, operation) (rate(db_query_duration_seconds_bucket[5m])))

# Orders confirmed vs failed
sum by (status) (rate(business_orders_total[5m]))
```

---

## 🧪 Testing & Simulation

### Manual API Testing

```bash
# Basic health check
curl http://localhost:5000/health

# List all endpoints
curl http://localhost:5000/

# Get users
curl http://localhost:5000/api/users

# Get specific user (valid)
curl http://localhost:5000/api/users/42

# Get specific user (triggers 404)
curl http://localhost:5000/api/users/150

# Create an order
curl -X POST http://localhost:5000/api/orders \
  -H "Content-Type: application/json" \
  -d '{"item": "widget", "quantity": 3}'

# Trigger slow endpoint (~0.5–3s)
curl http://localhost:5000/api/slow

# Trigger 500 error
curl http://localhost:5000/api/error

# View raw Prometheus metrics
curl http://localhost:5000/metrics
```

### Generating Load Spikes

```bash
# Burst of 100 concurrent requests
for i in $(seq 1 100); do
  curl -s http://localhost:5000/api/users &
done; wait

# Sustained error rate spike
for i in $(seq 1 50); do
  curl -s http://localhost:5000/api/error &
  sleep 0.1
done

# Slow endpoint stress test
for i in $(seq 1 10); do
  curl -s http://localhost:5000/api/slow &
done; wait
```

---

## 🚨 Alert Rules

Alerts defined in `prometheus/alert_rules.yml`:

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| `HighErrorRate` | Error rate > 5% for 2 min | Warning | Investigate logs |
| `CriticalErrorRate` | Error rate > 20% for 1 min | Critical | Page on-call |
| `HighRequestLatency` | p95 > 1s for 3 min | Warning | Check slow traces |
| `AppDown` | `up == 0` for 1 min | Critical | Immediate response |
| `HighCPUUsage` | CPU > 80% for 5 min | Warning | Scale up |
| `HighMemoryUsage` | Memory > 85% for 5 min | Warning | Check for leaks |

View active alerts: **http://localhost:9090/alerts**

---

## 🔧 Configuration Reference

### Scaling the Application

```bash
# Scale sample-app to 3 replicas
docker compose up -d --scale sample-app=3
```

### Changing Prometheus Scrape Interval

Edit `prometheus/prometheus.yml`:
```yaml
global:
  scrape_interval: 10s   # Default 15s — lower for faster updates
```

Apply without restart:
```bash
curl -X POST http://localhost:9090/-/reload
```

### Adjusting Log Retention (Loki)

Edit `loki/loki-config.yml`:
```yaml
limits_config:
  reject_old_samples_max_age: 720h  # 30 days (default 168h = 7 days)
```

### Adding Custom Metrics

In `app/app.py`, add new Prometheus metrics:
```python
from prometheus_client import Counter, Histogram, Gauge

MY_METRIC = Counter("my_custom_total", "Description", ["label1", "label2"])
MY_METRIC.labels(label1="value", label2="other").inc()
```

---

## 📦 Maintenance

### View Logs for Any Service

```bash
docker compose logs -f sample-app       # App logs
docker compose logs -f prometheus       # Prometheus logs
docker compose logs -f grafana          # Grafana logs
docker compose logs -f loki             # Loki logs
docker compose logs -f jaeger           # Jaeger logs
```

### Restart a Single Service

```bash
docker compose restart grafana
docker compose restart prometheus
```

### Stop the Stack

```bash
# Stop containers (preserve data volumes)
docker compose stop

# Stop and remove containers + networks (preserve volumes)
docker compose down

# Full cleanup (removes volumes and images)
docker compose down -v --rmi local
```

### Backup Grafana Dashboards

```bash
# Export dashboard via API
curl -s http://admin:observability123@localhost:3000/api/dashboards/uid/observability-main \
  | python3 -m json.tool > grafana/dashboards/backup-$(date +%Y%m%d).json
```

---

## 🐛 Troubleshooting

| Problem | Likely Cause | Solution |
|---------|-------------|----------|
| Grafana shows "No data" | Prometheus not connected | Check `http://localhost:9090/targets` — all should be UP |
| Loki shows no logs | Promtail can't reach Docker socket | Run `docker compose logs promtail` and check permissions |
| Traces not in Jaeger | Jaeger not ready when app started | `docker compose restart sample-app` |
| App not starting | Port 5000 already in use | `lsof -i :5000` and kill conflicting process |
| High memory usage | Loki/Prometheus retaining too much | Lower retention in configs and restart services |

### Health Check Commands

```bash
# Prometheus health
curl http://localhost:9090/-/healthy

# Loki readiness
curl http://localhost:3100/ready

# Check all Prometheus targets
curl http://localhost:9090/api/v1/targets | python3 -m json.tool | grep '"health"'

# Jaeger services
curl http://localhost:16686/api/services
```

---

## 📈 Key Metrics Reference

| Metric Name | Type | Description |
|-------------|------|-------------|
| `http_requests_total` | Counter | Total HTTP requests by method, endpoint, status |
| `http_request_duration_seconds` | Histogram | Request latency distribution |
| `http_active_requests` | Gauge | Currently in-flight requests |
| `app_errors_total` | Counter | Application errors by type |
| `db_query_duration_seconds` | Histogram | Simulated DB query latency |
| `business_orders_total` | Counter | Orders processed by status |
| `node_cpu_seconds_total` | Counter | Host CPU time by mode |
| `node_memory_MemAvailable_bytes` | Gauge | Available host memory |
| `container_cpu_usage_seconds_total` | Counter | Container CPU usage |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Commit changes: `git commit -m 'Add my feature'`
4. Push: `git push origin feat/my-feature`
5. Open a Pull Request

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [Prometheus](https://prometheus.io/) — metrics collection & alerting
- [Grafana](https://grafana.com/) — visualization & dashboards
- [Grafana Loki](https://grafana.com/oss/loki/) — log aggregation
- [Jaeger](https://www.jaegertracing.io/) — distributed tracing
- [OpenTelemetry](https://opentelemetry.io/) — vendor-neutral instrumentation
