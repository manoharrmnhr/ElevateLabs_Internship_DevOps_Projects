#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════
#  scripts/setup-s3.sh
#  Automates AWS S3 bucket creation and static website config
#  Usage: ./scripts/setup-s3.sh <bucket-name> <region>
#  Example: ./scripts/setup-s3.sh www.yourdomain.com ap-south-1
# ══════════════════════════════════════════════════════════════
set -euo pipefail

BUCKET="${1:?Usage: $0 <bucket-name> <aws-region>}"
REGION="${2:?Usage: $0 <bucket-name> <aws-region>}"

echo "╔══════════════════════════════════════════════╗"
echo "║  CloudStatic S3 Setup Script                 ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Bucket : $BUCKET"
echo "Region : $REGION"
echo ""

# ── Step 1: Create bucket ──────────────────────────────────────
echo "▶ Step 1: Creating S3 bucket..."
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi
echo "  ✅ Bucket created: $BUCKET"

# ── Step 2: Disable Block Public Access ───────────────────────
echo ""
echo "▶ Step 2: Disabling Block Public Access settings..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
echo "  ✅ Block Public Access disabled."

# ── Step 3: Set bucket policy for public read ─────────────────
echo ""
echo "▶ Step 3: Applying public-read bucket policy..."
POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
EOF
)
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$POLICY"
echo "  ✅ Bucket policy applied."

# ── Step 4: Enable static website hosting ─────────────────────
echo ""
echo "▶ Step 4: Enabling static website hosting..."
aws s3api put-bucket-website \
  --bucket "$BUCKET" \
  --website-configuration '{
    "IndexDocument": {"Suffix": "index.html"},
    "ErrorDocument": {"Key": "404.html"}
  }'
echo "  ✅ Static website hosting enabled."
echo "     Endpoint: http://${BUCKET}.s3-website-${REGION}.amazonaws.com"

# ── Step 5: Enable versioning ──────────────────────────────────
echo ""
echo "▶ Step 5: Enabling S3 bucket versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
echo "  ✅ Versioning enabled (supports rollback)."

# ── Step 6: Enable server-side encryption ─────────────────────
echo ""
echo "▶ Step 6: Enabling default AES-256 encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
echo "  ✅ Server-side encryption enabled."

# ── Done ───────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Setup Complete!                             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Website Endpoint:"
echo "  http://${BUCKET}.s3-website-${REGION}.amazonaws.com"
echo ""
echo "Next Steps:"
echo "  1. Create a Cloudflare CNAME: ${BUCKET} → above endpoint"
echo "  2. Set Cloudflare SSL to Flexible mode"
echo "  3. Add GitHub Secrets (see README.md)"
echo "  4. git push origin main to trigger first deploy"
