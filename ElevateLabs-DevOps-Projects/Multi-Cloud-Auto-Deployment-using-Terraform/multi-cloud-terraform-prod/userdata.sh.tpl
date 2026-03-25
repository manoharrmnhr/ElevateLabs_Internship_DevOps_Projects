#!/usr/bin/env bash
# =============================================================================
#  userdata.sh.tpl  ─  Cloud-agnostic NGINX bootstrap (rendered by Terraform)
#  Variables injected: cloud, region, cloud_color, text_color, bg_gradient
# =============================================================================
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

echo "[INFO] Starting NGINX bootstrap for ${cloud}..."

# ── System update & package install ─────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y --no-install-recommends
apt-get install -y nginx curl jq unzip wget

# ── Gather instance metadata ────────────────────────
CLOUD="${cloud}"
INSTANCE_ID=$(curl -sf --max-time 3 \
  -H "X-aws-ec2-metadata-token: $(curl -sf -X PUT \
    'http://169.254.169.254/latest/api/token' \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')" \
  http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "N/A")
REGION="${region}"
HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── Landing page ─────────────────────────────────────
cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${cloud} — Tri-Cloud Demo</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:'Segoe UI',Arial,sans-serif;background:${bg_gradient};
         min-height:100vh;display:flex;justify-content:center;align-items:center}
    .card{background:#fff;border-radius:16px;padding:48px 40px;
          box-shadow:0 20px 60px rgba(0,0,0,.25);max-width:520px;width:90%;
          text-align:center}
    .badge{display:inline-block;background:${cloud_color};color:#fff;
           padding:6px 18px;border-radius:20px;font-size:.85rem;
           font-weight:700;letter-spacing:.05em;margin-bottom:20px}
    h1{font-size:2rem;color:${text_color};margin-bottom:8px}
    h1 span{color:${cloud_color}}
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
    <h1>&#9729;&#65039; Running on <span>${cloud}</span></h1>
    <p style="color:#777;margin-top:8px;font-size:.95rem">
      Provisioned by Terraform · NGINX Web Server
    </p>
    <div class="info">
      <p><span>Instance / VM</span><strong>$INSTANCE_ID</strong></p>
      <p><span>Region / Zone</span><strong>$REGION</strong></p>
      <p><span>Hostname</span><strong>$HOSTNAME</strong></p>
      <p><span>Deployed At</span><strong>$TIMESTAMP</strong></p>
    </div>
    <div class="status">
      <div class="dot"></div> Server Healthy
    </div>
  </div>
</body>
</html>
HTML

# ── Health-check JSON endpoint ───────────────────────
mkdir -p /var/www/html/health
cat > /var/www/html/health/index.json <<JSON
{
  "status": "healthy",
  "cloud": "$CLOUD",
  "instance_id": "$INSTANCE_ID",
  "region": "$REGION",
  "hostname": "$HOSTNAME",
  "timestamp": "$TIMESTAMP",
  "nginx_version": "$(nginx -v 2>&1 | cut -d/ -f2)"
}
JSON

# Symlink for /health path
ln -sf /var/www/html/health/index.json /var/www/html/health.json

# ── NGINX config ────────────────────────────────────
cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        try_files $uri $uri/ =404;
    }

    location /health {
        alias /var/www/html/health;
        index index.json;
        default_type application/json;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    location /nginx_status {
        stub_status on;
        allow 127.0.0.1;
        deny all;
    }

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log;
}
NGINX

nginx -t
systemctl enable nginx
systemctl restart nginx

echo "[INFO] NGINX bootstrap complete for ${cloud}!"
