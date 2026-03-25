#!/usr/bin/env bash
# =============================================================================
# stress-test.sh  –  Trigger alert conditions for sandbox testing
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

command -v stress-ng &>/dev/null || {
  echo -e "${YELLOW}Installing stress-ng...${NC}"
  apt-get install -y -qq stress-ng
}

print_menu() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║   Monitoring Sandbox – Stress Tester ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
  echo " 1) Spike CPU to 90%+ for 3 minutes"
  echo " 2) Fill memory to 85% for 2 minutes"
  echo " 3) Simulate heavy disk I/O for 2 minutes"
  echo " 4) Run all tests sequentially"
  echo " 5) Exit"
  echo ""
}

cpu_stress() {
  echo -e "${RED}Stressing CPU (3 minutes)...${NC}"
  CPUS=$(nproc)
  stress-ng --cpu "${CPUS}" --cpu-load 90 --timeout 180s &
  echo "PID: $! — Watch Grafana CPU panel and check Alertmanager at :9093"
  wait
}

memory_stress() {
  echo -e "${RED}Stressing Memory (2 minutes)...${NC}"
  TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
  TARGET=$(( TOTAL_MEM * 85 / 100 ))
  stress-ng --vm 1 --vm-bytes "${TARGET}M" --timeout 120s &
  echo "PID: $! — Watch Grafana Memory panel"
  wait
}

disk_stress() {
  echo -e "${RED}Stressing Disk I/O (2 minutes)...${NC}"
  stress-ng --hdd 2 --hdd-bytes 512M --timeout 120s &
  echo "PID: $! — Watch Grafana Disk I/O panel"
  wait
}

print_menu
read -rp "Select option [1-5]: " choice
case "${choice}" in
  1) cpu_stress ;;
  2) memory_stress ;;
  3) disk_stress ;;
  4) cpu_stress; memory_stress; disk_stress ;;
  5) exit 0 ;;
  *) echo "Invalid option"; exit 1 ;;
esac

echo -e "${GREEN}Test complete. Allow 2-5 min for alerts to fire in Alertmanager.${NC}"
