"""
Chaos Injector Lambda
======================

Implements a "Chaos Monkey" style controller for the ECS service.

Triggered on a schedule (EventBridge rate/cron expression) or manually via
scripts/inject_chaos.sh.

Each invocation randomly chooses ONE chaos action (weighted by
KILL_PROBABILITY) to validate that the Auto-Healer + ECS service can recover:

  1. stop_random_task  - calls ecs:StopTask on a randomly chosen running task,
                          simulating a pod crash / node failure.
  2. noop               - does nothing this cycle (keeps the system "calm"
                          so you can observe steady state).

A summary of the action taken is published to SNS so the Notifier Lambda can
post it to Slack/email - giving you a timeline of "fault injected" ->
"system healed" events.
"""

import json
import os
import random
import time

import boto3

ecs = boto3.client("ecs")
sns = boto3.client("sns")

CLUSTER_NAME = os.environ["CLUSTER_NAME"]
SERVICE_NAME = os.environ["SERVICE_NAME"]
KILL_PROBABILITY = float(os.environ.get("KILL_PROBABILITY", "0.5"))
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


def _publish(message: dict) -> None:
    if not SNS_TOPIC_ARN:
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="Chaos Injector: fault injected",
            Message=json.dumps(message, default=str, indent=2),
        )
    except Exception as exc:  # noqa: BLE001
        print(f"WARN: failed to publish to SNS: {exc}")


def _list_running_tasks() -> list[str]:
    resp = ecs.list_tasks(
        cluster=CLUSTER_NAME,
        serviceName=SERVICE_NAME,
        desiredStatus="RUNNING",
    )
    return resp.get("taskArns", [])


def _stop_random_task() -> dict:
    task_arns = _list_running_tasks()

    if not task_arns:
        return {
            "action": "stop_random_task",
            "result": "skipped",
            "reason": "no running tasks found",
        }

    target = random.choice(task_arns)

    ecs.stop_task(
        cluster=CLUSTER_NAME,
        task=target,
        reason="Chaos Injector: simulated task failure for resilience testing",
    )

    return {
        "action": "stop_random_task",
        "result": "executed",
        "target_task_arn": target,
        "total_running_tasks_before": len(task_arns),
    }


def _noop() -> dict:
    return {
        "action": "noop",
        "result": "skipped",
        "reason": f"random roll did not meet kill_probability={KILL_PROBABILITY}",
    }


def lambda_handler(event, context):  # noqa: ANN001, ANN201
    print(f"Chaos Injector invoked with event: {json.dumps(event, default=str)}")

    # Allow explicit override for manual testing:
    # { "force_action": "stop_random_task" }
    force_action = None
    if isinstance(event, dict):
        force_action = event.get("force_action")

    roll = random.random()

    if force_action == "stop_random_task" or (force_action is None and roll < KILL_PROBABILITY):
        outcome = _stop_random_task()
    else:
        outcome = _noop()

    result = {
        "timestamp": time.time(),
        "cluster": CLUSTER_NAME,
        "service": SERVICE_NAME,
        "kill_probability": KILL_PROBABILITY,
        "random_roll": roll,
        **outcome,
    }

    print(json.dumps(result, default=str))
    _publish(result)

    return {
        "statusCode": 200,
        "body": json.dumps(result, default=str),
    }
