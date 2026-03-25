#!/usr/bin/env bash
###############################################################################
# chaos_simulator.sh — Chaos Engineering Scenarios
# Based on principles from: Netflix Chaos Monkey, Gremlin, LitmusChaos
#
# Scenarios:
#   1. Pod Kill (random pod termination)
#   2. Node Drain (simulate node failure)
#   3. Network Partition (block traffic to service)
#   4. CPU Bomb (saturate CPU on node)
#   5. Memory Leak Simulation
#   6. DNS Failure
#   7. Disk I/O Saturation
#   8. Cascading Failure (multi-service)
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'

NAMESPACE="${CHAOS_NAMESPACE:-self-healing}"
DEPLOYMENT="${CHAOS_TARGET:-nginx}"
LOG_FILE="/var/log/chaos-engineering.log"

log()     { echo -e "${BLUE}[$(date +'%H:%M:%S')] CHAOS${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[OK]${NC} $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; echo -e "${BOLD}$*${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

mkdir -p "$(dirname "$LOG_FILE")"
echo "$(date -Iseconds) | Chaos experiment started" >> "$LOG_FILE"

# ─── Helper: wait for recovery ────────────────────────────────────────────────
wait_for_recovery() {
  local service="$1"
  local max_wait="${2:-180}"
  local interval=5
  local elapsed=0

  log "Waiting for $service to recover (max ${max_wait}s)..."
  while [ $elapsed -lt $max_wait ]; do
    READY=$(kubectl get deployment "$service" -n "$NAMESPACE" \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment "$service" -n "$NAMESPACE" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    if [ "${READY:-0}" == "$DESIRED" ]; then
      success "✅ $service recovered in ${elapsed}s (${READY}/${DESIRED} replicas ready)"
      echo "$(date -Iseconds) | RECOVERY | $service | ${elapsed}s" >> "$LOG_FILE"
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
    echo -n "."
  done
  warn "⚠️  $service did NOT recover within ${max_wait}s"
  return 1
}

# ─── Scenario 1: Random Pod Kill ──────────────────────────────────────────────
chaos_pod_kill() {
  section "🎯 SCENARIO 1: Random Pod Kill"
  log "Target namespace: $NAMESPACE | Deployment: $DEPLOYMENT"

  # Get a random pod
  POD=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | shuf | head -1)

  if [ -z "$POD" ]; then
    warn "No pods found for $DEPLOYMENT"
    return 1
  fi

  log "Killing pod: $POD"
  echo "$(date -Iseconds) | KILL | $POD" >> "$LOG_FILE"

  kubectl delete pod "$POD" -n "$NAMESPACE" --grace-period=0 --force
  success "Pod $POD deleted"

  wait_for_recovery "$DEPLOYMENT"
}

# ─── Scenario 2: Kill ALL pods (complete service disruption) ──────────────────
chaos_kill_all_pods() {
  section "💥 SCENARIO 2: Kill ALL Pods (Complete Disruption)"
  warn "This simulates a complete service crash"

  PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    -o jsonpath='{.items[*].metadata.name}')
  POD_COUNT=$(echo "$PODS" | wc -w)

  log "Killing all $POD_COUNT pods of $DEPLOYMENT"
  kubectl delete pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    --grace-period=0 --force

  echo "$(date -Iseconds) | KILL_ALL | $DEPLOYMENT | $POD_COUNT pods" >> "$LOG_FILE"

  wait_for_recovery "$DEPLOYMENT" 300
}

# ─── Scenario 3: Network Policy Block ────────────────────────────────────────
chaos_network_block() {
  section "🌐 SCENARIO 3: Network Policy Block (Traffic Cutoff)"
  log "Applying blocking NetworkPolicy to $DEPLOYMENT"

  # Apply deny-all network policy
  kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: chaos-deny-all-${DEPLOYMENT}
  namespace: ${NAMESPACE}
  labels:
    chaos: "true"
    experiment: "network-block"
spec:
  podSelector:
    matchLabels:
      app: ${DEPLOYMENT}
  policyTypes:
    - Ingress
    - Egress
EOF
  success "Network policy applied — all traffic to/from $DEPLOYMENT is BLOCKED"
  echo "$(date -Iseconds) | NETWORK_BLOCK | $DEPLOYMENT" >> "$LOG_FILE"

  log "Waiting 60s for alert detection..."
  sleep 60

  log "Removing blocking NetworkPolicy (healing simulation)..."
  kubectl delete networkpolicy "chaos-deny-all-${DEPLOYMENT}" -n "$NAMESPACE"
  success "Network policy removed — traffic restored"
  echo "$(date -Iseconds) | NETWORK_RESTORED | $DEPLOYMENT" >> "$LOG_FILE"
}

# ─── Scenario 4: CPU Stress on pod ────────────────────────────────────────────
chaos_cpu_stress() {
  section "🔥 SCENARIO 4: CPU Stress Injection"
  log "Injecting CPU stress into $DEPLOYMENT pods"

  POD=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    -o jsonpath='{.items[0].metadata.name}')

  log "Target pod: $POD"
  log "Running CPU stress for 3 minutes..."
  echo "$(date -Iseconds) | CPU_STRESS_START | $POD" >> "$LOG_FILE"

  # Run stress in the container (requires stress binary)
  kubectl exec -n "$NAMESPACE" "$POD" -- sh -c \
    "apt-get install -y stress -qq 2>/dev/null; stress --cpu 4 --timeout 180 &" \
    || kubectl exec -n "$NAMESPACE" "$POD" -- sh -c \
    "yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null &
     sleep 180; kill %1 %2 %3 %4 2>/dev/null" &

  log "CPU stress injected. Monitor: kubectl top pods -n $NAMESPACE"
  log "Prometheus should fire HighCPUUsage within 5m"
  echo "$(date -Iseconds) | CPU_STRESS_END | $POD" >> "$LOG_FILE"
}

# ─── Scenario 5: Memory Exhaustion ────────────────────────────────────────────
chaos_memory_stress() {
  section "💾 SCENARIO 5: Memory Stress Injection"
  POD=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    -o jsonpath='{.items[0].metadata.name}')

  log "Injecting memory stress into $POD for 2 minutes..."
  echo "$(date -Iseconds) | MEMORY_STRESS | $POD" >> "$LOG_FILE"

  kubectl exec -n "$NAMESPACE" "$POD" -- sh -c \
    "python3 -c \"
import time
data = []
for i in range(100):
    data.append(' ' * 10**6)  # Allocate ~100MB
    time.sleep(0.1)
time.sleep(120)
del data
\"" &
  success "Memory stress injected. OOMKiller may trigger."
}

# ─── Scenario 6: Cascading Failure Simulation ─────────────────────────────────
chaos_cascading_failure() {
  section "🌊 SCENARIO 6: Cascading Failure"
  warn "Simulating cascading failure: NGINX → Alertmanager → Recovery loop"

  log "Step 1: Kill NGINX"
  kubectl delete pods -n "$NAMESPACE" -l app=nginx --grace-period=0 --force 2>/dev/null || true
  sleep 10

  log "Step 2: Kill Alertmanager"
  kubectl delete pods -n "$NAMESPACE" -l app=alertmanager --grace-period=0 --force 2>/dev/null || true
  sleep 5

  log "Step 3: Scale down webhook-receiver to 0"
  kubectl scale deployment webhook-receiver -n "$NAMESPACE" --replicas=0
  echo "$(date -Iseconds) | CASCADE_TRIGGER" >> "$LOG_FILE"

  log "Cascading failure injected. Recovery should auto-heal all components."
  log "Waiting 120s..."
  sleep 30

  log "Restoring webhook-receiver..."
  kubectl scale deployment webhook-receiver -n "$NAMESPACE" --replicas=2

  wait_for_recovery "nginx" 300
  wait_for_recovery "alertmanager" 120
  wait_for_recovery "webhook-receiver" 60
}

# ─── Scenario 7: Litmus Chaos Integration ─────────────────────────────────────
chaos_litmus_pod_delete() {
  section "⚗️  SCENARIO 7: LitmusChaos Pod Delete Experiment"

  if ! kubectl get ns litmus &>/dev/null; then
    log "Installing LitmusChaos..."
    kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v3.3.0.yaml
    sleep 30
  fi

  kubectl apply -f - <<EOF
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: nginx-chaos
  namespace: ${NAMESPACE}
spec:
  appinfo:
    appns: ${NAMESPACE}
    applabel: app=nginx
    appkind: deployment
  chaosServiceAccount: litmus-admin
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "60"
            - name: CHAOS_INTERVAL
              value: "15"
            - name: FORCE
              value: "false"
            - name: PODS_AFFECTED_PERC
              value: "50"
EOF
  success "LitmusChaos experiment submitted"
  log "Monitor: kubectl get chaosresult -n $NAMESPACE"
}

# ─── Report ───────────────────────────────────────────────────────────────────
generate_report() {
  section "📊 CHAOS EXPERIMENT REPORT"
  echo ""
  echo "  Log file: $LOG_FILE"
  echo ""
  echo "  Results:"
  cat "$LOG_FILE" | grep -E "(KILL|NETWORK|STRESS|CASCADE|RECOVERY)" | \
    awk -F'|' '{printf "  %-30s | %-20s | %s\n", $1, $2, $3}' 2>/dev/null || true
  echo ""
  echo "  Deployment status:"
  kubectl get deployments -n "$NAMESPACE" 2>/dev/null || true
}

# ─── Menu ─────────────────────────────────────────────────────────────────────
case "${1:-menu}" in
  pod-kill)     chaos_pod_kill ;;
  kill-all)     chaos_kill_all_pods ;;
  network)      chaos_network_block ;;
  cpu)          chaos_cpu_stress ;;
  memory)       chaos_memory_stress ;;
  cascade)      chaos_cascading_failure ;;
  litmus)       chaos_litmus_pod_delete ;;
  report)       generate_report ;;
  all)
    chaos_pod_kill
    sleep 30
    chaos_network_block
    sleep 30
    chaos_kill_all_pods
    generate_report
    ;;
  *)
    echo -e "${BOLD}Usage:${NC} $0 [scenario]"
    echo ""
    echo "  Scenarios:"
    echo "    pod-kill    — Delete a random pod"
    echo "    kill-all    — Delete ALL pods (complete outage)"
    echo "    network     — Block all network traffic for 60s"
    echo "    cpu         — Inject CPU stress"
    echo "    memory      — Inject memory pressure"
    echo "    cascade     — Cascading multi-service failure"
    echo "    litmus      — LitmusChaos experiment"
    echo "    all         — Run all scenarios sequentially"
    echo "    report      — Generate experiment report"
    ;;
esac
