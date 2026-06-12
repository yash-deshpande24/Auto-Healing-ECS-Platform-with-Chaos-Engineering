"""
Auto-Healer Lambda
==================

Acts as the "reconciliation controller" for the ECS service, analogous to a
Kubernetes ReplicaSet/Deployment controller.

Triggered by:
  1. CloudWatch Alarm: HealthyHostCount < threshold (ALB)
  2. CloudWatch Alarm: RunningTaskCount < desired_count (Container Insights)
  3. EventBridge Rule: "ECS Task State Change" with lastStatus == STOPPED

Responsibilities:
  - Inspect current vs desired state of the ECS service
  - If running count < desired count, trigger ECS to reconcile
    (ECS itself will normally relaunch tasks; this acts as a backstop and
    also forces a fresh deployment to clear out tasks stuck in a bad state)
  - Publish a summary of the healing action to SNS for the Notifier Lambda
"""

import json
import os
import time

import boto3

ecs = boto3.client("ecs")
sns = boto3.client("sns")

CLUSTER_NAME = os.environ["CLUSTER_NAME"]
SERVICE_NAME = os.environ["SERVICE_NAME"]
DESIRED_COUNT = int(os.environ.get("DESIRED_COUNT", "3"))
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


def _publish(message: dict) -> None:
    if not SNS_TOPIC_ARN:
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="Auto-Healer: action taken",
            Message=json.dumps(message, default=str, indent=2),
        )
    except Exception as exc:  # noqa: BLE001
        print(f"WARN: failed to publish to SNS: {exc}")


def _describe_service() -> dict:
    resp = ecs.describe_services(cluster=CLUSTER_NAME, services=[SERVICE_NAME])
    services = resp.get("services", [])
    if not services:
        raise RuntimeError(f"Service {SERVICE_NAME} not found in cluster {CLUSTER_NAME}")
    return services[0]


def _reconcile(event_source: str, event_detail: dict) -> dict:
    """
    Core reconciliation logic: compare desired vs running counts and take
    corrective action if they don't match.
    """
    service = _describe_service()

    desired = service["desiredCount"]
    running = service["runningCount"]
    pending = service["pendingCount"]

    actions_taken = []

    # Case 1: desiredCount was somehow changed away from the configured baseline
    # (e.g. chaos experiment scaled it to 0). Restore it.
    if desired < DESIRED_COUNT:
        ecs.update_service(
            cluster=CLUSTER_NAME,
            service=SERVICE_NAME,
            desiredCount=DESIRED_COUNT,
        )
        actions_taken.append(
            f"Restored desiredCount from {desired} to {DESIRED_COUNT}"
        )
        desired = DESIRED_COUNT

    # Case 2: running count is below desired -> something is unhealthy.
    # Force a new deployment to cycle out bad tasks. ECS will then schedule
    # replacements to bring runningCount back up to desiredCount.
    if running < desired:
        ecs.update_service(
            cluster=CLUSTER_NAME,
            service=SERVICE_NAME,
            forceNewDeployment=True,
        )
        actions_taken.append(
            f"Forced new deployment because runningCount ({running}) < "
            f"desiredCount ({desired})"
        )

    if not actions_taken:
        actions_taken.append(
            "No action needed; service already matches desired state "
            f"(desired={desired}, running={running}, pending={pending})"
        )

    result = {
        "timestamp": time.time(),
        "cluster": CLUSTER_NAME,
        "service": SERVICE_NAME,
        "event_source": event_source,
        "event_detail": event_detail,
        "desired_count": desired,
        "running_count": running,
        "pending_count": pending,
        "actions_taken": actions_taken,
    }

    print(json.dumps(result, default=str))
    _publish(result)
    return result


def lambda_handler(event, context):  # noqa: ANN001, ANN201
    """
    Entry point. Handles three trigger shapes:
      - CloudWatch Alarm via Lambda action (event contains "alarmData")
      - EventBridge "ECS Task State Change" (event contains "source" == "aws.ecs")
      - Manual/test invocation (arbitrary JSON)
    """
    print(f"Auto-Healer invoked with event: {json.dumps(event, default=str)}")

    if isinstance(event, dict) and event.get("source") == "aws.ecs":
        event_source = "eventbridge:ecs-task-state-change"
        event_detail = event.get("detail", {})
    elif isinstance(event, dict) and "alarmData" in event:
        alarm_data = event["alarmData"]
        event_source = f"cloudwatch-alarm:{alarm_data.get('alarmName')}"
        event_detail = alarm_data
    else:
        event_source = "manual-or-unknown"
        event_detail = event if isinstance(event, dict) else {"raw": str(event)}

    result = _reconcile(event_source, event_detail)

    return {
        "statusCode": 200,
        "body": json.dumps(result, default=str),
    }
