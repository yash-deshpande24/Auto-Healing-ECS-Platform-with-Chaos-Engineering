#!/usr/bin/env bash
###############################################################################
# cleanup.sh - Tear down all infrastructure created by this project
###############################################################################
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

cd "${TERRAFORM_DIR}"

echo "This will destroy ALL resources managed by Terraform in this directory."
read -r -p "Are you sure? Type 'yes' to continue: " CONFIRM

if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# Empty the ECR repository first, since Terraform cannot destroy a
# non-empty repository by default.
ECR_REPO_URL="$(terraform output -raw ecr_repository_url 2>/dev/null || true)"
if [[ -n "${ECR_REPO_URL}" ]]; then
  REPO_NAME="$(echo "${ECR_REPO_URL}" | cut -d'/' -f2-)"
  AWS_REGION="${AWS_REGION:-us-east-1}"

  echo "Deleting all images in ECR repository: ${REPO_NAME}"
  IMAGE_IDS="$(aws ecr list-images --repository-name "${REPO_NAME}" --region "${AWS_REGION}" \
    --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')"

  if [[ "${IMAGE_IDS}" != "[]" ]]; then
    aws ecr batch-delete-image \
      --repository-name "${REPO_NAME}" \
      --region "${AWS_REGION}" \
      --image-ids "${IMAGE_IDS}" >/dev/null || true
  fi
fi

echo "Running terraform destroy..."
terraform destroy -auto-approve -input=false

echo "Cleanup complete."
