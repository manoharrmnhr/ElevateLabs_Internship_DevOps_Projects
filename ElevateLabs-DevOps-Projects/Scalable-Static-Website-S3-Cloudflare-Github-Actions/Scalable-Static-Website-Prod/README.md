# ⚡ CloudStatic — Scalable Static Website with S3 + Cloudflare + GitHub Actions

<div align="center">

[![Deploy to S3](https://github.com/YOUR_USERNAME/cloudstatic/actions/workflows/deploy.yml/badge.svg)](https://github.com/YOUR_USERNAME/cloudstatic/actions)
[![HTTPS](https://img.shields.io/badge/HTTPS-Enabled-brightgreen)](https://www.yourdomain.com)
[![CDN](https://img.shields.io/badge/CDN-Cloudflare-orange)](https://cloudflare.com)
[![Hosting](https://img.shields.io/badge/Hosting-AWS%20S3-yellow)](https://aws.amazon.com/s3)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

**Production-grade static website hosting using AWS S3, Cloudflare CDN, and GitHub Actions CI/CD.**

[🌐 Live Demo](https://www.yourdomain.com) · [📋 Report](docs/deployment_report.pdf) · [⚙️ Workflow](.github/workflows/deploy.yml)

</div>

---

## 📑 Table of Contents

1. [Architecture](#-architecture)
2. [Project Structure](#-project-structure)
3. [Prerequisites](#-prerequisites)
4. [Step 1 — Create & Configure AWS S3 Bucket](#step-1--create--configure-aws-s3-bucket)
5. [Step 2 — Create IAM User for CI/CD](#step-2--create-iam-user-for-cicd)
6. [Step 3 — Cloudflare DNS & SSL Setup](#step-3--cloudflare-dns--ssl-setup)
7. [Step 4 — Configure GitHub Repository Secrets](#step-4--configure-github-repository-secrets)
8. [Step 5 — Understand the CI/CD Workflow](#step-5--understand-the-cicd-workflow)
9. [Step 6 — Cache Strategy & Versioning](#step-6--cache-strategy--versioning)
10. [Step 7 — First Deploy & Testing](#step-7--first-deploy--testing)
11. [Troubleshooting Guide](#-troubleshooting-guide)
12. [Cost Analysis](#-cost-analysis)

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     DEPLOYMENT PIPELINE                              │
│                                                                       │
│  Developer  →  git push  →  GitHub  →  Actions Workflow              │
│                                             │                         │
│                                    ┌────────┴────────┐               │
│                                    │                  │               │
│                              Validate Job       Deploy Job            │
│                              (HTML check)   (AWS S3 Sync)            │
│                                                    │                  │
│                                          S3 sync per asset type       │
│                                          Cloudflare cache purge       │
│                                          HTTP smoke test              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     TRAFFIC FLOW                                      │
│                                                                       │
│  User Browser  →  DNS Lookup  →  Cloudflare Edge (300+ nodes)        │
│                                        │                              │
│                                   Cache HIT → Serve instantly         │
│                                   Cache MISS → Fetch from S3          │
│                                        │                              │
│                                   AWS S3 Origin (ap-south-1)         │
│                                   (HTTPS via Cloudflare SSL)          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Project Structure

```
cloudstatic/
├── .github/
│   └── workflows/
│       └── deploy.yml          # Full CI/CD pipeline (12 steps)
├── src/                        # All static website files
│   ├── index.html              # Main homepage
│   ├── 404.html                # Custom error page
│   ├── css/
│   │   └── style.css           # Stylesheet (versioned: v1)
│   ├── js/
│   │   └── main.js             # JavaScript (versioned: v1)
│   └── assets/                 # Images, fonts, icons
│       └── (place assets here)
├── scripts/
│   └── setup-s3.sh             # Automated S3 bucket setup script
├── docs/
│   └── deployment_report.pdf   # Project report
└── README.md
```

---

## ✅ Prerequisites

| Tool | Version | Purpose | Cost |
|------|---------|---------|------|
| AWS Account | — | S3 bucket hosting | Free Tier |
| AWS CLI | v2+ | Local S3 management | Free |
| Cloudflare Account | — | CDN + SSL + DNS | Free |
| GitHub Account | — | Code repo + Actions | Free |
| A domain name | — | Custom HTTPS URL | ~$1/yr (.xyz) |
| Git | 2.x | Version control | Free |

### Install AWS CLI

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Verify
aws --version
# aws-cli/2.x.x Python/3.x.x ...

# Configure with your credentials
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: ap-south-1
# Default output format: json
```

---

## Step 1 — Create & Configure AWS S3 Bucket

### Option A: Automated (Recommended)

```bash
# Make the script executable
chmod +x scripts/setup-s3.sh

# Run it with your bucket name and region
./scripts/setup-s3.sh www.yourdomain.com ap-south-1
```

The script performs all 6 steps: create bucket → disable block public access → apply public-read policy → enable website hosting → enable versioning → enable AES-256 encryption.

### Option B: Manual (AWS Console)

#### 1.1 Create the bucket

1. Open [AWS S3 Console](https://s3.console.aws.amazon.com/s3/)
2. Click **Create bucket**
3. **Bucket name:** Must exactly match your domain — `www.yourdomain.com`
4. **AWS Region:** Choose closest to your users (e.g., `ap-south-1` Mumbai)
5. **Object Ownership:** ACLs enabled → Bucket owner preferred
6. **Block Public Access:** Uncheck all four checkboxes → confirm
7. Click **Create bucket**

#### 1.2 Enable Static Website Hosting

1. Open your bucket → **Properties** tab
2. Scroll to **Static website hosting** → **Edit**
3. Enable → **Index document:** `index.html` → **Error document:** `404.html`
4. **Save changes**
5. Note your **Bucket website endpoint**: `http://www.yourdomain.com.s3-website-ap-south-1.amazonaws.com`

#### 1.3 Apply Public-Read Bucket Policy

1. **Permissions** tab → **Bucket policy** → **Edit**
2. Paste the following (replace `www.yourdomain.com`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::www.yourdomain.com/*"
    }
  ]
}
```

3. **Save changes**

#### 1.4 Enable S3 Versioning (Rollback Support)

1. **Properties** tab → **Bucket Versioning** → **Edit**
2. Select **Enable** → **Save changes**

> **Rollback command:**
> ```bash
> # List versions and restore a previous one
> aws s3api list-object-versions --bucket www.yourdomain.com --prefix index.html
> aws s3api get-object --bucket www.yourdomain.com \
>   --key index.html --version-id <VERSION_ID> restored_index.html
> ```

---

## Step 2 — Create IAM User for CI/CD

GitHub Actions needs programmatic access to your S3 bucket. **Never use root credentials.**

#### 2.1 Create a scoped IAM Policy

1. AWS Console → **IAM** → **Policies** → **Create policy**
2. Select **JSON** and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3DeployAccess",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:PutObjectAcl",
        "s3:GetObjectAcl",
        "s3:HeadObject"
      ],
      "Resource": [
        "arn:aws:s3:::www.yourdomain.com",
        "arn:aws:s3:::www.yourdomain.com/*"
      ]
    }
  ]
}
```

3. Name: `CloudStaticGitHubDeploy` → **Create policy**

#### 2.2 Create the IAM User

```bash
# Using CLI
aws iam create-user --user-name github-actions-cloudstatic

# Attach the policy (replace ACCOUNT_ID)
aws iam attach-user-policy \
  --user-name github-actions-cloudstatic \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/CloudStaticGitHubDeploy
```

Or via Console: IAM → Users → Create user → `github-actions-cloudstatic` → Attach `CloudStaticGitHubDeploy` → Create.

#### 2.3 Generate Access Keys

```bash
aws iam create-access-key --user-name github-actions-cloudstatic
```

Output:
```json
{
  "AccessKey": {
    "AccessKeyId": "AKIAXXXXXXXXXXXXXXXXX",
    "SecretAccessKey": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  }
}
```

> ⚠️ **Save these immediately.** The Secret Access Key is shown only once.

---

## Step 3 — Cloudflare DNS & SSL Setup

#### 3.1 Add Domain to Cloudflare

1. Login to [dash.cloudflare.com](https://dash.cloudflare.com)
2. **Add a site** → enter your domain → **Free plan** → Continue
3. Cloudflare scans your DNS records
4. At your domain registrar (GoDaddy / Namecheap / Google Domains), update **nameservers** to the two Cloudflare nameservers shown (e.g., `aria.ns.cloudflare.com`, `bob.ns.cloudflare.com`)
5. Click **Done** and wait 5–30 minutes for propagation

```bash
# Verify nameserver propagation
dig NS yourdomain.com +short
# Should return Cloudflare nameservers
```

#### 3.2 Add DNS Records

In Cloudflare Dashboard → **DNS** → **Add record**:

| Type | Name | Content | Proxy Status | TTL |
|------|------|---------|-------------|-----|
| CNAME | `www` | `www.yourdomain.com.s3-website-ap-south-1.amazonaws.com` | ✅ Proxied | Auto |
| CNAME | `@` | `www.yourdomain.com` | ✅ Proxied | Auto |

> ⚠️ **Critical:** The CNAME host name must exactly equal your S3 bucket name.

#### 3.3 Configure SSL/TLS

1. Cloudflare Dashboard → **SSL/TLS** tab
2. Set encryption mode to **Flexible** (S3 only serves HTTP — Cloudflare encrypts to browser)
3. **Edge Certificates** → Enable **Always Use HTTPS**
4. Enable **Automatic HTTPS Rewrites**
5. **Minimum TLS Version** → TLS 1.2 (or TLS 1.3 for modern-only)

#### 3.4 Set Cache Rules

1. Cloudflare → **Caching** → **Cache Rules** → **Create rule**
2. Rule name: `Cache Static Assets`
3. When: Field `Hostname` equals `www.yourdomain.com`
4. Then: **Cache eligibility** → Eligible for cache → **Edge TTL** → 1 month
5. Deploy rule

#### 3.5 Get Zone ID and API Token

**Zone ID:**
1. Cloudflare Dashboard → select your domain
2. Right sidebar → scroll down → copy **Zone ID**

**API Token:**
1. **Profile** (top-right) → **API Tokens** → **Create Token**
2. Use template **"Edit zone DNS"** → Edit permissions:
   - Zone → Cache Purge → **Purge**
3. Zone Resources → Include → Specific zone → `yourdomain.com`
4. Create token → **Copy and save it**

---

## Step 4 — Configure GitHub Repository Secrets

1. GitHub → your repo → **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret** for each:

| Secret Name | Example Value | Where to Get |
|------------|--------------|-------------|
| `AWS_ACCESS_KEY_ID` | `AKIAXXXXXXXXXX` | IAM Step 2.3 |
| `AWS_SECRET_ACCESS_KEY` | `xxxx...xxxx` | IAM Step 2.3 |
| `AWS_REGION` | `ap-south-1` | Your chosen region |
| `S3_BUCKET_NAME` | `www.yourdomain.com` | Your bucket name |
| `CF_ZONE_ID` | `abc123def456...` | Cloudflare Step 3.5 |
| `CF_API_TOKEN` | `Bearer abc123...` | Cloudflare Step 3.5 |
| `SITE_DOMAIN` | `www.yourdomain.com` | Your domain |

> 💡 Optionally create a **GitHub Environment** named `production` for approval gates.

---

## Step 5 — Understand the CI/CD Workflow

The workflow file at `.github/workflows/deploy.yml` contains **2 jobs** and **12 steps**.

### Trigger Conditions

```yaml
on:
  push:
    branches: [ main ]
    paths:
      - 'src/**'                        # Only trigger on source changes
      - '.github/workflows/deploy.yml'  # Or workflow changes
  workflow_dispatch:                    # Manual trigger from GitHub UI
```

### Job 1: `validate` (runs first, gates deploy)

| Step | Action |
|------|--------|
| Checkout code | Pulls latest source |
| Count files | Lists all src/ files in job summary |
| Validate HTML | Checks DOCTYPE, `<html>`, `<head>`, `<body>` — **fails if missing** |
| Check CSS/JS | Counts files, checks CSS brace balance |

### Job 2: `deploy` (runs only if validate passes)

| Step | Action | Cache-Control Applied |
|------|--------|----------------------|
| Checkout | Fresh code checkout | — |
| AWS Auth | Configure IAM credentials | — |
| Verify bucket | Confirms S3 access before sync | — |
| Sync HTML | `aws s3 sync` `.html` files | `no-cache, must-revalidate` |
| Sync CSS | `aws s3 sync` `.css` files | `max-age=31536000, immutable` |
| Sync JS | `aws s3 sync` `.js` files | `max-age=31536000, immutable` |
| Sync assets | `aws s3 sync` images/fonts | `max-age=2592000` |
| Security metadata | Adds deploy timestamp to object metadata | — |
| Verify S3 | Lists bucket contents post-deploy | — |
| Purge Cloudflare | Calls CF API to clear all edge caches | — |
| Smoke test | Fetches live URL, checks HTTP 200 + SSL | — |
| Write summary | Posts deployment report to Actions tab | — |

---

## Step 6 — Cache Strategy & Versioning

### Cache Headers per Asset Type

```
HTML  → no-cache, must-revalidate      (always fresh, never stale)
CSS   → public, max-age=31536000, immutable  (1 year, filename versioned)
JS    → public, max-age=31536000, immutable  (1 year, filename versioned)
IMG   → public, max-age=2592000              (30 days)
Fonts → public, max-age=31536000, immutable  (1 year)
```

### Filename-Based Cache Busting

When you update CSS or JS, **rename the file** to break the cache:

```bash
# Before: your HTML references style.css
<link rel="stylesheet" href="css/style.css">

# After update: rename and update the reference
mv src/css/style.css src/css/style.v2.css

# Update index.html
<link rel="stylesheet" href="css/style.v2.css">

# Old style.css stays cached in browsers — doesn't matter
# New style.v2.css is fetched fresh because it's a new URL
```

### Manual Cache Operations

```bash
# Purge entire Cloudflare cache manually
curl -X POST "https://api.cloudflare.com/client/v4/zones/ZONE_ID/purge_cache" \
  -H "Authorization: Bearer CF_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"purge_everything":true}'

# Purge only specific files
--data '{"files":["https://www.yourdomain.com/index.html"]}'

# Check S3 object metadata (verify cache headers deployed)
aws s3api head-object --bucket www.yourdomain.com --key index.html
```

---

## Step 7 — First Deploy & Testing

### Local Testing

```bash
# Serve locally before pushing
cd src/
python3 -m http.server 3000
# Visit http://localhost:3000
```

### Trigger First Deployment

```bash
# Initialize git and push
git init
git add .
git commit -m "feat: initial site launch"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/cloudstatic.git
git push -u origin main
```

Watch the workflow run at: `https://github.com/YOUR_USERNAME/cloudstatic/actions`

### Verify Deployment

```bash
# 1. Check S3 content
aws s3 ls s3://www.yourdomain.com/ --recursive --human-readable

# 2. Check website is accessible via S3 endpoint
curl -I http://www.yourdomain.com.s3-website-ap-south-1.amazonaws.com

# 3. Check via Cloudflare (HTTPS)
curl -I https://www.yourdomain.com
# Expected: HTTP/2 200, cf-ray header present

# 4. Verify cache headers on CSS
curl -I https://www.yourdomain.com/css/style.css
# Expected: cache-control: public, max-age=31536000, immutable

# 5. Verify Cloudflare is proxying (not bypassed)
curl -I https://www.yourdomain.com | grep -i "cf-ray\|server"
# Expected: server: cloudflare, cf-ray: <id>
```

### Expected Response Headers

```
HTTP/2 200
content-type: text/html; charset=utf-8
cache-control: no-cache, no-store, must-revalidate
server: cloudflare
cf-ray: 8abc123def456789-BOM
strict-transport-security: max-age=15552000; includeSubDomains; preload
```

---

## 🔧 Troubleshooting Guide

| Problem | Symptoms | Solution |
|---------|----------|---------|
| **403 Forbidden on S3 URL** | AccessDenied XML response | Re-check bucket policy — ensure `Principal: "*"` and correct ARN |
| **Site shows but no HTTPS** | Browser warns "Not Secure" | Cloudflare SSL must be **Flexible**, not Off. Enable Always Use HTTPS |
| **Old content after deploy** | CSS/HTML changes not visible | Manually purge Cloudflare cache: Dashboard → Caching → Purge Everything |
| **GitHub Actions 403 on S3** | Workflow fails at sync step | IAM policy missing PutObject or wrong bucket ARN in the policy |
| **CNAME not resolving** | `nslookup` returns nothing | Wait 30 min for DNS propagation. Ensure bucket name = CNAME host |
| **Redirect loop** | ERR_TOO_MANY_REDIRECTS | Set Cloudflare SSL to **Flexible** (not Full or Full Strict with S3) |
| **CF_TOKEN auth error** | `"success": false` in purge | Token must have **Zone → Cache Purge → Purge** permission only |
| **Smoke test 403 after deploy** | curl returns 403 | ACL: ensure bucket objects are public-read. Check bucket policy |

```bash
# Debug DNS propagation
dig CNAME www.yourdomain.com +short

# Debug S3 endpoint directly
curl -v http://www.yourdomain.com.s3-website-ap-south-1.amazonaws.com/

# Debug Cloudflare SSL
openssl s_client -connect www.yourdomain.com:443 -servername www.yourdomain.com 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates

# Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT:user/github-actions-cloudstatic \
  --action-names s3:PutObject \
  --resource-arns arn:aws:s3:::www.yourdomain.com/*
```

---

## 💰 Cost Analysis

| AWS Resource | Free Tier Limit | Typical Usage | Cost |
|-------------|----------------|--------------|------|
| S3 Storage | 5 GB / month | < 10 MB (HTML/CSS/JS) | **$0.00** |
| S3 GET Requests | 20,000 / month | ~500 (direct) | **$0.00** |
| S3 PUT Requests | 2,000 / month | ~20 per deploy | **$0.00** |
| S3 Data Transfer | 15 GB / month | ~0 (Cloudflare caches) | **$0.00** |
| GitHub Actions | 2,000 min / month | ~5 min per deploy | **$0.00** |
| Cloudflare CDN | Unlimited traffic | All traffic | **$0.00** |
| **Total** | | | **$0.00 / month** |

> Cloudflare absorbs ~98% of all traffic at the edge, keeping S3 egress costs at zero.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Make your changes in `src/`
4. Commit: `git commit -m "feat: description"`
5. Push: `git push origin feat/my-feature`
6. Open a Pull Request to `main`

---

## 📄 License

MIT © 2025 CloudStatic

---

<div align="center">
  Built with AWS S3 · Cloudflare CDN · GitHub Actions
</div>
