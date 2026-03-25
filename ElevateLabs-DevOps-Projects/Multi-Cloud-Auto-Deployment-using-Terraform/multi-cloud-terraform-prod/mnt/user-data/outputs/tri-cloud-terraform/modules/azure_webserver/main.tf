# =============================================================================
#  modules/azure_webserver/main.tf
#  Provisions: Resource Group • VNet • Subnet • NSG • Public IP
#              NIC • Linux VM (Ubuntu 22.04) • NGINX via custom_data
# =============================================================================

# ── Resource Group ────────────────────────────────────
resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-rg"
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Cloud       = "Azure"
  }
}

# ── Virtual Network ───────────────────────────────────
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.project_name}-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = { Name = "${var.project_name}-vnet" }
}

# ── Subnet ────────────────────────────────────────────
resource "azurerm_subnet" "public" {
  name                 = "${var.project_name}-subnet-public"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.20.1.0/24"]
}

# ── Network Security Group ────────────────────────────
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.project_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { Name = "${var.project_name}-nsg" }
}

# ── NSG → Subnet Association ──────────────────────────
resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ── Public IP ─────────────────────────────────────────
resource "azurerm_public_ip" "web_ip" {
  name                = "${var.project_name}-pip-${var.suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]

  tags = { Name = "${var.project_name}-public-ip" }
}

# ── Network Interface ─────────────────────────────────
resource "azurerm_network_interface" "nic" {
  name                = "${var.project_name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web_ip.id
  }

  tags = { Name = "${var.project_name}-nic" }
}

# ── NIC → NSG Association ─────────────────────────────
resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ── Linux Virtual Machine ─────────────────────────────
resource "azurerm_linux_virtual_machine" "web" {
  name                  = "${var.project_name}-azure-web"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # NGINX bootstrap via cloud-init
  custom_data = base64encode(<<-CLOUDINIT
    #!/usr/bin/env bash
    set -euo pipefail
    exec > >(tee /var/log/azure-init.log | logger -t azure-init) 2>&1

    echo "[INFO] Azure NGINX bootstrap starting..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get upgrade -y --no-install-recommends
    apt-get install -y nginx curl jq

    VM_NAME=$(curl -sf -H "Metadata:true" --noproxy "*" \
      "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text" \
      || echo "${var.project_name}-azure-web")
    LOCATION=$(curl -sf -H "Metadata:true" --noproxy "*" \
      "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text" \
      || echo "eastus")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width,initial-scale=1.0">
      <title>Azure — Tri-Cloud Demo</title>
      <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:'Segoe UI',Arial,sans-serif;
             background:linear-gradient(135deg,#0078D4,#004578);
             min-height:100vh;display:flex;justify-content:center;align-items:center}
        .card{background:#fff;border-radius:16px;padding:48px 40px;
              box-shadow:0 20px 60px rgba(0,0,0,.25);max-width:520px;width:90%;text-align:center}
        .badge{display:inline-block;background:#0078D4;color:#fff;
               padding:6px 18px;border-radius:20px;font-size:.85rem;
               font-weight:700;letter-spacing:.05em;margin-bottom:20px}
        h1{font-size:2rem;color:#004578;margin-bottom:8px}
        h1 span{color:#0078D4}
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
        <h1>&#9729;&#65039; Running on <span>Azure</span></h1>
        <p style="color:#777;margin-top:8px;font-size:.95rem">
          Provisioned by Terraform · NGINX Web Server
        </p>
        <div class="info">
          <p><span>VM Name</span><strong>$VM_NAME</strong></p>
          <p><span>Region</span><strong>$LOCATION</strong></p>
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
    {"status":"healthy","cloud":"Azure","vm_name":"$VM_NAME","region":"$LOCATION","timestamp":"$TIMESTAMP"}
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
    echo "[INFO] Azure NGINX bootstrap complete!"
  CLOUDINIT
  )

  tags = {
    Name        = "${var.project_name}-azure-web"
    Cloud       = "Azure"
    Environment = var.environment
  }
}
