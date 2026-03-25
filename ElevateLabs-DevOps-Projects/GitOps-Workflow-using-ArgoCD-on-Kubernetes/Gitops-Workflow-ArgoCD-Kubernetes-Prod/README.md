# 🚀 GitOps Workflow using ArgoCD on Kubernetes

> **Production-Grade GitOps Pipeline** — Automating Kubernetes deployments via Git as the single source of truth.

![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-orange?style=for-the-badge&logo=argo)
![Kubernetes](https://img.shields.io/badge/Kubernetes-K3s%2FMinikube-blue?style=for-the-badge&logo=kubernetes)
![GitHub](https://img.shields.io/badge/GitHub-Actions-black?style=for-the-badge&logo=github)
![Docker](https://img.shields.io/badge/Docker-Container-2496ED?style=for-the-badge&logo=docker)

---

## 📋 Table of Contents

- [Project Overview](#-project-overview)
- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Repository Structure](#-repository-structure)
- [Step-by-Step Setup](#-step-by-step-setup)
  - [1. Kubernetes Cluster Setup](#1-kubernetes-cluster-setup)
  - [2. Install ArgoCD](#2-install-argocd)
  - [3. Access ArgoCD UI](#3-access-argocd-ui)
  - [4. Application Manifests](#4-application-manifests)
  - [5. Configure ArgoCD Application](#5-configure-argocd-application)
  - [6. Auto-Sync & GitOps Flow](#6-auto-sync--gitops-flow)
  - [7. Update & Observe Changes](#7-update--observe-changes)
- [Manifest Files Reference](#-manifest-files-reference)
- [GitOps Flow Explained](#-gitops-flow-explained)
- [ArgoCD Features Used](#-argocd-features-used)
- [Troubleshooting](#-troubleshooting)
- [Project Deliverables](#-project-deliverables)
- [References](#-references)

---

## 🎯 Project Overview

This project demonstrates a **production-grade GitOps pipeline** using **ArgoCD** and **Kubernetes**. Instead of manually applying `kubectl` commands, all deployment changes are driven by **Git commits**. ArgoCD continuously monitors the Git repository and automatically syncs the desired state to the cluster.

### Key Concepts
| Concept | Description |
|---|---|
| **GitOps** | Using Git as the single source of truth for infrastructure and application state |
| **ArgoCD** | Declarative, GitOps continuous delivery tool for Kubernetes |
| **Auto-Sync** | ArgoCD detects Git changes and reconciles cluster state automatically |
| **Drift Detection** | ArgoCD alerts when cluster state diverges from Git |

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitOps Workflow                          │
│                                                                 │
│  Developer  ──push──►  GitHub Repo  ◄──poll── ArgoCD           │
│                         (manifests)             │               │
│                                                 │ sync          │
│                                                 ▼               │
│                                        Kubernetes Cluster       │
│                                        ┌──────────────────┐    │
│                                        │  Namespace: app  │    │
│                                        │  ┌────────────┐  │    │
│                                        │  │ Deployment │  │    │
│                                        │  │  (nginx)   │  │    │
│                                        │  └────────────┘  │    │
│                                        │  ┌────────────┐  │    │
│                                        │  │  Service   │  │    │
│                                        │  │ (NodePort) │  │    │
│                                        │  └────────────┘  │    │
│                                        └──────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✅ Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Minikube or K3s | Latest | Local Kubernetes cluster |
| kubectl | v1.28+ | Kubernetes CLI |
| ArgoCD CLI | v2.9+ | ArgoCD management |
| Docker | 24.x | Container runtime |
| Git | 2.x | Version control |
| GitHub Account | — | Remote Git repository |

---

## 📁 Repository Structure

```
gitops-argocd-k8s/
├── README.md
├── apps/
│   └── sample-app/
│       ├── deployment.yaml        # App Deployment manifest
│       ├── service.yaml           # App Service manifest
│       └── namespace.yaml         # Namespace definition
├── argocd/
│   ├── argocd-app.yaml            # ArgoCD Application CRD
│   └── argocd-install.yaml        # Optional: custom install config
├── docker/
│   └── Dockerfile                 # Sample app Dockerfile
└── screenshots/
    ├── argocd-synced.png
    ├── argocd-app-healthy.png
    └── argocd-diff-view.png
```

---

## 🔧 Step-by-Step Setup

### 1. Kubernetes Cluster Setup

#### Option A — Minikube
```bash
# Install Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Start cluster
minikube start --cpus=2 --memory=4096 --driver=docker

# Verify
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   1m    v1.28.3
```

#### Option B — K3s (Lightweight, recommended for servers)
```bash
# Install K3s
curl -sfL https://get.k3s.io | sh -

# Set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Verify
kubectl get nodes
```

---

### 2. Install ArgoCD

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Verify all pods running
kubectl get pods -n argocd
# NAME                                                READY   STATUS    RESTARTS
# argocd-application-controller-0                    1/1     Running   0
# argocd-dex-server-xxxx                             1/1     Running   0
# argocd-redis-xxxx                                  1/1     Running   0
# argocd-repo-server-xxxx                            1/1     Running   0
# argocd-server-xxxx                                 1/1     Running   0
```

---

### 3. Access ArgoCD UI

```bash
# Method 1: Port-forward (recommended for local)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Open browser: https://localhost:8080
# Username: admin
# Password: (from above command)

# Method 2: NodePort (Minikube)
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "NodePort"}}'
minikube service argocd-server -n argocd --url

# Method 3: Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd

# Login via CLI
argocd login localhost:8080 --username admin \
  --password <PASSWORD> --insecure
```

---

### 4. Application Manifests

Create the following files and push to your GitHub repository.

#### `apps/sample-app/namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: sample-app
  labels:
    managed-by: argocd
    environment: production
```

#### `apps/sample-app/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-app
  namespace: sample-app
  labels:
    app: nginx-app
    version: "1.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: nginx-app
        version: "1.0"
    spec:
      containers:
      - name: nginx
        image: nginx:1.25.3          # <-- Change this tag to trigger GitOps update
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
```

#### `apps/sample-app/service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-app-svc
  namespace: sample-app
  labels:
    app: nginx-app
spec:
  type: NodePort
  selector:
    app: nginx-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
    nodePort: 30080
```

#### Push to GitHub
```bash
# Initialize local repo
git init gitops-argocd-k8s && cd gitops-argocd-k8s

# Create directory structure
mkdir -p apps/sample-app argocd docker screenshots

# (Copy all manifest files here)

# Commit and push
git add .
git commit -m "feat: initial GitOps manifests for nginx app v1.0"
git remote add origin https://github.com/<YOUR_USERNAME>/gitops-argocd-k8s.git
git push -u origin main
```

---

### 5. Configure ArgoCD Application

#### `argocd/argocd-app.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-gitops-app
  namespace: argocd
  labels:
    project: gitops-demo
spec:
  project: default
  source:
    repoURL: https://github.com/<YOUR_USERNAME>/gitops-argocd-k8s.git
    targetRevision: HEAD
    path: apps/sample-app
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
  syncPolicy:
    automated:                    # ← Enables Auto-Sync (GitOps magic!)
      prune: true                 # Remove resources deleted from Git
      selfHeal: true              # Revert manual cluster changes
    syncOptions:
    - CreateNamespace=true        # Auto-create namespace
    - PrunePropagationPolicy=foreground
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

#### Apply the ArgoCD Application
```bash
# Apply via kubectl
kubectl apply -f argocd/argocd-app.yaml

# OR register via CLI
argocd app create nginx-gitops-app \
  --repo https://github.com/<YOUR_USERNAME>/gitops-argocd-k8s.git \
  --path apps/sample-app \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace sample-app \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# Check app status
argocd app get nginx-gitops-app
```

---

### 6. Auto-Sync & GitOps Flow

```bash
# Watch ArgoCD sync in real-time
watch -n 2 'argocd app get nginx-gitops-app'

# Check application health
argocd app list
# NAME               CLUSTER                         NAMESPACE   PROJECT  STATUS  HEALTH
# nginx-gitops-app   https://kubernetes.default.svc  sample-app  default  Synced  Healthy

# View running pods
kubectl get pods -n sample-app -w
# NAME                         READY   STATUS    RESTARTS   AGE
# nginx-app-xxxxxxxxx-xxxxx    1/1     Running   0          2m
# nginx-app-xxxxxxxxx-xxxxx    1/1     Running   0          2m

# Access the application
minikube service nginx-app-svc -n sample-app --url
# http://127.0.0.1:30080
```

---

### 7. Update & Observe Changes

This is the **core GitOps demo** — update via Git, watch ArgoCD deploy:

```bash
# Step 1: Update image version in deployment.yaml
# Change: image: nginx:1.25.3
# To:     image: nginx:1.25.4

sed -i 's/nginx:1.25.3/nginx:1.25.4/' apps/sample-app/deployment.yaml

# Step 2: Commit and push
git add apps/sample-app/deployment.yaml
git commit -m "feat: upgrade nginx from 1.25.3 to 1.25.4"
git push origin main

# Step 3: Watch ArgoCD auto-sync (within ~3 minutes by default)
watch -n 5 'kubectl get pods -n sample-app'
# You will observe RollingUpdate replacing old pods with new ones!

# Step 4: Scale replicas via Git
sed -i 's/replicas: 2/replicas: 4/' apps/sample-app/deployment.yaml
git add . && git commit -m "scale: increase replicas to 4 for load"
git push

# Step 5: Demonstrate self-healing — manually scale down (drift)
kubectl scale deployment nginx-app -n sample-app --replicas=1
# Wait ~30 seconds — ArgoCD will auto-correct back to 4!
kubectl get pods -n sample-app
# ArgoCD restores desired 4 replicas from Git definition

# Force immediate sync (instead of waiting for poll)
argocd app sync nginx-gitops-app
```

---

## 📄 Manifest Files Reference

| File | Purpose | Key Fields |
|---|---|---|
| `namespace.yaml` | Creates isolated namespace | `metadata.name` |
| `deployment.yaml` | Defines app pods & strategy | `image`, `replicas`, `probes` |
| `service.yaml` | Exposes app via NodePort | `type: NodePort`, `nodePort` |
| `argocd-app.yaml` | ArgoCD Application CR | `repoURL`, `syncPolicy.automated` |

---

## 🔄 GitOps Flow Explained

```
1. DEVELOPER makes code/config change
        │
        ▼
2. Git commit pushed to GitHub (manifests updated)
        │
        ▼
3. ARGOCD polls repo every 3 minutes (or webhook)
        │
        ▼
4. ArgoCD detects DIFF between Git state vs Cluster state
        │
        ▼
5. Auto-Sync triggered → kubectl apply equivalent runs
        │
        ▼
6. Kubernetes performs RollingUpdate / reconciliation
        │
        ▼
7. ArgoCD reports: Synced ✅ | Healthy ✅
        │
        ▼
8. If manual drift detected → selfHeal restores Git state
```

---

## ⚙️ ArgoCD Features Used

| Feature | Config | Benefit |
|---|---|---|
| **Auto-Sync** | `syncPolicy.automated` | No manual sync needed |
| **Self-Heal** | `selfHeal: true` | Reverts unauthorized changes |
| **Auto-Prune** | `prune: true` | Cleans deleted resources |
| **Retry Logic** | `retry.limit: 5` | Handles transient failures |
| **Health Checks** | Built-in | Monitors pod/service status |
| **Diff View** | UI/CLI | Shows Git vs live state |

---

## 🔍 Troubleshooting

| Issue | Solution |
|---|---|
| ArgoCD pods not starting | `kubectl describe pod <pod> -n argocd` |
| App stuck in `OutOfSync` | `argocd app sync nginx-gitops-app --force` |
| Repo not accessible | Check repo URL & credentials in ArgoCD settings |
| Self-heal not working | Verify `selfHeal: true` in syncPolicy |
| NodePort unreachable (Minikube) | Run `minikube tunnel` or use port-forward |
| Image pull error | Check Docker Hub rate limits; use `imagePullPolicy: IfNotPresent` |

```bash
# View ArgoCD server logs
kubectl logs -n argocd deploy/argocd-server -f

# View application events
kubectl describe application nginx-gitops-app -n argocd

# Get sync history
argocd app history nginx-gitops-app
```

---

## 📦 Project Deliverables

- [x] ✅ Git repository with all manifest files (`apps/`, `argocd/`)
- [x] ✅ ArgoCD Application configured with auto-sync & self-heal
- [x] ✅ Deployment updated via Git commit (image version upgrade)
- [x] ✅ Self-healing demonstrated (manual drift auto-corrected)
- [x] ✅ README with complete step-by-step guide
- [x] ✅ PDF Project Report (Introduction → Conclusion)

---

## 📚 References

- [ArgoCD Official Documentation](https://argo-cd.readthedocs.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GitOps Principles — OpenGitOps](https://opengitops.dev/)
- [Minikube Getting Started](https://minikube.sigs.k8s.io/docs/start/)
- [K3s Lightweight Kubernetes](https://k3s.io/)

---

## 👨‍💻 Author

**Implemented GitOps pipeline using ArgoCD and Kubernetes**

> *"In GitOps, the Git repository is the only truth. The cluster is just its reflection."*

---

<p align="center">
  Made with ❤️ using ArgoCD + Kubernetes + GitOps
</p>
