# 🖥️ DevOps Monitoring Sandbox

> **A fully automated, production-grade local monitoring environment for DevOps training.**  
> Pre-configured Prometheus · Grafana · Node Exporter · Alertmanager stack — up in one command.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Ubuntu%2022.04-orange)
![Prometheus](https://img.shields.io/badge/Prometheus-2.51.2-red)
![Grafana](https://img.shields.io/badge/Grafana-10.4.2-orange)

---

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Option A: Vagrant VM (Recommended)](#option-a-vagrant-vm-recommended)
  - [Option B: Bare-Metal / Existing Ubuntu Server](#option-b-bare-metal--existing-ubuntu-server)
- [Access URLs](#access-urls)
- [Project Structure](#project-structure)
- [Pre-configured Alerts](#pre-configured-alerts)
- [Grafana Dashboards](#grafana-dashboards)
- [Testing Alerts (Stress Test)](#testing-alerts-stress-test)
- [Customization Guide](#customization-guide)
- [Troubleshooting](#troubleshooting)
- [Learning Exercises](#learning-exercises)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Host Machine (Your Laptop)                    │
│                                                                  │
│   Browser → localhost:3000 (Grafana)                            │
│             localhost:9090 (Prometheus)                          │
│             localhost:9093 (Alertmanager)                        │
│             localhost:9100 (Node Exporter)                       │
└─────────────────────────┬───────────────────────────────────────┘
                          │ Port Forwarding
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│             Vagrant VM  (192.168.56.10)  Ubuntu 22.04           │
│                                                                  │
│  ┌──────────────┐    scrape     ┌─────────────────────────┐    │
│  │ Node Exporter│◄──────────────│                         │    │
│  │  :9100       │               │      Prometheus         │    │
│  └──────────────┘               │        :9090            │    │
│                                 │                         │    │
│  ┌──────────────┐    scrape     │  alert_rules.yml        │    │
│  │  Prometheus  │◄──────────────│                         │    │
│  │  (self) :9090│               └────────────┬────────────┘    │
│  └──────────────┘                            │ fire alerts      │
│                                              ▼                  │
│  ┌──────────────┐               ┌─────────────────────────┐    │
│  │  Grafana     │               │      Alertmanager       │    │
│  │  :3000       │               │        :9093            │    │
│  │  (dashboards)│               │  (route → receivers)    │    │
│  └──────────────┘               └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Component Versions

| Component     | Version | Role                                   |
|---------------|---------|----------------------------------------|
| Prometheus    | 2.51.2  | Metrics collection & alerting engine   |
| Grafana       | 10.4.2  | Visualization & dashboards             |
| Node Exporter | 1.7.0   | Host OS metrics (CPU, memory, disk)    |
| Alertmanager  | 0.27.0  | Alert routing, deduplication, silencing|

---

## Prerequisites

### For Vagrant Setup (Option A)
| Requirement | Minimum Version | Download |
|-------------|----------------|---------|
| VirtualBox  | 7.0+           | [virtualbox.org](https://www.virtualbox.org/wiki/Downloads) |
| Vagrant     | 2.3+           | [vagrantup.com](https://developer.hashicorp.com/vagrant/downloads) |
| RAM         | 4 GB free      | — |
| Disk        | 10 GB free     | — |

### For Bare-Metal Setup (Option B)
- Ubuntu 20.04 or 22.04 LTS
- `sudo` / root access
- 2 GB RAM minimum

---

## Quick Start

### Option A: Vagrant VM (Recommended)

```bash
# 1. Clone the repository
git clone https://github.com/YOUR_USERNAME/devops-monitoring-sandbox.git
cd devops-monitoring-sandbox

# 2. Start the VM (first run downloads ~700MB Ubuntu box)
vagrant up

# 3. Wait for provisioning to complete (~5–10 minutes)
#    You will see green [INFO] messages as each tool installs

# 4. Open your browser
#    Grafana      → http://localhost:3000  (admin / admin)
#    Prometheus   → http://localhost:9090
#    Alertmanager → http://localhost:9093
```

**Useful Vagrant Commands:**

```bash
vagrant status          # Check VM state
vagrant ssh             # SSH into the VM
vagrant halt            # Shut down VM
vagrant destroy         # Remove VM completely
vagrant provision       # Re-run provisioning scripts
```

---

### Option B: Bare-Metal / Existing Ubuntu Server

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/devops-monitoring-sandbox.git
cd devops-monitoring-sandbox

# 2. Run the installer (requires sudo)
sudo bash scripts/install-bare-metal.sh

# 3. Run the health check
sudo bash scripts/health-check.sh
```

---

## Access URLs

Once the sandbox is running, open these URLs in your browser:

| Service       | URL                          | Credentials  |
|---------------|------------------------------|--------------|
| **Grafana**   | http://localhost:3000        | admin / admin |
| **Prometheus**| http://localhost:9090        | None          |
| **Alertmanager** | http://localhost:9093     | None          |
| Node Exporter | http://localhost:9100/metrics| None          |

> **First-time Grafana login:** You will be prompted to change the admin password. For sandbox purposes you can click "Skip" to keep `admin`.

---

## Project Structure

```
devops-monitoring-sandbox/
├── Vagrantfile                           # VM definition
├── README.md                             # This file
│
├── scripts/
│   ├── provision.sh                      # Main installer (used by Vagrant)
│   ├── install-bare-metal.sh             # Direct Ubuntu installer
│   ├── stress-test.sh                    # CPU/Memory/Disk stress tester
│   └── health-check.sh                   # Verify all services
│
└── configs/
    ├── prometheus/
    │   ├── prometheus.yml                # Scrape config & alertmanager ref
    │   └── alert_rules.yml               # All alert rules (CPU, Mem, Disk...)
    │
    ├── alertmanager/
    │   └── alertmanager.yml              # Routing, receivers, inhibitions
    │
    └── grafana/
        ├── provisioning/
        │   ├── datasources/
        │   │   └── prometheus.yml        # Auto-configure Prometheus datasource
        │   └── dashboards/
        │       └── dashboard.yml         # Auto-load dashboard files
        └── dashboards/
            └── node-exporter.json        # Pre-built system overview dashboard
```

---

## Pre-configured Alerts

All alerts are defined in `configs/prometheus/alert_rules.yml`.

### Alert Summary

| Alert Name            | Threshold    | Severity | Duration |
|-----------------------|-------------|----------|----------|
| HighCPUUsage          | > 80%       | Warning  | 2 min    |
| CriticalCPUUsage      | > 95%       | Critical | 1 min    |
| HighMemoryUsage       | > 80%       | Warning  | 2 min    |
| CriticalMemoryUsage   | > 95%       | Critical | 1 min    |
| DiskSpaceWarning      | > 75%       | Warning  | 5 min    |
| DiskSpaceCritical     | > 90%       | Critical | 2 min    |
| DiskIOHigh            | > 90% util  | Warning  | 5 min    |
| ServiceDown           | up == 0     | Critical | 1 min    |
| HighNetworkReceive    | > 100 MB/s  | Warning  | 5 min    |
| HighSystemLoad        | > 80% cores | Warning  | 5 min    |
| SystemLoadCritical    | > 150% cores| Critical | 3 min    |

### Viewing Alerts in Prometheus

1. Open **http://localhost:9090/alerts**
2. Alerts appear in three states: `Inactive` → `Pending` → `Firing`
3. A `Firing` alert is forwarded to Alertmanager

### Viewing Alerts in Alertmanager

1. Open **http://localhost:9093**
2. Active alert groups are shown with severity labels
3. You can silence alerts directly from the UI

---

## Grafana Dashboards

### Auto-Loaded Dashboard: Node Exporter – System Overview

The dashboard at `configs/grafana/dashboards/node-exporter.json` is automatically loaded and includes:

| Panel                  | Type       | Metric                           |
|------------------------|------------|----------------------------------|
| CPU Usage %            | Stat/Gauge | CPU idle rate                    |
| Memory Usage %         | Stat/Gauge | MemAvailable / MemTotal          |
| Disk Usage % (/)       | Stat/Gauge | Filesystem available bytes       |
| System Load (1m)       | Stat       | node_load1                       |
| CPU Usage Over Time    | Time-series| Per-CPU breakdown                |
| Memory Usage Over Time | Time-series| Used vs Available bytes          |
| Network I/O            | Time-series| RX/TX bytes per second           |
| Disk I/O               | Time-series| Read/Write bytes per second      |
| Active Alerts          | Table      | ALERTS{alertstate="firing"}      |

### Adding Community Dashboards

1. Open Grafana → **Dashboards → Import**
2. Enter a dashboard ID from [grafana.com/dashboards](https://grafana.com/grafana/dashboards/)
3. Recommended IDs:
   - **1860** – Node Exporter Full
   - **3662** – Prometheus 2.0 Stats
   - **9578** – Alertmanager

---

## Testing Alerts (Stress Test)

Use the included stress-test script to **actually trigger alerts** and see the full pipeline in action.

```bash
# SSH into the VM
vagrant ssh

# Run the stress tester (requires sudo)
sudo bash /opt/monitoring/configs/../scripts/stress-test.sh
```

**What to watch during stress tests:**

1. **Grafana** (`:3000`) — Panels turn yellow/red as thresholds are breached
2. **Prometheus** (`:9090/alerts`) — Alert state changes from `Pending` → `Firing`
3. **Alertmanager** (`:9093`) — Firing alerts appear with routing info

```bash
# Manually trigger a "ServiceDown" alert by stopping Node Exporter
sudo systemctl stop node_exporter
# Wait ~1 minute, then check Alertmanager
sudo systemctl start node_exporter  # Restore
```

---

## Customization Guide

### Change Alert Thresholds

Edit `configs/prometheus/alert_rules.yml`:
```yaml
- alert: HighCPUUsage
  expr: |
    100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    # Change 80 to your desired threshold ↑
```

After editing, reload Prometheus (no restart needed):
```bash
curl -X POST http://localhost:9090/-/reload
```

### Enable Email Notifications

Edit `configs/alertmanager/alertmanager.yml`:
```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alerts@yourdomain.com'
  smtp_auth_username: 'your@gmail.com'
  smtp_auth_password: 'your-app-password'

receivers:
  - name: 'critical-receiver'
    email_configs:
      - to: 'oncall@yourcompany.com'
        send_resolved: true
```

Reload Alertmanager:
```bash
curl -X POST http://localhost:9093/-/reload
```

### Enable Slack Notifications

```yaml
global:
  slack_api_url: 'https://hooks.slack.com/services/T.../B.../...'

receivers:
  - name: 'critical-receiver'
    slack_configs:
      - channel: '#alerts'
        title: ':fire: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        send_resolved: true
```

### Add More Scrape Targets

Edit `configs/prometheus/prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['192.168.56.20:8080']
    metrics_path: /metrics
```

---

## Troubleshooting

### Service Not Starting

```bash
# Check service logs
sudo journalctl -u prometheus -n 50 --no-pager
sudo journalctl -u grafana-server -n 50 --no-pager
sudo journalctl -u alertmanager -n 50 --no-pager
sudo journalctl -u node_exporter -n 50 --no-pager

# Validate Prometheus config
promtool check config /etc/prometheus/prometheus.yml

# Validate alert rules
promtool check rules /etc/prometheus/alert_rules.yml

# Validate Alertmanager config
amtool check-config /etc/alertmanager/alertmanager.yml
```

### Port Already in Use

```bash
# Check what's using a port
sudo lsof -i :3000
sudo lsof -i :9090

# Change Vagrant forwarded port in Vagrantfile if conflict on host:
config.vm.network "forwarded_port", guest: 3000, host: 3001  # Use 3001 instead
```

### Vagrant Box Not Starting

```bash
# Check VirtualBox extension pack
VBoxManage list extpacks

# Re-provision from scratch
vagrant destroy -f && vagrant up
```

### Prometheus Targets Showing as "DOWN"

1. Open **http://localhost:9090/targets**
2. Check the error message in the "Error" column
3. Common fix: ensure the target service is running and the port is accessible:
   ```bash
   curl http://localhost:9100/metrics | head -5
   ```

---

## Learning Exercises

Work through these exercises to master the monitoring stack:

**Beginner**
- [ ] Log in to Grafana and explore the pre-built dashboard
- [ ] Run the stress test and watch metrics change in real-time
- [ ] Stop Node Exporter and observe the `ServiceDown` alert fire

**Intermediate**
- [ ] Add a custom alert rule for swap memory usage
- [ ] Import Grafana dashboard ID `1860` (Node Exporter Full)
- [ ] Configure a Slack webhook receiver in Alertmanager
- [ ] Write a PromQL query to find the top 5 memory-consuming processes

**Advanced**
- [ ] Add a second VM target to Prometheus (multi-host monitoring)
- [ ] Create a custom Grafana dashboard from scratch using PromQL
- [ ] Set up alert silencing and inhibition rules in Alertmanager
- [ ] Export metrics from a sample app and create custom alert rules

---

## License

MIT License — free to use for learning and training purposes.

---

## Acknowledgements

- [Prometheus](https://prometheus.io/) — The Prometheus Authors
- [Grafana](https://grafana.com/) — Grafana Labs
- [Node Exporter](https://github.com/prometheus/node_exporter) — Prometheus community
