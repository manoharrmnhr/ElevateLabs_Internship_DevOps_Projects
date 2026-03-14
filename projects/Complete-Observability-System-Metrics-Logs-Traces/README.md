# Complete Observability System: Metrics, Logs & Traces

A comprehensive, production-ready observability system that integrates Prometheus for metrics, Loki for logs, and Jaeger for distributed tracing. This system provides a complete view of application behavior and system health through integrated monitoring dashboards.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Components](#components)
- [Configuration](#configuration)
- [Usage](#usage)
- [API Endpoints](#api-endpoints)
- [Dashboards](#dashboards)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Performance Considerations](#performance-considerations)
- [Conclusion](#conclusion)

## Overview

This observability system provides:

- **Metrics**: Real-time performance metrics collected by Prometheus
- **Logs**: Centralized log aggregation using Loki with structured JSON logging
- **Traces**: Distributed request tracing using Jaeger for end-to-end visibility

The system includes:
- A containerized Python Flask API instrumented with OpenTelemetry
- Prometheus for metrics scraping and storage
- Grafana for visualization and dashboards
- Loki for log aggregation
- Promtail for log shipping to Loki
- Jaeger for distributed tracing
- Alertmanager for alert management

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User/Client                          │
└────────────────────┬────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
    ┌─────────┐ ┌──────────┐ ┌──────────┐
    │   Flask │ │Prometheus│ │ Jaeger   │
    │   API   │ │ Scrape   │ │ Collector│
    │ (5000)  │ │ (9090)   │ │(14250)   │
    └────┬────┘ └────▲─────┘ └────▲─────┘
         │           │             │
    ┌────┴─────┐     │         ┌───┴─────┐
    │  Logging │     │         │  Traces  │
    │  (JSON)  │     │         │  Export  │
    └────┬─────┘     │         └───┬─────┘
         │           │             │
         ▼           ▼             ▼
    ┌─────────────────────────────────┐
    │        Promtail (Log Shipper)   │
    └─────────────────────────────────┘
              │         │         │
              ▼         ▼         ▼
         ┌────────┐ ┌────────┐ ┌────────┐
         │  Loki  │ │ Prom   │ │ Jaeger │
         │ (3100) │ │ (9090) │ │(16686) │
         └────────┘ └────────┘ └────────┘
              │         │         │
              └────────┬┴─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │     Grafana      │
              │  Dashboards &    │
              │  Visualization   │
              │      (3000)      │
              └──────────────────┘
```

## Prerequisites

- Docker and Docker Compose (version 20.10+)
- At least 4GB RAM available
- Ports 3000, 3100, 5000, 5778, 6831, 9090, 14250, 16686 available
- Linux, macOS, or Windows with WSL2

## Quick Start

### 1. Clone or Download the Project

```bash
cd /path/to/observability-system
```

### 2. Start All Services

```bash
docker-compose up -d
```

This command will:
- Build the Flask application
- Download all required images
- Start all containers
- Initialize volumes and networks

### 3. Verify All Services Are Running

```bash
docker-compose ps
```

Expected output shows all services as "Up":
```
observability-app         Up (healthy)
observability-prometheus  Up (healthy)
observability-grafana     Up (healthy)
observability-loki        Up (healthy)
observability-promtail    Up (healthy)
observability-jaeger      Up (healthy)
observability-alertmanager Up (healthy)
```

### 4. Generate Sample Traffic

```bash
# Run the load generation script
bash scripts/generate-traffic.sh
```

Or manually:
```bash
# Terminal 1: GET request loop
while true; do \
  curl http://localhost:5000/api/users; \
  sleep 2; \
done

# Terminal 2: POST request loop
while true; do \
  curl -X POST http://localhost:5000/api/process \
    -H "Content-Type: application/json" \
    -d '{"data": "test"}'; \
  sleep 5; \
done

# Terminal 3: Simulate errors
while true; do \
  curl http://localhost:5000/api/simulate-error; \
  sleep 15; \
done
```

### 5. Access Dashboards and UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | - |
| Jaeger UI | http://localhost:16686 | - |
| Loki | http://localhost:3100 | - |
| Application API | http://localhost:5000 | - |

## Components

### Flask Application (`app/app.py`)

A fully instrumented Python Flask API that demonstrates:

- **Structured Logging**: JSON-formatted logs with contextual information
- **Prometheus Metrics**: Custom metrics for requests, errors, and business logic
- **Distributed Tracing**: OpenTelemetry integration with Jaeger

#### Custom Metrics Exposed:

- `app_requests_total`: Counter of total requests by method, endpoint, and status
- `app_request_duration_seconds`: Histogram of request duration with quantiles
- `app_active_requests`: Gauge of currently active requests
- `app_errors_total`: Counter of errors by type and endpoint
- `app_events_total`: Counter of custom business events
- `app_processing_time_seconds`: Histogram of business logic processing time

#### API Endpoints:

- `GET /health`: Health check endpoint
- `GET /metrics`: Prometheus metrics endpoint
- `GET /api/users`: Fetch list of users
- `GET /api/users/<id>`: Fetch specific user
- `POST /api/process`: Process data with variable execution time
- `GET /api/simulate-error`: Simulate an error for testing

### Prometheus (`config/prometheus/prometheus.yml`)

Time-series database for metrics collection with:

- 15-second default scrape interval
- 15-day retention time
- Alert rules for critical conditions
- Targets configured for all major services

#### Alert Rules Include:

- `HighErrorRate`: Error rate > 10 errors/min for 2 minutes
- `HighResponseTime`: P95 response time > 1 second for 5 minutes
- `HighActiveRequests`: > 50 concurrent requests for 2 minutes
- `ServiceDown`: Service unavailable for > 1 minute
- `HighRequestVolume`: > 10 requests/second for 3 minutes

### Grafana (`config/grafana/`)

Visualization and dashboarding platform with:

- Pre-configured data sources (Prometheus, Loki, Jaeger)
- Custom dashboards for metrics, logs, and system overview
- Real-time refresh every 10 seconds
- Alert visualization and history

### Loki (`config/loki/loki-config.yml`)

Log aggregation system with:

- In-memory index for fast queries
- Filesystem backend for storage
- 24-hour index period for efficient retrieval
- Support for complex log queries with labels

### Promtail (`config/promtail/promtail-config.yml`)

Log shipper that:

- Collects logs from Docker containers
- Parses JSON logs using pipeline stages
- Adds labels for filtering and correlation
- Ships logs to Loki for centralized storage

### Jaeger (`docker-compose.yml`)

Distributed tracing system with:

- All-in-one deployment for simplicity
- UDP receiver on port 6831 for agents
- Jaeger UI on port 16686
- 10,000 trace limit in memory
- BadgerDB persistence

### Alertmanager

Alert management with:

- Alert deduplication and grouping
- Inhibition rules to prevent alert cascades
- Configurable routing (email, Slack, PagerDuty, etc.)
- Alert history and visualization in Grafana

## Configuration

### Environment Variables

No required environment variables. All services use defaults optimized for local development.

### Docker Compose Configuration

```yaml
volumes:
  prometheus_data:      # Prometheus time-series storage
  grafana_data:         # Grafana dashboards and settings
  loki_data:           # Loki log index and chunks
  jaeger_data:         # Jaeger trace storage
  alertmanager_data:   # Alertmanager configuration

networks:
  observability:       # Internal Docker network
```

### Scaling for Production

To scale this system for production:

1. **Metrics**: Deploy multiple Prometheus instances with federation
2. **Logs**: Use distributed Loki deployment with object storage (S3/GCS)
3. **Traces**: Deploy Jaeger as a distributed system with multiple collectors
4. **Storage**: Use external object storage (S3, GCS, Azure Blob)
5. **HA**: Implement high availability with load balancing

See [Advanced Topics](#advanced-topics) for detailed configuration.

## Usage

### Accessing Metrics

#### Via Prometheus GUI

1. Navigate to http://localhost:9090
2. Click "Graphs" tab
3. Enter query:
```promql
rate(app_requests_total[1m])
```
4. Click "Execute"

#### Common Queries

```promql
# Request rate
rate(app_requests_total[1m])

# Error rate
rate(app_errors_total[1m])

# P95 response time
histogram_quantile(0.95, rate(app_request_duration_seconds_bucket[5m]))

# Active requests
app_active_requests

# Requests by status
sum(rate(app_requests_total[5m])) by (status)
```

### Accessing Logs

#### Via Grafana Logs Dashboard

1. Navigate to http://localhost:3000
2. Go to Dashboards → Logs Dashboard
3. View real-time logs with filtering

#### Via Loki API

```bash
# Query logs for ERROR level
curl 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query={level="ERROR"}'

# Query logs by service
curl 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query={service="observability-app"}'
```

#### Log Query Syntax

```logql
# Exact match
{service="observability-app"}

# By level
{service="observability-app", level="ERROR"}

# By container
{container="observability-app"}

# Complex query
{service="observability-app"} |= "error" | json
```

### Accessing Traces

#### Via Jaeger UI

1. Navigate to http://localhost:16686
2. Select service: "observability-app"
3. View traces with operation details
4. Click on trace to view spans and timing

#### Trace Details Include

- Service name and operation
- Total duration and span count
- Dependencies between services
- Error status and logs
- Custom tags and annotations

## API Endpoints

### Health Check

```bash
curl http://localhost:5000/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2024-02-19T10:30:45.123456"
}
```

### Get Metrics

```bash
curl http://localhost:5000/metrics
```

Returns Prometheus format metrics.

### Get Users

```bash
curl http://localhost:5000/api/users
```

Response:
```json
[
  {
    "id": 1,
    "name": "Alice Johnson",
    "email": "alice@example.com"
  },
  ...
]
```

### Get User by ID

```bash
curl http://localhost:5000/api/users/1
```

### Process Data

```bash
curl -X POST http://localhost:5000/api/process \
  -H "Content-Type: application/json" \
  -d '{"data": "test"}'
```

Response:
```json
{
  "status": "processed",
  "processing_time": 1.234,
  "timestamp": "2024-02-19T10:30:45.123456"
}
```

### Simulate Error

```bash
curl http://localhost:5000/api/simulate-error
```

## Dashboards

### Application Metrics Dashboard

Shows real-time application performance:

- **Request Rate**: Requests per second by endpoint
- **Response Time**: P95 and P99 latency percentiles
- **Status Distribution**: Success vs error rates
- **Active Requests**: Concurrent request count
- **Errors**: Error count by type
- **Custom Events**: Business-level events

### Logs Dashboard

Displays centralized application logs:

- **Log Level Distribution**: Pie chart of log levels
- **Application Logs**: Real-time log stream
- **Error Count**: Errors by service over time
- **Log Rate**: Log volume by level

### System Overview Dashboard

Provides system-wide health view (optional):

- Service health status
- Resource utilization
- External dependency status
- Recent alerts

## Troubleshooting

### Services Not Starting

**Problem**: Containers fail to start

**Solution**:
```bash
# Check logs
docker-compose logs [service-name]

# Verify ports are available
lsof -i :3000
lsof -i :9090

# Clean and rebuild
docker-compose down -v
docker-compose up -d
```

### No Metrics Appearing

**Problem**: Prometheus shows "No data found"

**Solution**:
```bash
# Verify app is running
curl http://localhost:5000/metrics

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Generate traffic
while true; do curl http://localhost:5000/api/users; sleep 1; done
```

### Logs Not Appearing in Loki

**Problem**: No logs visible in Loki/Grafana

**Solution**:
```bash
# Check Promtail is running
docker logs observability-promtail

# Verify log format is JSON
docker logs observability-app | head -1

# Check Loki connection
curl http://localhost:3100/ready
```

### Traces Not Appearing

**Problem**: Jaeger shows no traces

**Solution**:
```bash
# Check Jaeger is receiving data
docker logs observability-jaeger | grep "processing"

# Verify UDP port is accessible
netstat -an | grep 6831

# Regenerate traffic to capture traces
curl http://localhost:5000/api/process
```

### High Memory Usage

**Problem**: System using excessive memory

**Solution**:
```bash
# Check container memory usage
docker stats

# Reduce Prometheus retention
# Edit config/prometheus/prometheus.yml:
# Change: --storage.tsdb.retention.time=15d
# To: --storage.tsdb.retention.time=7d

# Limit Jaeger trace count
# Edit docker-compose.yml:
# Change: MEMORY_MAX_TRACES=10000
# To: MEMORY_MAX_TRACES=5000
```

## Advanced Topics

### Custom Instrumentation

To add custom metrics to your application:

```python
from prometheus_client import Counter, Histogram

# Create metric
custom_metric = Counter(
    'custom_events_total',
    'Description of custom events',
    ['label1', 'label2']
)

# Increment counter
custom_metric.labels(label1='value1', label2='value2').inc()
```

### Alerting Configuration

Configure Slack notifications:

1. Create Slack webhook: https://api.slack.com/messaging/webhooks
2. Edit `config/prometheus/alertmanager.yml`:

```yaml
receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'YOUR_WEBHOOK_URL'
        channel: '#alerts'
```

### Production Deployment

For production environments:

1. **Use external storage**: 
   - Prometheus: Use object storage (S3/GCS)
   - Loki: Configure Boltdb Shipper with S3
   - Jaeger: Use Elasticsearch or Cassandra

2. **High Availability**:
   - Deploy multiple Prometheus instances
   - Use Loki distributed mode
   - Deploy Jaeger with HA configuration

3. **Security**:
   - Enable authentication in Grafana
   - Use TLS for all connections
   - Implement network policies
   - Use secrets management for API keys

4. **Resource Allocation**:

```yaml
services:
  prometheus:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
```

### Custom Alerting Rules

Add to `config/prometheus/alert_rules.yml`:

```yaml
- alert: CustomAlert
  expr: your_metric > threshold
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Custom alert"
    description: "{{ $value }}"
```

### Trace Sampling

For high-volume environments, configure sampling in `app/app.py`:

```python
config = Config(
    config={
        'sampler': {
            'type': 'probabilistic',
            'param': 0.1,  # Sample 10% of traces
        },
        ...
    }
)
```

## Performance Considerations

### Optimization Tips

1. **Metrics Cardinality**: Avoid high-cardinality labels
   - Instead of: `labels=['user_id', 'request_id']`
   - Use: `labels=['endpoint', 'status']`

2. **Scrape Intervals**: Balance between freshness and load
   - Default: 15 seconds
   - Adjust based on needs
   - Higher intervals reduce storage

3. **Log Volume**: Implement log sampling
   - Only log necessary events
   - Use structured logging
   - Aggregate similar log entries

4. **Trace Sampling**: Reduce traces for high-traffic systems
   - Default: Sample 100% of traces
   - For production: Sample 1-5%

5. **Storage Retention**: Adjust based on requirements
   - Metrics retention: 15 days (adjustable)
   - Logs retention: Configurable in Loki
   - Traces retention: Based on memory

### Resource Requirements

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Application | 0.5 | 512MB | - |
| Prometheus | 1.0 | 2GB | 10GB* |
| Grafana | 0.5 | 512MB | 1GB |
| Loki | 1.0 | 2GB | 10GB* |
| Jaeger | 1.0 | 2GB | 5GB* |
| Promtail | 0.25 | 256MB | - |
| Alertmanager | 0.25 | 256MB | 1GB |

*Retention-dependent

## Conclusion

This complete observability system provides:

1. **Real-time Monitoring**: Instant visibility into application behavior
2. **Centralized Logs**: Single source of truth for all application logs
3. **Distributed Tracing**: End-to-end request tracking across services
4. **Visualization**: Beautiful dashboards for data exploration
5. **Alerting**: Proactive issue detection and notification
6. **Scalability**: Foundation for production-grade monitoring

The system is configurable, extensible, and production-ready. Start with this foundation and customize based on your specific requirements.

### Next Steps

1. **Customize Dashboards**: Modify JSON files in `dashboards/` directory
2. **Add Custom Metrics**: Instrument your business logic
3. **Configure Alerts**: Set thresholds relevant to your SLOs
4. **Scale Up**: Deploy to production with external storage
5. **Integrate**: Connect with incident management tools

### Resources

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [OpenTelemetry](https://opentelemetry.io/)

### Support

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review logs: `docker-compose logs [service]`
3. Visit official documentation links above
4. Check GitHub issues for similar problems

---

**Version**: 1.0.0  
**Last Updated**: February 2024  
**License**: MIT
