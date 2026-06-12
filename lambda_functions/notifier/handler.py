"""
Notifier Lambda
================

Subscribed to the SNS "alerts" topic. Receives messages published by:
  - the Auto-Healer Lambda (healing actions taken)
  - the Chaos Injector Lambda (faults injected)
  - CloudWatch Alarms (state changes)

Forwards a human-readable summary to a Slack incoming webhook (if
SLACK_WEBHOOK_URL is configured) and always logs the message to CloudWatch
Logs, which acts as an audit trail similar to `kubectl get events`.
"""

import json
import os
import urllib.request

SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")


def _format_message(record: dict) -> str:
    sns_message = record.get("Sns", {})
    subject = sns_message.get("Subject", "Notification")
    raw_message = sns_message.get("Message", "{}")

    try:
        payload = json.loads(raw_message)
    except (TypeError, ValueError):
        payload = {"raw": raw_message}

    lines = [f"*{subject}*"]
    for key, value in payload.items():
        if key == "event_detail":
            continue  # often verbose; omit from the Slack summary
        lines.append(f"• *{key}*: {value}")

    return "\n".join(lines)


def _send_to_slack(text: str) -> None:
    if not SLACK_WEBHOOK_URL:
        return

    body = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(
        SLACK_WEBHOOK_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"Slack webhook responded with status {resp.status}")
    except Exception as exc:  # noqa: BLE001
        print(f"WARN: failed to post to Slack: {exc}")


def lambda_handler(event, context):  # noqa: ANN001, ANN201
    print(f"Notifier invoked with event: {json.dumps(event, default=str)}")

    records = event.get("Records", []) if isinstance(event, dict) else []

    if not records:
        # Direct/manual invocation for testing
        text = f"*Manual test notification*\n{json.dumps(event, default=str)}"
        print(text)
        _send_to_slack(text)
        return {"statusCode": 200, "body": "ok"}

    for record in records:
        text = _format_message(record)
        print(text)
        _send_to_slack(text)

    return {"statusCode": 200, "body": "ok"}
