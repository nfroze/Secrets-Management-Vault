#!/usr/bin/env bash
# =============================================================================
# Bootstrap Terraform Remote State Backend
# Creates S3 bucket + DynamoDB table for state locking before terraform init
# =============================================================================

set -euo pipefail

BUCKET_NAME="nf-secrets-vault-tfstate"
TABLE_NAME="nf-secrets-vault-tfstate-lock"
REGION="eu-west-2"

echo "========================================="
echo "  Terraform State Backend Bootstrap"
echo "========================================="

# Check AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
  echo "ERROR: AWS CLI not configured. Run 'aws configure' first."
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account: ${ACCOUNT_ID}"
echo "Region:      ${REGION}"

# Create S3 bucket
echo ""
echo "[1/4] Creating S3 bucket: ${BUCKET_NAME}"
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "  Bucket already exists. Skipping."
else
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
  echo "  Created."
fi

# Enable versioning
echo "[2/4] Enabling versioning on S3 bucket"
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled
echo "  Enabled."

# Enable encryption
echo "[3/4] Enabling server-side encryption"
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms"
        },
        "BucketKeyEnabled": true
      }
    ]
  }'
echo "  Enabled."

# Block public access
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for locking
echo "[4/4] Creating DynamoDB table: ${TABLE_NAME}"
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" &>/dev/null; then
  echo "  Table already exists. Skipping."
else
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  echo "  Created."
fi

echo ""
echo "========================================="
echo "  State backend ready!"
echo "  Run: cd terraform && terraform init"
echo "========================================="
