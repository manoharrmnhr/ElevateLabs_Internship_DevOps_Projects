# =============================================================================
#  modules/gcp_webserver/main.tf
#  Provisions: VPC Network • Subnet • Firewall Rules (HTTP, SSH, ICMP)
#              Static External IP • GCE e2-micro (Ubuntu 22.04) • NGINX
# =============================================================================

# ── VPC Network ───────────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
  description             = "Tri-cloud project VPC — GCP"
}

# ── Subnet ────────────────────────────────────────────
resource "google_compute_subnetwork" "public" {
  name          = "${var.project_name}-subnet-public"
  ip_cidr_range = "10.30.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.vpc.id

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ── Firewall: Allow HTTP / HTTPS ──────────────────────
resource "google_compute_firewall" "allow_http" {
  name    = "${var.project_name}-allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server", "nginx"]
  description   = "Allow inbound HTTP/HTTPS from anywhere"
}

# ── Firewall: Allow SSH ───────────────────────────────
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.project_name}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]   # Restrict to your IP in production
  target_tags   = ["web-server"]
  description   = "Allow SSH access"
}

# ── Firewall: Allow ICMP Ping ─────────────────────────
resource "google_compute_firewall" "allow_icmp" {
  name    = "${var.project_name}-allow-icmp"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
  description   = "Allow ping for health monitoring"
}

# ── Static External IP ────────────────────────────────
resource "google_compute_address" "web_ip" {
  name         = "${var.project_name}-web-ip"
  region       = var.gcp_region
  address_type = "EXTERNAL"
  description  = "Static IP for GCP NGINX web server"
}

# ── GCE Instance ──────────────────────────────────────
resource "google_compute_instance" "web" {
  name         = "${var.project_name}-gcp-web"
  machine_type = var.machine_type
  zone         = var.gcp_zone
  description  = "Tri-cloud NGINX web server on GCP"

  tags = ["web-server", "nginx", var.environment]

  boot_disk {
    initialize_params {
      image  = "ubuntu-os-cloud/ubuntu-2204-lts"
      size   = 10
      type   = "pd-standard"
    }
    auto_delete = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    access_config {
      nat_ip = google_compute_address.web_ip.address
    }
  }

  # Enforce metadata server security
  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "false"
    serial-port-enable     = "FALSE"
  }

  metadata_startup_script = <<-SCRIPT
    #!/usr/bin/env bash
    set -euo pipefail
    exec > >(tee /var/log/startup-script.log | logger -t startup-script) 2>&1

    echo "[INFO] GCP NGINX bootstrap starting..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y --no-install-recommends
    apt-get install -y nginx curl jq

    # Fetch GCP metadata
    META="http://metadata.google.internal/computeMetadata/v1"
    H="Metadata-Flavor: Google"
    INSTANCE_NAME=$(curl -sf -H "$H" "$META/instance/name" || echo "${var.project_name}-gcp-web")
    ZONE=$(curl -sf -H "$H" "$META/instance/zone" | awk -F/ '{print $NF}')
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width,initial-scale=1.0">
      <title>GCP — Tri-Cloud Demo</title>
      <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:'Segoe UI',Arial,sans-serif;
             background:linear-gradient(135deg,#4285F4,#0D47A1);
             min-height:100vh;display:flex;justify-content:center;align-items:center}
        .card{background:#fff;border-radius:16px;padding:48px 40px;
              box-shadow:0 20px 60px rgba(0,0,0,.25);max-width:520px;width:90%;text-align:center}
        .badge{display:inline-block;background:#4285F4;color:#fff;
               padding:6px 18px;border-radius:20px;font-size:.85rem;
               font-weight:700;letter-spacing:.05em;margin-bottom:20px}
        h1{font-size:2rem;color:#1A73E8;margin-bottom:8px}
        h1 span{color:#4285F4}
        .info{margin-top:24px;background:#f8f9fa;border-radius:10px;
              padding:16px;text-align:left;font-size:.88rem}
        .info p{display:flex;justify-content:space-between;
                padding:6px 0;border-bottom:1px solid #eee;color:#555}
        .info p:last-child{border-bottom:none}
        .info p strong{color:#333}
        .status{display:inline-flex;align-items:center;gap:6px;
                margin-top:20px;font-weight:600;color:#2e7d32;font-size:.95rem}
        .dot{width:10px;height:10px;background:#4caf50;
             border-radius:50%;animation:pulse 2s infinite}
        @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
      </style>
    </head>
    <body>
      <div class="card">
        <div class="badge">Tri-Cloud Deployment</div>
        <h1>&#9729;&#65039; Running on <span>GCP</span></h1>
        <p style="color:#777;margin-top:8px;font-size:.95rem">
          Provisioned by Terraform · NGINX Web Server
        </p>
        <div class="info">
          <p><span>Instance</span><strong>$INSTANCE_NAME</strong></p>
          <p><span>Zone</span><strong>$ZONE</strong></p>
          <p><span>Hostname</span><strong>$(hostname)</strong></p>
          <p><span>Deployed At</span><strong>$TIMESTAMP</strong></p>
        </div>
        <div class="status"><div class="dot"></div> Server Healthy</div>
      </div>
    </body>
    </html>
HTML

    mkdir -p /var/www/html/health
    cat > /var/www/html/health/index.json <<JSON
    {"status":"healthy","cloud":"GCP","instance":"$INSTANCE_NAME","zone":"$ZONE","timestamp":"$TIMESTAMP"}
JSON

    cat > /etc/nginx/sites-available/default <<'NGINX'
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        root /var/www/html;
        index index.html;
        server_name _;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        location / { try_files $uri $uri/ =404; }
        location /health {
            alias /var/www/html/health;
            index index.json;
            default_type application/json;
            add_header Cache-Control "no-cache";
        }
    }
NGINX

    nginx -t
    systemctl enable nginx
    systemctl restart nginx
    echo "[INFO] GCP NGINX bootstrap complete!"
  SCRIPT

  service_account {
    email  = google_service_account.web_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
    cloud       = "gcp"
    role        = "web-server"
  }
}

# ── Service Account for VM ────────────────────────────
resource "google_service_account" "web_sa" {
  account_id   = "${var.project_name}-web-sa"
  display_name = "Tri-Cloud Web Server SA"
  project      = var.gcp_project
}
