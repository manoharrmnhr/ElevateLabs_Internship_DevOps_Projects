#!/usr/bin/env bash
# =============================================================================
# health-check.sh  –  Verify all monitoring services are running correctly
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}✔ PASS${NC}  $*"; }
fail() { echo -e "  ${RED}✘ FAIL${NC}  $*"; FAILURES=$((FAILURES+1)); }
info() { echo -e "  ${YELLOW}ℹ INFO${NC}  $*"; }

FAILURES=0

echo ""
echo "======================================================"
echo "  DevOps Monitoring Sandbox – Health Check"
echo "======================================================"
echo ""

# --- Service status ---
echo "[ Systemd Services ]"
for svc in node_exporter prometheus alertmanager grafana-server; do
  if systemctl is-active --quiet "${svc}" 2>/dev/null; then
    pass "${svc} is running"
  else
    fail "${svc} is NOT running"
  fi
done

echo ""
echo "[ HTTP Endpoints ]"

check_http() {
  local name="$1" url="$2" expected="${3:-200}"
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${url}" 2>/dev/null || echo "000")
  if [ "${code}" = "${expected}" ]; then
    pass "${name} → ${url} (HTTP ${code})"
  else
    fail "${name} → ${url} (HTTP ${code}, expected ${expected})"
  fi
}

check_http "Node Exporter" "http://localhost:9100/metrics"
check_http "Prometheus"    "http://localhost:9090/-/healthy"
check_http "Alertmanager"  "http://localhost:9093/-/healthy"
check_http "Grafana"       "http://localhost:3000/api/health"

echo ""
echo "[ Prometheus Targets ]"
TARGETS=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  [print(t['labels']['job'], t['health']) for t in d['data']['activeTargets']]" 2>/dev/null || echo "Error")
if [ "${TARGETS}" != "Error" ]; then
  while IFS=' ' read -r job health; do
    if [ "${health}" = "up" ]; then
      pass "Target ${job} → ${health}"
    else
      fail "Target ${job} → ${health}"
    fi
  done <<< "${TARGETS}"
else
  fail "Could not query Prometheus API"
fi

echo ""
echo "[ Alert Rules ]"
RULES=$(curl -s "http://localhost:9090/api/v1/rules" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  groups=d['data']['groups']; \
  print(f'{sum(len(g[\"rules\"]) for g in groups)} rules in {len(groups)} groups')" 2>/dev/null || echo "Error")
if [ "${RULES}" != "Error" ]; then
  pass "Prometheus loaded: ${RULES}"
else
  fail "Could not query alert rules"
fi

echo ""
echo "======================================================"
if [ "${FAILURES}" -eq 0 ]; then
  echo -e "  ${GREEN}All checks passed! Sandbox is healthy.${NC}"
else
  echo -e "  ${RED}${FAILURES} check(s) failed. Review above.${NC}"
fi
echo "======================================================"
echo ""
