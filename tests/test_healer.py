"""
Unit tests for the Auto-Healer Lambda reconciliation logic.

These tests mock the boto3 ECS/SNS clients so they can run without any AWS
credentials or network access:

    pip install boto3 pytest
    pytest tests/test_healer.py
"""

import json
import os
import sys
import importlib
from unittest import mock

import pytest


@pytest.fixture()
def healer_module(monkeypatch):
    """
    Import the auto_healer handler module fresh for each test, with required
    environment variables set and boto3.client mocked out.
    """
    monkeypatch.setenv("CLUSTER_NAME", "test-cluster")
    monkeypatch.setenv("SERVICE_NAME", "test-service")
    monkeypatch.setenv("DESIRED_COUNT", "3")
    monkeypatch.setenv("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123456789012:test-topic")

    module_path = os.path.join(
        os.path.dirname(__file__), "..", "lambda_functions", "auto_healer"
    )
    sys.path.insert(0, os.path.abspath(module_path))

    with mock.patch("boto3.client") as mock_client:
        mock_ecs = mock.MagicMock()
        mock_sns = mock.MagicMock()

        def client_side_effect(service_name, *args, **kwargs):
            return {"ecs": mock_ecs, "sns": mock_sns}[service_name]

        mock_client.side_effect = client_side_effect

        import handler  # type: ignore

        importlib.reload(handler)

        handler._mock_ecs = mock_ecs  # type: ignore[attr-defined]
        handler._mock_sns = mock_sns  # type: ignore[attr-defined]

        yield handler

    sys.path.remove(os.path.abspath(module_path))
    sys.modules.pop("handler", None)


def _describe_services_response(desired, running, pending=0):
    return {
        "services": [
            {
                "desiredCount": desired,
                "runningCount": running,
                "pendingCount": pending,
            }
        ]
    }


def test_no_action_when_state_matches(healer_module):
    healer_module._mock_ecs.describe_services.return_value = _describe_services_response(
        desired=3, running=3, pending=0
    )

    event = {"detail-type": "manual-test"}
    response = healer_module.lambda_handler(event, None)

    body = json.loads(response["body"])
    assert body["actions_taken"] == [
        "No action needed; service already matches desired state "
        "(desired=3, running=3, pending=0)"
    ]
    healer_module._mock_ecs.update_service.assert_not_called()


def test_forces_new_deployment_when_running_below_desired(healer_module):
    healer_module._mock_ecs.describe_services.return_value = _describe_services_response(
        desired=3, running=1, pending=0
    )

    event = {"source": "aws.ecs", "detail": {"lastStatus": "STOPPED"}}
    response = healer_module.lambda_handler(event, None)

    body = json.loads(response["body"])
    assert any("Forced new deployment" in action for action in body["actions_taken"])

    healer_module._mock_ecs.update_service.assert_called_with(
        cluster="test-cluster",
        service="test-service",
        forceNewDeployment=True,
    )


def test_restores_desired_count_when_below_baseline(healer_module):
    # Simulate a chaos experiment that scaled desiredCount down to 0
    healer_module._mock_ecs.describe_services.return_value = _describe_services_response(
        desired=0, running=0, pending=0
    )

    event = {"alarmData": {"alarmName": "autoheal-ecs-running-task-count-low"}}
    response = healer_module.lambda_handler(event, None)

    body = json.loads(response["body"])

    calls = healer_module._mock_ecs.update_service.call_args_list
    # First call restores desiredCount, second forces new deployment
    assert calls[0] == mock.call(
        cluster="test-cluster",
        service="test-service",
        desiredCount=3,
    )
    assert any(
        call.kwargs.get("forceNewDeployment") is True for call in calls
    )

    assert body["desired_count"] == 3
    assert any("Restored desiredCount" in action for action in body["actions_taken"])


def test_publishes_to_sns(healer_module):
    healer_module._mock_ecs.describe_services.return_value = _describe_services_response(
        desired=3, running=2, pending=0
    )

    healer_module.lambda_handler({}, None)

    healer_module._mock_sns.publish.assert_called_once()
    _, kwargs = healer_module._mock_sns.publish.call_args
    assert kwargs["TopicArn"] == "arn:aws:sns:us-east-1:123456789012:test-topic"
    assert "Auto-Healer" in kwargs["Subject"]
