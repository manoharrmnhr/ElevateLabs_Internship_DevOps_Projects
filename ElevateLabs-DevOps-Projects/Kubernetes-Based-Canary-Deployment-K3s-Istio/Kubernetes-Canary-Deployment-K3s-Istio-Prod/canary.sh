#!/usr/bin/env bash
# ==============================================================================
# canary.sh — Production Canary Deployment Manager
#
# Commands:
#   canary.sh deploy          — deploy both versions to K3s
#   canary.sh status          — show live traffic split & pod health
#   canary.sh shift <weight>  — set canary traffic weight (0-100)
#   canary.sh promote         — full promotion to canary (100%)
#   canary.sh rollback        — instant rollback to stable (100%)
#   canary.sh auto            — automated progressive rollout
#   canary.sh monitor         — live metrics dashboard in terminal
#   canary.sh loadtest [n]    — send N requests and show distribution
#   canary.sh cleanup         — delete all resources
# ==============================================================================
set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
readonly NS="canary-demo"
readonly VS_NAME="demo-app-vs"

# SLO thresholds for automated promotion
readonly ERROR_THRESHOLD=5      # % — rollback if canary exceeds this
readonly LATENCY_THRESHOLD=400  # ms — warn if canary avg exceeds this
readonly SOAK_TIME=60           # seconds to wait between auto-shift steps
readonly AUTO_STEPS=(10 20 50 100)

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; MAG='\033[0;35m'
BLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
ts()     { date '+%H:%M:%S'; }
info()   { echo -e "${GRN}[$(ts)] ✓${RST}  $*"; }
warn()   { echo -e "${YLW}[$(ts)] ⚠${RST}  $*"; }
error()  { echo -e "${RED}[$(ts)] ✗${RST}  $*" >&2; }
step()   { echo -e "\n${BLU}${BLD}━━━ $* ━━━${RST}"; }
die()    { error "$*"; exit 1; }

# ── Prerequisites check ───────────────────────────────────────────────────────
require() {
  for cmd in "$@"; do
    command -v "${cmd}" &>/dev/null || die "Required command '${cmd}' not found"
  done
}

# ── Get current canary weight from VirtualService annotation ─────────────────
get_canary_weight() {
  kubectl get vs "${VS_NAME}" -n "${NS}" \
    -o jsonpath='{.metadata.annotations.traffic\.canary/canary-weight}' \
    2>/dev/null || echo "0"
}

# ── Get metrics from a pod ────────────────────────────────────────────────────
get_pod_metric() {
  local pod="$1" metric="$2"
  kubectl exec "${pod}" -n "${NS}" -c app -- \
    wget -qO- http://localhost:3000/metrics 2>/dev/null \
    | grep "^${metric}{" | awk '{print $2}' | head -1
}

# ── Get the first running pod for a track ────────────────────────────────────
get_pod() {
  kubectl get pods -n "${NS}" -l "app=demo-app,track=$1" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

# ── Apply traffic weight via patching VirtualService ─────────────────────────
apply_weight() {
  local canary_w=$1
  local stable_w=$((100 - canary_w))
  local phase
  case "${canary_w}" in
    0)   phase="rolled-back" ;;
    100) phase="promoted"    ;;
    *)   phase="in-progress" ;;
  esac

  info "Applying traffic split → stable: ${stable_w}%, canary: ${canary_w}%"

  kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ${VS_NAME}
  namespace: ${NS}
  annotations:
    traffic.canary/stable-weight: "${stable_w}"
    traffic.canary/canary-weight: "${canary_w}"
    traffic.canary/phase:         "${phase}"
    traffic.canary/updated-at:    "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
spec:
  hosts:
  - "demo-app.local"
  - demo-app
  gateways:
  - demo-app-gateway
  - mesh
  http:
  - name: canary-force
    match:
    - headers:
        x-canary:
          exact: "force"
    route:
    - destination:
        host:   demo-app
        subset: canary
      weight: 100
  - name: weight-split
    route:
    - destination:
        host:   demo-app
        subset: stable
      weight: ${stable_w}
    - destination:
        host:   demo-app
        subset: canary
      weight: ${canary_w}
    timeout: 10s
    retries:
      attempts: 3
      perTryTimeout: 3s
      retryOn: "gateway-error,connect-failure,5xx"
EOF
}

# ── Check SLOs for canary ─────────────────────────────────────────────────────
check_canary_slo() {
  local pod
  pod=$(get_pod "canary")
  [[ -z "${pod}" ]] && { warn "No canary pods running — skipping SLO check"; return 0; }

  local err_rate latency_ms
  err_rate=$(get_pod_metric "${pod}" "app_error_rate_pct" || echo "0")
  latency_ms=$(get_pod_metric "${pod}" "app_latency_avg_ms" || echo "0")

  err_rate=${err_rate:-0}
  latency_ms=${latency_ms:-0}

  info "Canary SLO check → error_rate=${err_rate}%  avg_latency=${latency_ms}ms"

  # Use bc for float comparison
  local err_fail latency_warn
  err_fail=$(echo "${err_rate} > ${ERROR_THRESHOLD}" | bc -l 2>/dev/null || echo "0")
  latency_warn=$(echo "${latency_ms} > ${LATENCY_THRESHOLD}" | bc -l 2>/dev/null || echo "0")

  if [[ "${err_fail}" == "1" ]]; then
    error "SLO BREACH: error rate ${err_rate}% > threshold ${ERROR_THRESHOLD}%"
    return 1
  fi
  if [[ "${latency_warn}" == "1" ]]; then
    warn "Latency elevated: ${latency_ms}ms > ${LATENCY_THRESHOLD}ms — monitor closely"
  fi
  return 0
}

# ==============================================================================
# COMMANDS
# ==============================================================================

cmd_deploy() {
  step "Building Docker images"
  require docker

  info "Building demo-app:v1.0.0 (stable)"
  docker build -q -t demo-app:v1.0.0 "${PROJECT_DIR}/app/v1/" \
    || die "Failed to build v1 image"

  info "Building demo-app:v2.0.0 (canary)"
  docker build -q -t demo-app:v2.0.0 "${PROJECT_DIR}/app/v2/" \
    || die "Failed to build v2 image"

  step "Importing images into K3s containerd"
  docker save demo-app:v1.0.0 | sudo k3s ctr images import - \
    || die "Failed to import v1 image"
  docker save demo-app:v2.0.0 | sudo k3s ctr images import - \
    || die "Failed to import v2 image"

  sudo k3s ctr images list | grep demo-app
  info "Images imported successfully"

  step "Applying Kubernetes manifests"
  kubectl apply -f "${PROJECT_DIR}/k8s/00-namespace.yaml"
  kubectl apply -f "${PROJECT_DIR}/k8s/01-deployment-stable.yaml"
  kubectl apply -f "${PROJECT_DIR}/k8s/02-deployment-canary.yaml"
  kubectl apply -f "${PROJECT_DIR}/k8s/03-services.yaml"

  step "Waiting for pods to be Ready"
  kubectl wait --for=condition=ready pod \
    -n "${NS}" -l app=demo-app \
    --timeout=120s

  step "Applying Istio configuration"
  kubectl apply -f "${PROJECT_DIR}/istio/01-gateway.yaml"
  kubectl apply -f "${PROJECT_DIR}/istio/02-destination-rule.yaml"
  kubectl apply -f "${PROJECT_DIR}/istio/03-vs-80-20.yaml"

  echo ""
  info "✅  Deployment complete!"
  cmd_status
}

cmd_status() {
  step "Canary Deployment Status"

  local canary_w
  canary_w=$(get_canary_weight)
  local stable_w=$((100 - canary_w))

  echo ""
  echo -e "  ${BLD}Traffic Split${RST}"
  echo -e "  ${GRN}●${RST} Stable (v1):  ${BLD}${stable_w}%${RST}"
  echo -e "  ${MAG}●${RST} Canary (v2):  ${BLD}${canary_w}%${RST}"
  echo ""

  echo -e "  ${BLD}Pod Health${RST}"
  kubectl get pods -n "${NS}" -l app=demo-app \
    -o custom-columns='  NAME:.metadata.name,TRACK:.metadata.labels.track,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount' \
    --no-headers 2>/dev/null || echo "  No pods found"
  echo ""

  echo -e "  ${BLD}Services${RST}"
  kubectl get svc -n "${NS}" --no-headers -o wide 2>/dev/null | \
    awk '{printf "  %-20s %-12s %-20s\n", $1, $2, $3}'
  echo ""

  echo -e "  ${BLD}Istio Resources${RST}"
  kubectl get gateway,destinationrule,virtualservice -n "${NS}" \
    --no-headers 2>/dev/null | awk '{printf "  %-40s %s\n", $1, $2}'
  echo ""
}

cmd_shift() {
  local weight="${1:-}"
  [[ -z "${weight}" ]] && die "Usage: canary.sh shift <0-100>"
  [[ "${weight}" =~ ^[0-9]+$ ]] || die "Weight must be a number between 0 and 100"
  [[ "${weight}" -ge 0 && "${weight}" -le 100 ]] || die "Weight must be 0-100"

  step "Shifting canary traffic to ${weight}%"
  apply_weight "${weight}"
  info "Done. Run 'canary.sh status' to verify."
}

cmd_promote() {
  step "Promoting canary to 100% production"

  info "Running final SLO check before promotion..."
  check_canary_slo || die "SLO check failed — aborting promotion. Run rollback instead."

  apply_weight 100

  echo ""
  warn "Canary is now serving 100% of traffic."
  info "Post-promotion steps:"
  info "  1. kubectl set image deployment/app-stable app=demo-app:v2.0.0 -n ${NS}"
  info "  2. kubectl scale deployment/app-canary --replicas=0 -n ${NS}"
  info "  3. Wait for stable rollout: kubectl rollout status deployment/app-stable -n ${NS}"
  info "  4. Apply rollback VS (stable subset now runs v2): canary.sh shift 0"
  info "  5. Scale canary back to 1 for next release cycle"
}

cmd_rollback() {
  step "EMERGENCY ROLLBACK — routing 100% traffic to stable"
  warn "Reason: $(get_canary_weight)% canary traffic redirected to stable immediately"

  apply_weight 0
  kubectl apply -f "${PROJECT_DIR}/istio/06-vs-rollback.yaml" 2>/dev/null || true

  info "✅  Rollback complete. All traffic on stable."
  info "Canary pod logs for investigation:"
  local pod
  pod=$(get_pod "canary")
  [[ -n "${pod}" ]] && kubectl logs "${pod}" -n "${NS}" -c app --tail=50 2>/dev/null || true
}

cmd_auto() {
  step "Automated Canary Progressive Rollout"
  info "Steps: ${AUTO_STEPS[*]}%  |  Soak: ${SOAK_TIME}s  |  Error threshold: ${ERROR_THRESHOLD}%"
  echo ""

  for weight in "${AUTO_STEPS[@]}"; do
    info "── Step: ${weight}% ──────────────────────────────────────"
    apply_weight "${weight}"
    info "Soaking for ${SOAK_TIME}s..."

    local elapsed=0
    while [[ "${elapsed}" -lt "${SOAK_TIME}" ]]; do
      sleep 10
      elapsed=$((elapsed + 10))
      if ! check_canary_slo; then
        error "SLO breach at ${weight}%! Initiating automatic rollback..."
        cmd_rollback
        exit 1
      fi
      info "Health check passed at ${weight}% (${elapsed}/${SOAK_TIME}s)"
    done

    info "✓ Stable at ${weight}% for ${SOAK_TIME}s"
    echo ""
  done

  info "🎉  Canary successfully promoted to 100%!"
  info "Run 'canary.sh promote' to complete the post-promotion steps."
}

cmd_monitor() {
  step "Live Canary Metrics Monitor (Ctrl+C to stop)"
  while true; do
    clear
    echo -e "${BLD}${CYN}Canary Deployment Monitor — $(date)${RST}"
    echo -e "${DIM}Refresh: 5s | Namespace: ${NS}${RST}\n"

    local cw sw
    cw=$(get_canary_weight)
    sw=$((100 - cw))

    echo -e "  ${BLD}Traffic:${RST} Stable ${GRN}${sw}%${RST}  Canary ${MAG}${cw}%${RST}"
    echo ""

    for track in stable canary; do
      local pod
      pod=$(get_pod "${track}")
      if [[ -n "${pod}" ]]; then
        local err lat req
        err=$(get_pod_metric "${pod}" "app_error_rate_pct" || echo "N/A")
        lat=$(get_pod_metric "${pod}" "app_latency_avg_ms" || echo "N/A")
        req=$(get_pod_metric "${pod}" "app_http_requests_total" || echo "N/A")
        color="${GRN}"; [[ "${track}" == "canary" ]] && color="${MAG}"
        printf "  ${color}%-8s${RST}  Pod: %-40s  Req: %-6s  Err: %-6s%%  Lat: %sms\n" \
          "${track}" "${pod}" "${req}" "${err}" "${lat}"
      else
        echo -e "  ${track}: no running pods"
      fi
    done
    echo ""
    echo -e "  ${DIM}Commands: shift | promote | rollback | auto${RST}"
    sleep 5
  done
}

cmd_loadtest() {
  local n="${1:-100}"
  require curl
  step "Load Test: ${n} requests"

  local port
  port=$(kubectl get svc istio-ingressgateway -n istio-system \
    -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || echo "80")

  info "Ingress port: ${port}"
  info "Sending ${n} requests to http://localhost:${port}/ (Host: demo-app.local)"
  echo ""

  local s=0 c=0 e=0
  for i in $(seq 1 "${n}"); do
    local ver
    ver=$(curl -s --max-time 5 \
      -H "Host: demo-app.local" \
      -H "Accept: application/json" \
      -o /dev/null -w "%{header{x-app-version}}" \
      "http://localhost:${port}/" 2>/dev/null || echo "error")

    if   [[ "${ver}" == *"v1"* ]]; then ((s++))
    elif [[ "${ver}" == *"v2"* ]]; then ((c++))
    else ((e++))
    fi
    [[ $((i % 10)) -eq 0 ]] && printf "  %3d/%d — stable: %d  canary: %d  errors: %d\n" \
      "${i}" "${n}" "${s}" "${c}" "${e}"
  done

  echo ""
  echo -e "${BLD}Results (${n} requests):${RST}"
  echo -e "  ${GRN}Stable (v1):${RST}  ${s}  ($(( s * 100 / n ))%)"
  echo -e "  ${MAG}Canary (v2):${RST}  ${c}  ($(( c * 100 / n ))%)"
  echo -e "  ${RED}Errors:${RST}       ${e}  ($(( e * 100 / n ))%)"
}

cmd_cleanup() {
  step "Cleaning up all resources"
  warn "This will delete the namespace and all resources in it."
  read -r -p "  Continue? [y/N] " confirm
  [[ "${confirm}" == [yY] ]] || { info "Aborted."; exit 0; }

  kubectl delete namespace "${NS}" --ignore-not-found=true
  info "Namespace ${NS} deleted."
}

# ==============================================================================
# ENTRYPOINT
# ==============================================================================
require kubectl

CMD="${1:-help}"
shift || true

case "${CMD}" in
  deploy)    cmd_deploy    ;;
  status)    cmd_status    ;;
  shift)     cmd_shift  "$@" ;;
  promote)   cmd_promote   ;;
  rollback)  cmd_rollback  ;;
  auto)      cmd_auto      ;;
  monitor)   cmd_monitor   ;;
  loadtest)  cmd_loadtest "$@" ;;
  cleanup)   cmd_cleanup   ;;
  help|--help|-h)
    echo ""
    echo -e "${BLD}Usage: canary.sh <command> [args]${RST}"
    echo ""
    echo "  deploy              Build images, deploy both versions, configure Istio"
    echo "  status              Show traffic split, pod health, Istio resources"
    echo "  shift <0-100>       Set canary traffic weight percentage"
    echo "  promote             Promote canary to 100% (with SLO gate)"
    echo "  rollback            Emergency rollback to 100% stable"
    echo "  auto                Automated progressive rollout (10→20→50→100%)"
    echo "  monitor             Live terminal metrics dashboard"
    echo "  loadtest [n=100]    Send N requests and show version distribution"
    echo "  cleanup             Delete namespace and all resources"
    echo ""
    ;;
  *)
    error "Unknown command: ${CMD}"
    echo "Run 'canary.sh --help' for usage."
    exit 1
    ;;
esac
