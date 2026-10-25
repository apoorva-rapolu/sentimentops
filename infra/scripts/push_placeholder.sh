#!/usr/bin/env bash
# Build + push the placeholder image to ECR as :placeholder.
# Run AFTER `terraform apply -target=module.registry` and BEFORE the full apply.
set -euo pipefail
cd "$(dirname "$0")/.."
REGION="ap-south-1"
REPO_URL="$(terraform output -raw ecr_repository_url)"
REGISTRY="${REPO_URL%%/*}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker build --platform linux/amd64 --provenance=false -t "${REPO_URL}:placeholder" placeholder/
docker push "${REPO_URL}:placeholder"
