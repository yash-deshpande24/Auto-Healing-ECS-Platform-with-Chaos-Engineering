#!/usr/bin/env bash
###############################################################################
# inject_chaos.sh - Manually invoke the Chaos Injector Lambda
#
# Usage:
#   ./inject_chaos.sh                  # random action based on KILL_PROBABILITY
#   ./inject_chaos.sh stop_random_task # force a task kill
###############################################################################
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

AWS_REGION="${AWS_REGION:-us-east-1}"
FORCE_ACTION="${1:-}"

cd "${TERRAFORM_DIR}"
FUNCTION_NAME="$(terraform output -raw chaos_injector_function_name)"

if [[ -n "${FORCE_ACTION}" ]]; then
  PAYLOAD="{\"force_action\": \"${FORCE_ACTION}\"}"
else
  PAYLOAD="{}"
fi

echo "Invoking ${FUNCTION_NAME} with payload: ${PAYLOAD}"

aws lambda invoke \
  --function-name "${FUNCTION_NAME}" \
  --payload "${PAYLOAD}" \
  --cli-binary-format raw-in-base64-out \
  --region "${AWS_REGION}" \
  /dev/stdout | cat

echo
echo "Watch ECS service events and the CloudWatch dashboard to observe the"
echo "Auto-Healer Lambda restoring the desired state."
