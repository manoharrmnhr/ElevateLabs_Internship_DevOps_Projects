# 🔭 Complete Observability Stack — Metrics, Logs & Traces

A production-grade, fully integrated observability system built with **Prometheus**, **Grafana**, **Loki**, **Jaeger**, and **Docker Compose**. Includes a live Python/Flask demo application with custom metrics, structured JSON logs, and distributed tracing.

```
┌─────────────┐    ┌────────────────────────────────────────────────┐
│   Browser   │───▶│              Grafana (port 3000)               │
└─────────────┘    │   Dashboards ▸ Metrics ▸ Logs ▸ Traces        │
                   └───────────┬────────────┬───────────────────────┘
                               │            │              │
                    ┌──────────▼──┐ ┌───────▼──┐ ┌───────▼───┐
                    │ Prometheus  │ │   Loki   │ │  Jaeger   │
                    │  (metrics)  │ │  (logs)  │ │ (traces)  │
                    └──────┬──────┘ └────┬─────┘ └─────┬─────┘
                           │             │              │
                    ┌──────▼──────────────▼──────────────▼──────────┐
                    │          Flask App  (port 5000)                │
                    │  /metrics  /api/users  /api/orders  /health    │
                    └────────────────────────────────────────────────┘
```

---

## 📦 Stack Overview

| Component       | Image                        | Port  | Purpose                        |
|-----------------|------------------------------|-------|--------------------------------|
| Flask App       | Custom (Python 3.11)         | 5000  | Demo service with telemetry    |
| Prometheus      | `prom/prometheus:v2.51.0`    | 9090  | Metrics scraping & storage     |
| Grafana         | `grafana/grafana:10.4.2`     | 3000  | Dashboards & visualization     |
| Loki            | `grafana/loki:2.9.8`         | 3100  | Log aggregation & querying     |
| Promtail        | `grafana/promtail:2.9.8`     | —     | Log shipping agent             |
| Jaeger          | `jaegertracing/all-in-one`   | 16686 | Distributed tracing UI         |
| Node Exporter   | `prom/node-exporter:v1.7.0`  | 9100  | Host-level metrics             |
| cAdvisor        | `gcr.io/cadvisor/cadvisor`   | 8080  | Container-level metrics        |
| Load Generator  | Custom (Python 3.11)         | —     | Realistic traffic simulation   |

---

## 🗂️ Project Structure

```
observability/
├── docker-compose.yml            # Orchestrates all services
├── app/
│   ├── app.py                    # Flask app — metrics, logs, traces
│   ├── load_generator.py         # Synthetic traffic generator
│   ├── requirements.txt          # Python dependencies
│   └── Dockerfile                # App container image
├── prometheus/
│   ├── prometheus.yml            # Scrape configs & targets
│   └── alert_rules.yml           # Alerting rules (latency, errors)
├── loki/
│   ├── loki-config.yml           # Loki server configuration
│   └── promtail-config.yml       # Log shipping & parsing pipeline
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── datasources.yml   # Auto-configure Prometheus, Loki, Jaeger
        └── dashboards/
            ├── dashboards.yml    # Dashboard provider config
            └── observability_dashboard.json  # Pre-built dashboard
```

---

## 🚀 Quick Start

### Prerequisites

Ensure the following are installed on your machine:

- [Docker](https://docs.docker.com/get-docker/) ≥ 24.0
- [Docker Compose](https://docs.docker.com/compose/install/) ≥ 2.20
- At least **4 GB RAM** available for Docker
- Ports **3000, 5000, 9090, 3100, 16686** free

### Step 1 — Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/observability-stack.git
cd observability-stack
```

### Step 2 — Build & Launch All Services

```bash
docker compose up --build -d
```

This command:
1. Builds the Flask app Docker image
2. Pulls all upstream images (Prometheus, Grafana, Loki, Jaeger, etc.)
3. Starts all containers in detached mode
4. Provisions Grafana datasources and dashboards automatically

> ⏳ First-time startup takes ~2–3 minutes. The load generator waits 15 s before sending traffic.

### Step 3 — Verify All Services Are Healthy

```bash
docker compose ps
```

Expected output (all services should show `Up` or `healthy`):

```
NAME                  STATUS          PORTS
observability-app     Up (healthy)    0.0.0.0:5000->5000/tcp
prometheus            Up              0.0.0.0:9090->9090/tcp
grafana               Up              0.0.0.0:3000->3000/tcp
loki                  Up              0.0.0.0:3100->3100/tcp
promtail              Up
jaeger                Up              0.0.0.0:16686->16686/tcp
node-exporter         Up              0.0.0.0:9100->9100/tcp
cadvisor              Up              0.0.0.0:8080->8080/tcp
load-generator        Up
```

### Step 4 — Access the UIs

| Service    | URL                                      | Credentials          |
|------------|------------------------------------------|----------------------|
| Grafana    | http://localhost:3000                    | admin / observability|
| Prometheus | http://localhost:9090                    | —                    |
| Jaeger UI  | http://localhost:16686                   | —                    |
| Flask App  | http://localhost:5000                    | —                    |
| cAdvisor   | http://localhost:8080                    | —                    |

---

## 📊 Grafana Dashboards

The dashboard is **auto-provisioned**. Navigate to **Grafana → Dashboards → Observability** to find it.

### Dashboard Sections

#### 1. Request Metrics
- **Request Rate (req/s)** — Live throughput gauge
- **P95 Latency** — 95th percentile response time
- **Error Rate** — 5xx responses as a fraction of total
- **Active Requests** — Concurrent in-flight requests
- **Latency Percentiles by Endpoint** — p50 / p95 / p99 time-series
- **Request Rate by Endpoint & Method** — Traffic breakdown

#### 2. Database Metrics
- **DB Query Duration (p50/p95)** by operation type (SELECT, INSERT)
- **DB Query Rate** — Simulated operations per second

#### 3. Application Logs (Loki)
- **Live log stream** with JSON parsing and level filtering
- **Log volume by level** (INFO / WARNING / ERROR) over time
- **Error log rate** — Spot error bursts quickly

#### 4. Errors & Alerts
- **HTTP Errors by type** (DatabaseError, TimeoutError, ValidationError)
- **Status code distribution** (200, 201, 500 over time)

#### 5. Infrastructure Metrics
- **CPU Usage** (per core via Node Exporter)
- **Memory Used vs Available**
- **Network I/O** — Receive and transmit bytes/s

---

## 🔍 Distributed Tracing with Jaeger

### Viewing Traces

1. Open **http://localhost:16686**
2. Select service **`observability-app`** from the dropdown
3. Click **Find Traces**
4. Click any trace to see the full span waterfall

### What Gets Traced

Each request creates a root span. The following child spans are automatically created:

| Endpoint        | Spans Created                                          |
|-----------------|--------------------------------------------------------|
| `GET /api/users`  | `get_users` → `db.query.users`                       |
| `GET /api/orders` | `get_orders` → `db.query.orders`                     |
| `POST /api/process` | `process_data` → `validate_input` → `transform_data` → `db.write` |
| `GET /api/slow`   | `slow_operation`                                     |

Spans carry attributes like `user.count`, `order.count`, and `input.keys`.

### Correlating Traces with Logs

Grafana's **Explore** panel supports trace-to-log correlation:

1. Go to **Grafana → Explore**
2. Select **Jaeger** datasource
3. Search for a trace
4. Click a span — Grafana will automatically query Loki for logs at the same timestamp

---

## 📜 Log Exploration with Loki

### Querying Logs in Grafana

Go to **Grafana → Explore → Loki datasource** and try these LogQL queries:

```logql
# All application logs
{service="app"}

# Only errors
{service="app"} | json | level="ERROR"

# Slow requests (>500ms)
{service="app"} | json | message=~".*Slow.*"

# Log rate per minute by level
sum by (level) (rate({service="app"} | json [1m]))

# Count errors in last 5 minutes
count_over_time({service="app"} | json | level="ERROR" [5m])
```

### Sample Log Entries

```json
{"timestamp": "2024-01-15 10:23:45,123", "level": "INFO",    "service": "observability-app", "message": "Incoming request: GET /api/users from 172.18.0.5", "module": "app", "line": 52}
{"timestamp": "2024-01-15 10:23:45,298", "level": "INFO",    "service": "observability-app", "message": "Returned 14 users", "module": "app", "line": 77}
{"timestamp": "2024-01-15 10:23:46,001", "level": "WARNING", "service": "observability-app", "message": "Slow DB query detected for orders", "module": "app", "line": 89}
{"timestamp": "2024-01-15 10:23:47,450", "level": "ERROR",   "service": "observability-app", "message": "Simulated error triggered: DatabaseError", "module": "app", "line": 114}
```

---

## 📈 Prometheus Metrics Reference

Query these in Prometheus UI (`http://localhost:9090`) or Grafana:

```promql
# Total request rate
sum(rate(http_requests_total[1m]))

# P95 latency across all endpoints
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Error rate percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# Per-endpoint P99 latency
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, endpoint))

# DB query rate by operation
sum(rate(db_query_duration_seconds_count[1m])) by (operation)

# Active requests right now
http_active_requests
```

---

## 🛠️ Application API Endpoints

| Method | Path            | Description                                 |
|--------|-----------------|---------------------------------------------|
| GET    | `/`             | Service info & health check                 |
| GET    | `/health`       | Liveness probe                              |
| GET    | `/metrics`      | Prometheus metrics scrape endpoint          |
| GET    | `/api/users`    | Fetch users (simulated DB query 20–150ms)   |
| GET    | `/api/orders`   | Fetch orders (20% chance of slow query)     |
| POST   | `/api/process`  | Process JSON payload (multi-span trace)     |
| GET    | `/api/error`    | Trigger simulated errors (for demo)         |
| GET    | `/api/slow`     | Slow endpoint (1–3s delay)                  |

### Manual Testing

```bash
# Test normal endpoints
curl http://localhost:5000/api/users
curl http://localhost:5000/api/orders
curl -X POST http://localhost:5000/api/process \
     -H "Content-Type: application/json" \
     -d '{"product": "laptop", "quantity": 2}'

# Trigger an error (adds to error metrics)
curl http://localhost:5000/api/error

# Hit the slow endpoint
curl http://localhost:5000/api/slow

# View raw Prometheus metrics
curl http://localhost:5000/metrics
```

---

## 🔔 Alerting Rules

Pre-configured Prometheus alert rules in `prometheus/alert_rules.yml`:

| Alert Name     | Condition                            | Severity |
|----------------|--------------------------------------|----------|
| `HighErrorRate` | Error rate > 0.1/s for 1 min       | Warning  |
| `HighLatency`  | P95 latency > 1.0s for 2 min        | Warning  |
| `AppDown`      | App unreachable for 30s             | Critical |

View triggered alerts at: **http://localhost:9090/alerts**

---

## 🧪 Generating Load for Testing

The **load-generator** container runs automatically. To generate burst traffic manually:

```bash
# Send 50 requests quickly
for i in $(seq 1 50); do
  curl -s http://localhost:5000/api/users > /dev/null &
done
wait

# Trigger errors to test alerting
for i in $(seq 1 20); do
  curl -s http://localhost:5000/api/error > /dev/null
done
```

---

## 🔧 Configuration Reference

### Changing Prometheus Scrape Interval

Edit `prometheus/prometheus.yml`:
```yaml
global:
  scrape_interval: 10s   # Change from 15s to 10s
```

### Changing Loki Log Retention

Edit `loki/loki-config.yml` and add:
```yaml
limits_config:
  retention_period: 48h   # Keep logs for 48 hours
```

### Adding a New Grafana Datasource

Add to `grafana/provisioning/datasources/datasources.yml`:
```yaml
- name: NewSource
  type: prometheus
  url: http://new-service:9090
```

---

## 🧹 Cleanup

```bash
# Stop all services
docker compose down

# Stop and remove all data volumes
docker compose down -v

# Remove built images too
docker compose down -v --rmi all
```

---

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| Grafana shows "No data" | Wait 1–2 min for the load generator to produce traffic |
| Loki datasource fails | Check `docker compose logs loki` for startup errors |
| Jaeger shows no traces | Verify `OTLP_ENDPOINT` env var points to `http://jaeger:4318/v1/traces` |
| Port conflict on 3000/9090 | Change host port in `docker-compose.yml` (e.g., `"3001:3000"`) |
| cAdvisor permission error | Run Docker with `privileged: true` (already set) or on Linux host |
| Promtail can't read Docker socket | Ensure Docker socket is accessible: `ls -la /var/run/docker.sock` |

---

## 📚 Key Concepts Demonstrated

- **RED Method** — Rate, Errors, Duration for every service
- **USE Method** — Utilization, Saturation, Errors for infrastructure
- **Structured Logging** — JSON-formatted logs with consistent fields
- **Distributed Tracing** — Parent/child spans across service boundaries
- **Log Correlation** — Linking traces ↔ logs via timestamp and trace ID
- **Metrics Cardinality** — Labels chosen to avoid high-cardinality explosion
- **SLI/SLO Readiness** — P95/P99 latency and error rate metrics ready for SLO definition

---

## 📄 License

MIT — feel free to use, adapt, and share.
