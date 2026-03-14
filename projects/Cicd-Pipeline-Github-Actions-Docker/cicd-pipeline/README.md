# 🚀 CI/CD Pipeline with GitHub Actions & Docker

A complete CI/CD pipeline that automatically builds a Docker image, runs tests, pushes to Docker Hub, and deploys locally using Minikube — **no cloud required**.

---

## 📁 Project Structure

```
cicd-pipeline/
├── app/
│   ├── app.py               # Flask application
│   ├── requirements.txt     # Python dependencies
│   └── tests/
│       └── test_app.py      # Unit tests
├── Dockerfile               # Docker image definition
├── docker-compose.yml       # Local multi-container setup
├── .github/
│   └── workflows/
│       └── ci-cd.yml        # GitHub Actions workflow
├── k8s/
│   ├── deployment.yml       # Kubernetes Deployment manifest
│   └── service.yml          # Kubernetes Service manifest
└── README.md
```

---

## 🛠️ Tools & Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | 24+ | Containerization |
| Docker Hub | Free | Image registry |
| GitHub Actions | — | CI/CD automation |
| Minikube | 1.32+ | Local Kubernetes cluster |
| kubectl | 1.28+ | Kubernetes CLI |
| Python | 3.11+ | App runtime |
| Flask | 3.0+ | Web framework |

---

## 📋 Step-by-Step Setup Guide

### Step 1 — Install Prerequisites

#### Install Docker
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker
```

#### Install Minikube
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

#### Install kubectl
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

---

### Step 2 — Create the Flask Application

**`app/app.py`**
```python
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify({"message": "Hello from CI/CD Pipeline!", "status": "running"})

@app.route("/health")
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
```

**`app/requirements.txt`**
```
flask==3.0.0
pytest==7.4.3
pytest-flask==1.3.0
```

**`app/tests/test_app.py`**
```python
import pytest
from app import app

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

def test_home(client):
    response = client.get("/")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "running"

def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "healthy"
```

---

### Step 3 — Write the Dockerfile

**`Dockerfile`**
```dockerfile
# Use official Python slim image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy and install dependencies
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY app/ .

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

# Run the app
CMD ["python", "app.py"]
```

---

### Step 4 — Write docker-compose.yml

**`docker-compose.yml`**
```yaml
version: "3.9"

services:
  web:
    build: .
    container_name: cicd-app
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=production
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

#### Test Locally with Docker Compose
```bash
docker-compose up --build
# Visit http://localhost:5000 to verify
docker-compose down
```

---

### Step 5 — Configure GitHub Actions Workflow

#### 5a. Create Docker Hub Secrets in GitHub
1. Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions**
2. Add the following secrets:
   - `DOCKERHUB_USERNAME` — your Docker Hub username
   - `DOCKERHUB_TOKEN` — your Docker Hub access token (create at hub.docker.com → Account Settings → Security)

#### 5b. Create the Workflow File

**`.github/workflows/ci-cd.yml`**
```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  IMAGE_NAME: ${{ secrets.DOCKERHUB_USERNAME }}/cicd-flask-app

jobs:
  # ── Job 1: Run Tests ──────────────────────────────────
  test:
    name: Run Unit Tests
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r app/requirements.txt

      - name: Run tests
        run: |
          cd app
          pytest tests/ -v --tb=short

  # ── Job 2: Build & Push Docker Image ─────────────────
  build-and-push:
    name: Build & Push to Docker Hub
    runs-on: ubuntu-latest
    needs: test

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.IMAGE_NAME }}:latest
            ${{ env.IMAGE_NAME }}:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ── Job 3: Notify Deployment Ready ───────────────────
  notify:
    name: Deployment Ready
    runs-on: ubuntu-latest
    needs: build-and-push

    steps:
      - name: Print deployment info
        run: |
          echo "✅ Image pushed: ${{ env.IMAGE_NAME }}:latest"
          echo "✅ Commit SHA tag: ${{ github.sha }}"
          echo "🚀 Ready to deploy with Minikube!"
```

---

### Step 6 — Push to GitHub

```bash
git init
git add .
git commit -m "feat: initial CI/CD pipeline setup"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/cicd-pipeline.git
git push -u origin main
```

After pushing, navigate to **Actions** tab in GitHub to watch the pipeline run automatically.

---

### Step 7 — Create Kubernetes Manifests

**`k8s/deployment.yml`**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cicd-flask-app
  labels:
    app: cicd-flask-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cicd-flask-app
  template:
    metadata:
      labels:
        app: cicd-flask-app
    spec:
      containers:
        - name: flask-app
          image: YOUR_DOCKERHUB_USERNAME/cicd-flask-app:latest
          ports:
            - containerPort: 5000
          livenessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 15
            periodSeconds: 20
          resources:
            requests:
              memory: "64Mi"
              cpu: "250m"
            limits:
              memory: "128Mi"
              cpu: "500m"
```

**`k8s/service.yml`**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: cicd-flask-service
spec:
  selector:
    app: cicd-flask-app
  type: NodePort
  ports:
    - protocol: TCP
      port: 80
      targetPort: 5000
      nodePort: 30080
```

---

### Step 8 — Deploy Locally with Minikube

```bash
# Start Minikube
minikube start --driver=docker

# Verify cluster is running
kubectl cluster-info
kubectl get nodes

# Apply Kubernetes manifests
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service.yml

# Wait for pods to be ready
kubectl rollout status deployment/cicd-flask-app

# Get the service URL
minikube service cicd-flask-service --url

# Open in browser (opens automatically)
minikube service cicd-flask-service
```

#### Useful kubectl Commands
```bash
# View all pods
kubectl get pods

# View pod logs
kubectl logs -l app=cicd-flask-app

# Describe deployment
kubectl describe deployment cicd-flask-app

# Scale up/down
kubectl scale deployment cicd-flask-app --replicas=3

# Delete resources
kubectl delete -f k8s/
minikube stop
```

---

### Step 9 — Update Deployment (Rolling Update)

When you push new code to `main`, GitHub Actions builds and pushes a new image automatically. To update your Minikube deployment:

```bash
# Pull latest image and restart pods
kubectl rollout restart deployment/cicd-flask-app

# Watch rollout progress
kubectl rollout status deployment/cicd-flask-app

# Rollback if needed
kubectl rollout undo deployment/cicd-flask-app
```

---

## ✅ CI/CD Pipeline Flow

```
Developer pushes code
        │
        ▼
┌─────────────────┐
│  GitHub Actions │
│  Triggered      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Job 1: Test    │ ← pytest runs all unit tests
│  (ubuntu-latest)│
└────────┬────────┘
         │  (only if tests pass)
         ▼
┌─────────────────┐
│ Job 2: Build &  │ ← Docker image built & pushed
│ Push to Hub     │   to Docker Hub
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Job 3: Notify   │ ← Deployment ready notification
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Local Minikube  │ ← Pull image & deploy manually
│ Deployment      │   or via webhook trigger
└─────────────────┘
```

---

## 🐛 Troubleshooting

| Issue | Fix |
|-------|-----|
| `docker: permission denied` | Run `sudo usermod -aG docker $USER && newgrp docker` |
| `minikube start` fails | Try `minikube start --driver=virtualbox` or `--driver=none` |
| Image pull error in Minikube | Run `minikube ssh` then `docker pull YOUR_IMAGE` |
| GitHub Actions secrets not found | Verify secret names match exactly in workflow YAML |
| Port 5000 already in use | Run `sudo lsof -i :5000` and kill the process |

---

## 📊 Expected Results

- ✅ All GitHub Actions jobs pass (green checkmarks)
- ✅ Docker image visible at `hub.docker.com/r/YOUR_USERNAME/cicd-flask-app`
- ✅ App accessible at Minikube service URL (e.g., `http://192.168.49.2:30080`)
- ✅ `/health` endpoint returns `{"status": "healthy"}`

---

## 📄 License

MIT License — free to use and modify.
