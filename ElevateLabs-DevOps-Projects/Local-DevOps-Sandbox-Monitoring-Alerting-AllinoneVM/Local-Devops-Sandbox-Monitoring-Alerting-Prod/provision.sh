#!/usr/bin/env bash
# =============================================================================
# DevOps Monitoring Sandbox – Provision Script
# Installs: Prometheus, Grafana, Node Exporter, Alertmanager
# Tested on: Ubuntu 22.04 LTS
# =============================================================================
set -euo pipefail

# ---------- Versions ----------
PROMETHEUS_VERSION="2.51.2"
NODE_EXPORTER_VERSION="1.7.0"
ALERTMANAGER_VERSION="0.27.0"
GRAFANA_VERSION="10.4.2"

INSTALL_DIR="/opt/monitoring"
CONFIG_DIR="${INSTALL_DIR}/configs"
DATA_DIR="${INSTALL_DIR}/data"

# ---------- Colors ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# =============================================================================
# 0. System Prerequisites
# =============================================================================
log "Updating system packages..."
apt-get update -qq
apt-get install -y -qq \
  curl wget tar gzip adduser libfontconfig1 \
  apt-transport-https software-properties-common gnupg2 \
  net-tools htop vim jq unzip

mkdir -p "${DATA_DIR}"/{prometheus,alertmanager}

# =============================================================================
# 1. Node Exporter
# =============================================================================
log "Installing Node Exporter ${NODE_EXPORTER_VERSION}..."
useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

NE_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
wget -q "${NE_URL}" -O /tmp/node_exporter.tar.gz
tar -xzf /tmp/node_exporter.tar.gz -C /tmp
cp "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --collector.systemd \
  --collector.processes \
  --web.listen-address=0.0.0.0:9100

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# 2. Prometheus
# =============================================================================
log "Installing Prometheus ${PROMETHEUS_VERSION}..."
useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true

PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
wget -q "${PROM_URL}" -O /tmp/prometheus.tar.gz
tar -xzf /tmp/prometheus.tar.gz -C /tmp
PROM_DIR="/tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64"
cp "${PROM_DIR}/prometheus" /usr/local/bin/
cp "${PROM_DIR}/promtool"   /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/{prometheus,promtool}

mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /var/lib/prometheus

# Copy configs from synced folder (Vagrant) or local path (bare-metal)
if [ -f "${CONFIG_DIR}/prometheus/prometheus.yml" ]; then
  cp "${CONFIG_DIR}/prometheus/prometheus.yml"  /etc/prometheus/prometheus.yml
  cp "${CONFIG_DIR}/prometheus/alert_rules.yml" /etc/prometheus/alert_rules.yml
else
  warn "Config files not found in ${CONFIG_DIR}. Using bundled defaults."
  # Configs are embedded below as a fallback
  create_default_prometheus_config
fi
chown -R prometheus:prometheus /etc/prometheus

cat > /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus Monitoring
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=15d \
  --web.listen-address=0.0.0.0:9090 \
  --web.enable-lifecycle \
  --web.enable-admin-api
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# 3. Alertmanager
# =============================================================================
log "Installing Alertmanager ${ALERTMANAGER_VERSION}..."
useradd --no-create-home --shell /bin/false alertmanager 2>/dev/null || true

AM_URL="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
wget -q "${AM_URL}" -O /tmp/alertmanager.tar.gz
tar -xzf /tmp/alertmanager.tar.gz -C /tmp
AM_DIR="/tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64"
cp "${AM_DIR}/alertmanager" /usr/local/bin/
cp "${AM_DIR}/amtool"       /usr/local/bin/
chown alertmanager:alertmanager /usr/local/bin/{alertmanager,amtool}

mkdir -p /etc/alertmanager "${DATA_DIR}/alertmanager"
chown alertmanager:alertmanager /etc/alertmanager "${DATA_DIR}/alertmanager"

if [ -f "${CONFIG_DIR}/alertmanager/alertmanager.yml" ]; then
  cp "${CONFIG_DIR}/alertmanager/alertmanager.yml" /etc/alertmanager/alertmanager.yml
fi
chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

cat > /etc/systemd/system/alertmanager.service <<EOF
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=${DATA_DIR}/alertmanager \
  --web.listen-address=0.0.0.0:9093
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# =============================================================================
# 4. Grafana
# =============================================================================
log "Installing Grafana ${GRAFANA_VERSION}..."
GRAFANA_DEB="grafana_${GRAFANA_VERSION}_amd64.deb"
wget -q "https://dl.grafana.com/oss/release/${GRAFANA_DEB}" -O "/tmp/${GRAFANA_DEB}"
dpkg -i "/tmp/${GRAFANA_DEB}" 2>&1 | tail -5

# Grafana provisioning
GRAFANA_PROV="/etc/grafana/provisioning"
mkdir -p "${GRAFANA_PROV}/datasources" "${GRAFANA_PROV}/dashboards"

if [ -d "${CONFIG_DIR}/grafana/provisioning" ]; then
  cp "${CONFIG_DIR}/grafana/provisioning/datasources/"* "${GRAFANA_PROV}/datasources/"
  cp "${CONFIG_DIR}/grafana/provisioning/dashboards/"*  "${GRAFANA_PROV}/dashboards/"
fi

if [ -d "${CONFIG_DIR}/grafana/dashboards" ]; then
  mkdir -p /var/lib/grafana/dashboards
  cp "${CONFIG_DIR}/grafana/dashboards/"* /var/lib/grafana/dashboards/
  chown -R grafana:grafana /var/lib/grafana/dashboards
fi

# =============================================================================
# 5. Enable & Start Services
# =============================================================================
log "Enabling and starting services..."
systemctl daemon-reload

for svc in node_exporter prometheus alertmanager grafana-server; do
  systemctl enable  "${svc}" > /dev/null 2>&1
  systemctl restart "${svc}"
  sleep 2
  if systemctl is-active --quiet "${svc}"; then
    log "✔  ${svc} is running"
  else
    warn "✘  ${svc} failed – check: journalctl -u ${svc}"
  fi
done

# =============================================================================
# 6. Firewall (ufw)
# =============================================================================
log "Configuring firewall..."
ufw allow 3000/tcp comment "Grafana"    > /dev/null 2>&1 || true
ufw allow 9090/tcp comment "Prometheus" > /dev/null 2>&1 || true
ufw allow 9093/tcp comment "Alertmanager" > /dev/null 2>&1 || true
ufw allow 9100/tcp comment "Node Exporter" > /dev/null 2>&1 || true

# =============================================================================
log "============================================================"
log " Provisioning COMPLETE!"
log " Grafana      → http://192.168.56.10:3000  (admin/admin)"
log " Prometheus   → http://192.168.56.10:9090"
log " Alertmanager → http://192.168.56.10:9093"
log "============================================================"
