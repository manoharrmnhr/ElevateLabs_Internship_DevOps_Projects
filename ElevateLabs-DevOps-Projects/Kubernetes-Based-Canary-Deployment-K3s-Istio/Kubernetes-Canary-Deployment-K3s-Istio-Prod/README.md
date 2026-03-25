# 🚀 Kubernetes Canary Deployment — K3s + Istio + Helm

<div align="center">

![K8s](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Istio](https://img.shields.io/badge/Istio-466BB0?style=for-the-badge&logo=istio&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white)

**Production-grade canary deployment with traffic splitting, automated SLO gates, circuit breaking, and real-time observability.**

</div>

---

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Quick Start](#quick-start)
- [Step-by-Step Manual Setup](#step-by-step-manual-setup)
- [Traffic Management](#traffic-management)
- [Monitoring](#monitoring)
- [Canary Decision Framework](#canary-decision-framework)
- [Helm Deployment](#helm-deployment)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

---

## Overview

A **canary deployment** releases a new version to a small percentage of production traffic while keeping the stable version running. Istio's Envoy proxies route traffic according to declared weights — no application code changes required.

This project implements the full production lifecycle:

```
Deploy → Monitor → Shift Traffic → Gate on SLOs → Promote or Rollback
```

| Component | Role |
|-----------|------|
| **K3s** | Lightweight production-ready Kubernetes |
| **Istio 1.20** | L7 traffic management, mTLS, circuit breaking |
| **Helm 3** | Templated deployments with configurable traffic weights |
| **Node.js 20** | Demo app — v1 stable + v2 canary with fault injection |
| **Prometheus** | Metrics scraped from `/metrics` on each pod |
| **Grafana** | Dashboard comparing stable vs canary KPIs |
| **GitHub Actions** | Automated build + validate + deploy pipeline |

---

## Architecture

```
            External Traffic
                   │
       ┌───────────▼───────────┐
       │  Istio Ingress Gateway │
       └───────────┬───────────┘
                   │
       ┌───────────▼───────────┐
       │    VirtualService      │
       │  x-canary:force → 100% canary
       │  Default: 80% / 20%   │
       └──────┬────────────┬───┘
              │            │
    ┌─────────▼──┐    ┌────▼──────────┐
    │ app-stable │    │  app-canary   │
    │  (3 pods)  │    │   (1 pod)     │
    │  v1.0.0    │    │   v2.0.0      │
    │ 80% traffic│    │  20% traffic  │
    └─────┬──────┘    └───────┬───────┘
          │                   │
    ┌─────▼───────────────────▼──────┐
    │  Prometheus metrics scraping    │
    │  Grafana dashboards + alerting  │
    └────────────────────────────────┘
```

Each pod runs **2 containers**: the app container + the Envoy sidecar injected by Istio. All pod-to-pod communication is secured via **mTLS** automatically.

---

## Prerequisites

| Requirement | Check |
|-------------|-------|
| Linux (Ubuntu 20.04+) | `uname -r` |
| Docker 20.10+ | `docker --version` |
| 4 GB+ RAM | `free -h` |
| 15 GB+ disk | `df -h` |
| 2+ CPU cores | `nproc` |

> K3s, Helm, and Istio are installed by `setup.sh`.

---

## Project Structure

```
k8s-canary/
├── app/
│   ├── v1/                          # Stable app — green UI, 0% error rate
│   │   ├── server.js                # Structured JSON logs, Prometheus /metrics
│   │   └── Dockerfile               # Multi-stage, non-root user, healthcheck
│   └── v2/                          # Canary app — dark UI, new features
│       ├── server.js                # Configurable FAULT_RATE for chaos testing
│       └── Dockerfile
├── k8s/
│   ├── 00-namespace.yaml            # NS + istio-injection + ResourceQuota + LimitRange
│   ├── 01-deployment-stable.yaml   # 3 replicas + HPA(3→10) + PDB + all probes
│   ├── 02-deployment-canary.yaml   # 1 replica + PDB + fault injection env var
│   └── 03-services.yaml            # ClusterIP services (main + per-track)
├── istio/
│   ├── 01-gateway.yaml              # L7 entry (HTTP, commented TLS for production)
│   ├── 02-destination-rule.yaml    # Subsets + mTLS + circuit breaker + outlier detection
│   ├── 03-vs-80-20.yaml            # Phase 1 — 80% stable / 20% canary
│   ├── 04-vs-50-50.yaml            # Phase 2 — 50/50 mid-rollout
│   ├── 05-vs-promote.yaml          # Phase 3 — 100% canary (promote)
│   └── 06-vs-rollback.yaml         # Emergency — 100% stable (rollback)
├── helm/canary-app/
│   ├── Chart.yaml
│   ├── values.yaml                  # All tunable: images, weights, resources
│   └── templates/
│       ├── deployments.yaml
│       └── virtual-service.yaml
├── monitoring/
│   ├── prometheus/service-monitor.yaml   # ServiceMonitor + PrometheusRule SLO alerts
│   └── grafana/dashboards/canary-dashboard.json
├── scripts/
│   ├── setup.sh                     # Full stack provisioner
│   └── canary.sh                    # Lifecycle CLI: deploy/shift/promote/rollback/monitor
└── .github/workflows/
    └── canary-deploy.yml            # GitHub Actions CI/CD pipeline
```

---

## Quick Start

```bash
git clone https://github.com/your-username/k8s-canary-istio.git
cd k8s-canary-istio

# Full automated setup (~10 min)
sudo bash scripts/setup.sh

# Confirm 80/20 split
./scripts/canary.sh loadtest 100

# Open live dashboard
./scripts/canary.sh monitor
```

---

## Step-by-Step Manual Setup

### Step 1 — Install K3s

```bash
# Install without Traefik (Istio replaces it)
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode=644" sh -

# Configure kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

# Verify node is Ready
kubectl get nodes
# NAME     STATUS   ROLES                  AGE   VERSION
# node1    Ready    control-plane,master   60s   v1.28.x+k3s1
```

> K3s uses **containerd** as its runtime — Docker images must be explicitly imported.

---

### Step 2 — Install Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version --short   # v3.14.x+...
```

---

### Step 3 — Install Istio

```bash
# Download Istio CLI
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
sudo mv istio-1.20.0/bin/istioctl /usr/local/bin/

# Deploy Istio (demo profile = all components)
istioctl install --set profile=demo -y

# Wait for control plane
kubectl wait --for=condition=ready pod -n istio-system --all --timeout=300s

# Verify (should see istiod + ingressgateway + egressgateway)
kubectl get pods -n istio-system
```

---

### Step 4 — Build Docker Images

```bash
# Build both versions
docker build -t demo-app:v1.0.0 ./app/v1/
docker build -t demo-app:v2.0.0 ./app/v2/

# Import into K3s containerd (required — K3s does not use Docker daemon)
docker save demo-app:v1.0.0 | sudo k3s ctr images import -
docker save demo-app:v2.0.0 | sudo k3s ctr images import -

# Verify
sudo k3s ctr images list | grep demo-app
```

---

### Step 5 — Deploy to Kubernetes

```bash
# Namespace + Istio injection label + quotas
kubectl apply -f k8s/00-namespace.yaml

# Confirm injection is enabled
kubectl get namespace canary-demo --show-labels | grep istio-injection
# canary-demo   istio-injection=enabled ...

# Deploy both versions
kubectl apply -f k8s/01-deployment-stable.yaml
kubectl apply -f k8s/02-deployment-canary.yaml
kubectl apply -f k8s/03-services.yaml

# Wait for Ready
kubectl wait --for=condition=ready pod \
  -n canary-demo -l app=demo-app --timeout=120s

# Verify — READY must be 2/2 (app + Envoy sidecar)
kubectl get pods -n canary-demo -o wide
```

**Expected:**
```
NAME                         READY   STATUS    RESTARTS   AGE
app-stable-7d9f-aaa          2/2     Running   0          45s
app-stable-7d9f-bbb          2/2     Running   0          45s
app-stable-7d9f-ccc          2/2     Running   0          43s
app-canary-5c6d-ddd          2/2     Running   0          40s
```

> **2/2** = app container + Istio Envoy sidecar injected automatically.

---

### Step 6 — Configure Istio Traffic Routing

```bash
# 1. Gateway (external HTTP entry point)
kubectl apply -f istio/01-gateway.yaml

# 2. DestinationRule (stable/canary subsets + circuit breaker + mTLS)
kubectl apply -f istio/02-destination-rule.yaml

# 3. VirtualService (80/20 split + header override + retry policy)
kubectl apply -f istio/03-vs-80-20.yaml

# Validate configuration
istioctl analyze -n canary-demo
# ✔ No validation issues found when analyzing namespace: canary-demo.

# Inspect the weight configuration
kubectl get vs demo-app-vs -n canary-demo \
  -o jsonpath='{.spec.http[1].route}' | python3 -m json.tool
```

**VirtualService routing logic:**
```
Request arrives at Istio Ingress Gateway
  ↓
Does it have header "x-canary: force"?
  → YES → 100% route to canary subset
  → NO  → Weight-based: 80% stable / 20% canary
             ↓
           Retry on failure (3 attempts, 3s timeout each)
```

---

### Step 7 — Verify & Test

```bash
# Get the NodePort for Istio ingress
INGRESS_PORT=$(kubectl get svc istio-ingressgateway -n istio-system \
  -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

# Add local DNS (optional)
echo "127.0.0.1 demo-app.local" | sudo tee -a /etc/hosts

# Test regular request (hits stable 80% of the time)
curl -s -H "Host: demo-app.local" \
  http://localhost:$INGRESS_PORT/healthz
# {"status":"ok","version":"v1.0.0","uptime":120}

# Force canary with header
curl -s -H "Host: demo-app.local" -H "x-canary: force" \
  http://localhost:$INGRESS_PORT/healthz
# {"status":"ok","version":"v2.0.0","uptime":115}

# Check Prometheus metrics
curl -s -H "Host: demo-app.local" \
  http://localhost:$INGRESS_PORT/metrics

# Confirm 80/20 distribution
./scripts/canary.sh loadtest 100
# Stable (v1): ~80 hits
# Canary (v2): ~20 hits
```

---

## Traffic Management

### All-in-one CLI

```bash
./scripts/canary.sh status              # Current split + pod health
./scripts/canary.sh shift 10            # 10% canary
./scripts/canary.sh shift 50            # 50/50
./scripts/canary.sh auto                # Automated: 10→20→50→100% with SLO gates
./scripts/canary.sh promote             # 100% canary (with SLO pre-check)
./scripts/canary.sh rollback            # Instant 100% stable
./scripts/canary.sh monitor             # Live terminal dashboard (5s refresh)
./scripts/canary.sh loadtest 200        # 200-request load test
```

### Manual kubectl approaches

```bash
# Apply a specific phase
kubectl apply -f istio/04-vs-50-50.yaml    # 50/50
kubectl apply -f istio/05-vs-promote.yaml  # 100% canary
kubectl apply -f istio/06-vs-rollback.yaml # 100% stable

# Edit weights live (opens $EDITOR)
kubectl edit vs demo-app-vs -n canary-demo
```

### Post-promotion cleanup

```bash
# After promoting canary to 100%:
# 1. Update stable deployment to new image
kubectl set image deployment/app-stable \
  app=demo-app:v2.0.0 -n canary-demo

# 2. Wait for rollout
kubectl rollout status deployment/app-stable -n canary-demo

# 3. Scale down old canary
kubectl scale deployment/app-canary --replicas=0 -n canary-demo

# 4. Route traffic back to stable subset (now running v2)
kubectl apply -f istio/06-vs-rollback.yaml
```

---

## Monitoring

### Kiali + Grafana + Prometheus (Istio addons)

```bash
# Install all addons
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

# Open dashboards
istioctl dashboard kiali    # Service graph + traffic flows
istioctl dashboard grafana  # Metrics dashboards
istioctl dashboard prometheus  # Raw metrics
```

### Import custom canary dashboard

```
Grafana → Dashboards → Import → Upload monitoring/grafana/dashboards/canary-dashboard.json
```

Dashboard panels: Traffic split %, Error rates, Avg latency, Request volume, Pod status.

### Key Prometheus queries

```promql
# Error rate comparison
app_error_rate_pct{namespace="canary-demo"}

# Request rate
rate(app_http_requests_total{namespace="canary-demo"}[2m])

# Latency comparison
app_latency_avg_ms{namespace="canary-demo"}

# Traffic split ratio
sum(rate(app_http_requests_total{track="canary"}[5m]))
/ sum(rate(app_http_requests_total[5m]))
```

---

## Canary Decision Framework

| Metric | Green ✅ | Yellow ⚠️ | Red 🔴 Rollback |
|--------|---------|-----------|----------------|
| Error rate | < 1% | 1–5% | **> 5%** |
| Avg latency | < 200ms | 200–400ms | **> 500ms** |
| Pod restarts | 0 | 1–2 in 5m | **> 2 in 5m** |
| Success rate | > 99% | 95–99% | **< 95%** |

**Recommended rollout schedule:**

```
Hour 0:  Deploy → 5-10% canary
Hour 1:  Error rate < 1%  → shift to 25%
Hour 2:  Error rate < 1%  → shift to 50%
Hour 4:  Error rate < 1%  → shift to 100% (promote)
```

---

## Helm Deployment

```bash
# Install / upgrade
helm upgrade --install canary-app ./helm/canary-app \
  --namespace canary-demo --create-namespace

# Set custom traffic weights
helm upgrade canary-app ./helm/canary-app \
  -n canary-demo \
  --set traffic.canaryWeight=30 \
  --set traffic.stableWeight=70

# Rollback Helm release
helm rollback canary-app 1 -n canary-demo

# List history
helm history canary-app -n canary-demo
```

---

## Troubleshooting

**Pods show 1/1 instead of 2/2 (sidecar not injected)**
```bash
kubectl get namespace canary-demo --show-labels | grep istio-injection
# Fix: kubectl label namespace canary-demo istio-injection=enabled
kubectl rollout restart deployment -n canary-demo
```

**503 errors from ingress**
```bash
istioctl analyze -n canary-demo
istioctl proxy-config cluster deploy/app-stable.canary-demo
```

**Images not found (ErrImageNeverPull)**
```bash
docker save demo-app:v1.0.0 | sudo k3s ctr images import -
docker save demo-app:v2.0.0 | sudo k3s ctr images import -
kubectl rollout restart deployment -n canary-demo
```

**Traffic not splitting correctly**
```bash
# Check VirtualService weights
kubectl get vs demo-app-vs -n canary-demo \
  -o jsonpath='{.spec.http[1].route}' | python3 -m json.tool

# Verify pod labels match subsets
kubectl get pods -n canary-demo -l track=stable --show-labels
kubectl get pods -n canary-demo -l track=canary --show-labels
```

---

## Cleanup

```bash
./scripts/canary.sh cleanup      # delete namespace (interactive)

# Full uninstall
kubectl delete namespace canary-demo
istioctl uninstall --purge -y
kubectl delete namespace istio-system
/usr/local/bin/k3s-uninstall.sh
docker rmi demo-app:v1.0.0 demo-app:v2.0.0
```

---

## References

- [Istio Traffic Management](https://istio.io/latest/docs/concepts/traffic-management/)
- [K3s Documentation](https://docs.k3s.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [Kiali Observability](https://kiali.io/)
