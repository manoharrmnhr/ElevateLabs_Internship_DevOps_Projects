#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
#  scripts/deploy-local.sh
#  One-shot script to start Minikube and deploy the app
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

DOCKERHUB_USER="${1:-YOUR_DOCKERHUB_USERNAME}"
IMAGE="$DOCKERHUB_USER/cicd-flask-app:latest"

echo "=============================================="
echo "  CI/CD Pipeline — Local Minikube Deployment"
echo "=============================================="

# 1. Start Minikube
echo -e "\n[1/5] Starting Minikube..."
if minikube status | grep -q "Running"; then
  echo "  ✓ Minikube already running"
else
  minikube start --driver=docker --memory=2048 --cpus=2
  echo "  ✓ Minikube started"
fi

# 2. Update image in deployment
echo -e "\n[2/5] Patching deployment image to: $IMAGE"
sed -i "s|YOUR_DOCKERHUB_USERNAME|$DOCKERHUB_USER|g" k8s/deployment.yml

# 3. Apply manifests
echo -e "\n[3/5] Applying Kubernetes manifests..."
kubectl apply -f k8s/configmap.yml
kubectl apply -f k8s/deployment.yml
kubectl apply -f k8s/service.yml
echo "  ✓ Manifests applied"

# 4. Wait for rollout
echo -e "\n[4/5] Waiting for rollout to complete..."
kubectl rollout status deployment/cicd-flask-app --timeout=120s
echo "  ✓ Deployment ready"

# 5. Print access URL
echo -e "\n[5/5] Getting service URL..."
URL=$(minikube service cicd-flask-service --url)
echo ""
echo "=============================================="
echo "  ✅ App is LIVE at: $URL"
echo "  Health check    : $URL/health"
echo "  Metrics         : $URL/metrics"
echo "=============================================="

# Optional: open in browser
# xdg-open "$URL" 2>/dev/null || open "$URL" 2>/dev/null || true
