#!/usr/bin/env bash
# One-time setup (an allowed console/CLI exception in rule 8):
#   - S3 bucket + DynamoDB lock table for Terraform remote state
#   - optional low-limit Budgets alert
# Usage: ./bootstrap.sh [alert-email] [monthly-limit-usd]
# Run with your own IAM user profile (MFA), never root.
set -euo pipefail

REGION="ap-south-1"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="sentimentops-tfstate-${ACCOUNT_ID}"
TABLE="sentimentops-tflock"
EMAIL="${1:-}"
LIMIT="${2:-5}"

echo "Account: $ACCOUNT_ID  Region: $REGION"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "State bucket exists: $BUCKET"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
  aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-tagging --bucket "$BUCKET" \
    --tagging 'TagSet=[{Key=Project,Value=sentimentops},{Key=Owner,Value=shaurya},{Key=ManagedBy,Value=bootstrap}]'
  echo "Created state bucket: $BUCKET"
fi

if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "Lock table exists: $TABLE"
else
  aws dynamodb create-table --table-name "$TABLE" --region "$REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --tags Key=Project,Value=sentimentops Key=Owner,Value=shaurya Key=ManagedBy,Value=bootstrap
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
  echo "Created lock table: $TABLE"
fi

cat > "$(dirname "$0")/../backend.hcl" <<HCL
bucket         = "${BUCKET}"
key            = "sentimentops/dev/terraform.tfstate"
region         = "${REGION}"
dynamodb_table = "${TABLE}"
encrypt        = true
HCL
echo "Wrote infra/backend.hcl"

if [[ -n "$EMAIL" ]]; then
  # Budgets is a global service; its API lives in us-east-1
  aws budgets create-budget --region us-east-1 --account-id "$ACCOUNT_ID" \
    --budget "{\"BudgetName\":\"sentimentops-monthly\",\"BudgetLimit\":{\"Amount\":\"${LIMIT}\",\"Unit\":\"USD\"},\"TimeUnit\":\"MONTHLY\",\"BudgetType\":\"COST\"}" \
    --notifications-with-subscribers "[
      {\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"${EMAIL}\"}]},
      {\"Notification\":{\"NotificationType\":\"FORECASTED\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":100,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"${EMAIL}\"}]}
    ]" && echo "Budget alert created: \$${LIMIT}/month -> ${EMAIL}" \
       || echo "Budget creation failed or already exists (check console)."
fi

echo "Next: cd infra && terraform init -backend-config=backend.hcl"
