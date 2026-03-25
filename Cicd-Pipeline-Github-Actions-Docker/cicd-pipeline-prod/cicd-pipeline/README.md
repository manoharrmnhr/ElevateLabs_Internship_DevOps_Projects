# 🚀 CI/CD Pipeline — GitHub Actions + Docker + Minikube

> **Production-grade CI/CD pipeline** that automatically lints, tests, builds a Docker image,
> pushes to Docker Hub, and deploys to a local Kubernetes cluster — **zero cloud costs.**

[![CI/CD Pipeline](https://github.com/YOUR_USERNAME/cicd-pipeline/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/YOUR_USERNAME/cicd-pipeline/actions/workflows/ci-cd.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/YOUR_DOCKERHUB_USERNAME/cicd-flask-app)](https://hub.docker.com/r/YOUR_DOCKERHUB_USERNAME/cicd-flask-app)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Step-by-Step Guide](#-step-by-step-guide)
  - [1. Clone & Set Up Locally](#step-1--clone--set-up-locally)
  - [2. Run Tests Locally](#step-2--run-tests-locally)
  - [3. Build & Run with Docker](#step-3--build--run-with-docker)
  - [4. Configure GitHub Secrets](#step-4--configure-github-secrets)
  - [5. Push to GitHub (Triggers CI/CD)](#step-5--push-to-github-triggers-cicd)
  - [6. Verify GitHub Actions Pipeline](#step-6--verify-github-actions-pipeline)
  - [7. Deploy to Minikube](#step-7--deploy-to-minikube)
  - [8. Verify Running Application](#step-8--verify-running-application)
  - [9. Rolling Updates](#step-9--rolling-updates)
- [API Reference](#-api-reference)
- [Makefile Commands](#-makefile-commands)
- [Troubleshooting](#-troubleshooting)

---

## 🔍 Overview

This project implements a **full CI/CD pipeline** for a production Flask web application. Every `git push` to `main` automatically:

1. **Lints** the code with `flake8` + `black`
2. **Tests** with `pytest` (80%+ coverage enforced)
3. **Builds** a multi-stage Docker image (multi-arch: `amd64` + `arm64`)
4. **Pushes** to Docker Hub with semantic version tags
5. **Scans** for vulnerabilities using Trivy
6. **Summarizes** results in the GitHub Actions dashboard

Local deployment uses **Minikube** with zero-downtime rolling updates, liveness/readiness probes, and Horizontal Pod Autoscaling.

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                        Developer Machine                           │
│                                                                    │
│  git push ──▶ GitHub Repo                                          │
│                    │                                               │
│         ┌──────────▼───────────┐                                   │
│         │   GitHub Actions     │                                   │
│         │  ┌────────────────┐  │                                   │
│         │  │  Job 1: Lint   │  │  flake8 + black                   │
│         │  └───────┬────────┘  │                                   │
│         │          ▼           │                                   │
│         │  ┌────────────────┐  │                                   │
│         │  │  Job 2: Test   │  │  pytest + coverage                │
│         │  └───────┬────────┘  │                                   │
│         │          ▼           │                                   │
│         │  ┌────────────────┐  │                                   │
│         │  │ Job 3: Build   │  │  Docker Buildx (amd64/arm64)      │
│         │  │    & Push      │  │  ──▶ Docker Hub Registry          │
│         │  └───────┬────────┘  │                                   │
│         │          ▼           │                                   │
│         │  ┌────────────────┐  │                                   │
│         │  │ Job 4: Trivy   │  │  Vulnerability scan               │
│         │  │ Security Scan  │  │                                   │
│         │  └────────────────┘  │                                   │
│         └──────────────────────┘                                   │
│                                                                    │
│  ┌─────────────────────────────────────┐                           │
│  │         Minikube (Local K8s)        │                           │
│  │                                     │                           │
│  │  ┌──────────┐    ┌──────────┐       │                           │
│  │  │  Pod 1   │    │  Pod 2   │  ...  │  ◀── kubectl apply        │
│  │  │  Flask   │    │  Flask   │       │                           │
│  │  └──────────┘    └──────────┘       │                           │
│  │         │               │           │                           │
│  │  ┌──────▼───────────────▼────────┐  │                           │
│  │  │     NodePort Service :30080   │  │                           │
│  │  └───────────────────────────────┘  │                           │
│  └─────────────────────────────────────┘                           │
│              │                                                     │
│        Browser / curl ──▶ http://$(minikube ip):30080              │
└────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
cicd-pipeline/
├── app/
│   ├── __init__.py
│   ├── app.py                    # Flask application (factory pattern)
│   ├── requirements.txt          # Pinned Python dependencies
│   └── tests/
│       ├── __init__.py
│       ├── conftest.py
│       └── test_app.py           # 20+ unit & integration tests
│
├── .github/
│   └── workflows/
│       └── ci-cd.yml             # 5-job GitHub Actions pipeline
│
├── k8s/
│   ├── deployment.yml            # K8s Deployment (2 replicas, probes, limits)
│   ├── service.yml               # NodePort Service + HPA
│   └── configmap.yml             # Non-secret environment config
│
├── nginx/
│   └── nginx.conf                # Reverse proxy config (optional)
│
├── scripts/
│   └── deploy-local.sh           # One-shot Minikube deploy script
│
├── Dockerfile                    # Multi-stage production Dockerfile
├── docker-compose.yml            # Local dev + optional Nginx profile
├── Makefile                      # Developer convenience commands
├── pytest.ini                    # Test configuration
├── .gitignore
└── README.md
```

---

## 🛠️ Prerequisites

Install the following tools before starting:

| Tool | Min Version | Install Link |
|------|------------|--------------|
| Git | 2.x | https://git-scm.com |
| Docker | 24.x | https://docs.docker.com/get-docker/ |
| Docker Compose | 2.x | Bundled with Docker Desktop |
| Minikube | 1.32+ | https://minikube.sigs.k8s.io/docs/start/ |
| kubectl | 1.28+ | https://kubernetes.io/docs/tasks/tools/ |
| Python | 3.11+ | https://python.org |

### Install on Ubuntu/Debian

```bash
# ── Docker ──────────────────────────────────────────────────────
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 curl
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker                         # apply group change immediately

# ── Minikube ────────────────────────────────────────────────────
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

# ── kubectl ─────────────────────────────────────────────────────
curl -LO "https://dl.k8s.io/release/$(curl -L -s \
  https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# ── Verify all tools ────────────────────────────────────────────
docker --version
minikube version
kubectl version --client
```

### Install on macOS

```bash
brew install docker minikube kubectl python@3.11
```

---

## ⚡ Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/YOUR_USERNAME/cicd-pipeline.git
cd cicd-pipeline

# 2. Run tests
make test

# 3. Build and run locally
make run
# App available at: http://localhost:5000

# 4. Deploy to Minikube
make deploy DOCKERHUB_USER=your_dockerhub_username
```

---

## 📖 Step-by-Step Guide

### Step 1 — Clone & Set Up Locally

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/cicd-pipeline.git
cd cicd-pipeline

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate         # Windows: .venv\Scripts\activate

# Install dependencies
pip install -r app/requirements.txt

# Verify installation
python -c "import flask; print('Flask', flask.__version__)"
```

---

### Step 2 — Run Tests Locally

```bash
# Run full test suite with coverage
pytest app/tests/ -v --cov=app --cov-report=term-missing

# Expected output:
# app/tests/test_app.py::TestHomeEndpoint::test_home_returns_200 PASSED
# app/tests/test_app.py::TestHealthEndpoint::test_health_returns_200 PASSED
# ... (20+ tests)
# Coverage: 85%+
```

**What the tests cover:**
- `GET /` — status 200, JSON structure, all required fields
- `GET /health` — Kubernetes liveness probe
- `GET /ready` — Kubernetes readiness probe
- `GET /metrics` — uptime and version metrics
- `POST /echo` — payload reflection, invalid JSON handling
- `GET /nonexistent` — 404 JSON error response
- `DELETE /health` — 405 method-not-allowed response

---

### Step 3 — Build & Run with Docker

```bash
# Build the multi-stage image
docker build -t cicd-flask-app:local .

# Check image size (should be ~150MB due to slim base)
docker images cicd-flask-app

# Run with Docker Compose
docker-compose up --build

# In a new terminal, verify endpoints:
curl http://localhost:5000/
curl http://localhost:5000/health
curl http://localhost:5000/metrics
curl -X POST http://localhost:5000/echo \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'

# Stop
docker-compose down
```

**Expected response from `GET /`:**
```json
{
  "app": "CI/CD Pipeline Demo",
  "environment": "production",
  "status": "running",
  "timestamp": "2025-01-15T10:30:00Z",
  "version": "1.0.0"
}
```

---

### Step 4 — Configure GitHub Secrets

Before pushing, set up Docker Hub credentials in GitHub so the Actions workflow can push images.

#### 4a. Create a Docker Hub Access Token

1. Log in at https://hub.docker.com
2. Click your avatar → **Account Settings** → **Security**
3. Click **New Access Token**
4. Name it `github-actions-cicd` with **Read/Write** permissions
5. Copy the token (shown only once)

#### 4b. Add Secrets to GitHub Repository

1. Open your GitHub repository
2. Go to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add:

| Secret Name | Value |
|-------------|-------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | The access token from step 4a |

> ⚠️ Never commit credentials to code. Always use GitHub Secrets.

---

### Step 5 — Push to GitHub (Triggers CI/CD)

```bash
# Initialize git (if starting fresh)
git init
git add .
git commit -m "feat: initial production CI/CD pipeline"

# Add your GitHub remote
git remote add origin https://github.com/YOUR_USERNAME/cicd-pipeline.git
git branch -M main

# Push — this AUTOMATICALLY triggers the GitHub Actions workflow
git push -u origin main
```

From this point on, **every push to `main` runs the full pipeline automatically.**

---

### Step 6 — Verify GitHub Actions Pipeline

1. Open your GitHub repository
2. Click the **Actions** tab
3. You will see the **"CI/CD Pipeline"** workflow running with 5 jobs:

```
CI/CD Pipeline
├── 🔍 Lint & Style Check          ← flake8 + black
├── ✅ Unit Tests & Coverage        ← pytest (80% min coverage)
├── 🐳 Build & Push Docker Image   ← Docker Buildx → Docker Hub
├── 🔒 Security Vulnerability Scan ← Trivy scanner
└── 📢 Pipeline Summary            ← Markdown summary in Actions
```

Each job shows:
- ✅ Green checkmark = passed
- ❌ Red X = failed (check logs to debug)
- ⏭️ Skipped = not triggered (e.g., PRs skip the push job)

**Verify the image was pushed to Docker Hub:**
```
https://hub.docker.com/r/YOUR_DOCKERHUB_USERNAME/cicd-flask-app/tags
```

You should see tags:
- `latest`
- `main`
- `sha-<short-commit-hash>`

---

### Step 7 — Deploy to Minikube

```bash
# Start Minikube (first time only: downloads ~500MB)
minikube start --driver=docker --memory=2048 --cpus=2

# Verify the cluster is healthy
kubectl cluster-info
kubectl get nodes
# Expected: 1 node in "Ready" state

# Update the image name in deployment manifest
# Replace YOUR_DOCKERHUB_USERNAME with your actual username:
sed -i 's/YOUR_DOCKERHUB_USERNAME/your_actual_username/g' k8s/deployment.yml

# Apply all Kubernetes manifests
kubectl apply -f k8s/configmap.yml
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service.yml

# Watch the rollout (wait for "successfully rolled out")
kubectl rollout status deployment/cicd-flask-app

# Verify pods are Running (2/2 Ready)
kubectl get pods -l app=cicd-flask-app

# Verify service
kubectl get service cicd-flask-service
```

**Alternatively, use the one-shot script:**
```bash
chmod +x scripts/deploy-local.sh
bash scripts/deploy-local.sh YOUR_DOCKERHUB_USERNAME
```

---

### Step 8 — Verify Running Application

```bash
# Get the Minikube service URL
minikube service cicd-flask-service --url
# Example output: http://192.168.49.2:30080

# Test all endpoints (replace IP with your Minikube IP)
MINIKUBE_URL=$(minikube service cicd-flask-service --url)

curl $MINIKUBE_URL/
curl $MINIKUBE_URL/health
curl $MINIKUBE_URL/ready
curl $MINIKUBE_URL/metrics
curl -X POST $MINIKUBE_URL/echo \
  -H "Content-Type: application/json" \
  -d '{"pipeline": "success"}'

# Open in browser
minikube service cicd-flask-service
```

**Useful kubectl commands for monitoring:**
```bash
# View all resources
kubectl get all -l app=cicd-flask-app

# View pod logs (live)
kubectl logs -l app=cicd-flask-app --follow

# Describe a pod (events, resource usage)
kubectl describe pod -l app=cicd-flask-app

# Check HPA (autoscaler)
kubectl get hpa cicd-flask-hpa

# Interactive shell in a pod (debugging)
kubectl exec -it $(kubectl get pod -l app=cicd-flask-app \
  -o jsonpath='{.items[0].metadata.name}') -- /bin/sh
```

---

### Step 9 — Rolling Updates

When you push new code, the pipeline builds a new image. Update your deployment with zero downtime:

```bash
# After GitHub Actions pushes the new image, update Minikube:
kubectl rollout restart deployment/cicd-flask-app

# Monitor the rolling update (new pods start before old ones stop)
kubectl rollout status deployment/cicd-flask-app

# View rollout history
kubectl rollout history deployment/cicd-flask-app

# Rollback to previous version if needed
kubectl rollout undo deployment/cicd-flask-app

# Scale manually
kubectl scale deployment cicd-flask-app --replicas=4
```

---

## 📡 API Reference

| Method | Endpoint | Description | Status |
|--------|----------|-------------|--------|
| `GET` | `/` | App info, version, status | 200 |
| `GET` | `/health` | Kubernetes liveness probe | 200 |
| `GET` | `/ready` | Kubernetes readiness probe | 200 |
| `GET` | `/metrics` | Uptime and version metrics | 200 |
| `POST` | `/echo` | Echo JSON payload | 200 / 400 |

---

## ⚙️ Makefile Commands

```bash
make help       # List all available commands
make install    # Install Python dependencies
make lint       # Run flake8 + black style check
make test       # Run pytest with coverage
make build      # Build Docker image locally
make run        # Start app via Docker Compose
make stop       # Stop Docker Compose
make push       # Push image to Docker Hub
make deploy     # One-shot Minikube deployment
make logs       # Tail Kubernetes pod logs
make clean      # Remove images + stop Minikube
```

---

## 🐛 Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `permission denied` on Docker socket | User not in docker group | `sudo usermod -aG docker $USER && newgrp docker` |
| `minikube start` fails | VT-x not enabled | Enable virtualization in BIOS, or use `--driver=none` (requires sudo) |
| `ImagePullBackOff` in pods | Wrong image name or private repo | Verify `DOCKERHUB_USERNAME` in `deployment.yml` matches Docker Hub username |
| GitHub Actions `secret not found` | Secret name mismatch | Check exact secret names in Settings → Secrets. Case-sensitive. |
| `CrashLoopBackOff` | App crashing at startup | Run `kubectl logs <pod-name>` to see error |
| Port 5000 already in use | Another process on port | `sudo lsof -i :5000 \| awk 'NR>1 {print $2}' \| xargs kill` |
| `flake8` fails in Actions | Code style issues | Run `flake8 app/` locally and fix before pushing |
| Coverage below 80% | Insufficient test coverage | Add tests; check `coverage.xml` for uncovered lines |
| Minikube `node not ready` | Resource exhaustion | `minikube stop && minikube start --memory=4096` |

---

## 🔑 Security Notes

- Docker Hub credentials are stored **only as GitHub Secrets**, never in code
- The Docker image runs as a **non-root user** (`appuser`, UID 1000)
- Container drops **all Linux capabilities** (`DROP ALL`)
- Trivy scans for HIGH/CRITICAL CVEs on every build
- Kubernetes liveness/readiness probes ensure only healthy pods serve traffic

---

## 📜 License

MIT License — free to use, modify, and distribute.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Commit changes: `git commit -m "feat: add your feature"`
4. Push and open a Pull Request
5. GitHub Actions will automatically lint and test your PR

---

*Built with ❤️ using GitHub Actions, Docker, and Kubernetes*
