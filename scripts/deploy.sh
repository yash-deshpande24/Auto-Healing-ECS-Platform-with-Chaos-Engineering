#!/usr/bin/env bash
###############################################################################
# deploy.sh - Build & push the sample app image, then apply Terraform
###############################################################################
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
APP_DIR="${PROJECT_ROOT}/app"

AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-autoheal-ecs}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=== 1/4: terraform init ==="
cd "${TERRAFORM_DIR}"
terraform init -input=false

echo "=== 2/4: terraform apply (create ECR repo + base infra) ==="
# First apply creates the ECR repo (and everything else). If this is the very
# first run and container_image is empty, the ECS service will fail to pull
# an image until step 4 pushes one and you re-apply / force a new deployment.
terraform apply -auto-approve -input=false

ECR_REPO_URL="$(terraform output -raw ecr_repository_url)"
ACCOUNT_ID="$(echo "${ECR_REPO_URL}" | cut -d'.' -f1)"

echo "=== 3/4: build & push Docker image to ${ECR_REPO_URL}:${IMAGE_TAG} ==="
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build -t "${ECR_REPO_URL}:${IMAGE_TAG}" "${APP_DIR}"
docker push "${ECR_REPO_URL}:${IMAGE_TAG}"

echo "=== 4/4: force new ECS deployment to pick up the new image ==="
CLUSTER_NAME="$(terraform output -raw ecs_cluster_name)"
SERVICE_NAME="$(terraform output -raw ecs_service_name)"

aws ecs update-service \
  --cluster "${CLUSTER_NAME}" \
  --service "${SERVICE_NAME}" \
  --force-new-deployment \
  --region "${AWS_REGION}" >/dev/null

echo
echo "Deployment complete!"
echo "ALB DNS name: $(terraform output -raw alb_dns_name)"
echo "CloudWatch Dashboard: $(terraform output -raw cloudwatch_dashboard_url)"
