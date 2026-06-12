###############################################################################
# cloudwatch.tf - Alarms, EventBridge rules, SNS, Dashboard
###############################################################################

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

###############################################################################
# Alarm 1: ALB Healthy Host Count drops below threshold
# (Equivalent to a K8s readiness probe failing across replicas)
###############################################################################
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.healthy_host_alarm_threshold
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.app.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_description = "Fires when fewer than ${var.healthy_host_alarm_threshold} healthy targets are behind the ALB. Triggers the Auto-Healer Lambda."
  alarm_actions      = [aws_sns_topic.alerts.arn, aws_lambda_function.auto_healer.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project_name}-unhealthy-hosts-alarm"
  }
}

resource "aws_lambda_permission" "allow_cloudwatch_unhealthy" {
  statement_id  = "AllowExecutionFromCloudWatchUnhealthy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_healer.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.unhealthy_hosts.arn
}

###############################################################################
# Alarm 2: ECS Service running task count below desired
###############################################################################
resource "aws_cloudwatch_metric_alarm" "running_task_count_low" {
  alarm_name          = "${var.project_name}-running-task-count-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.desired_count
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_description = "Fires when RunningTaskCount < desired_count, indicating drift from desired state."
  alarm_actions      = [aws_sns_topic.alerts.arn, aws_lambda_function.auto_healer.arn]
  ok_actions         = [aws_sns_topic.alerts.arn]

  tags = {
    Name = "${var.project_name}-running-task-count-alarm"
  }
}

resource "aws_lambda_permission" "allow_cloudwatch_taskcount" {
  statement_id  = "AllowExecutionFromCloudWatchTaskCount"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_healer.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.running_task_count_low.arn
}

###############################################################################
# EventBridge Rule: ECS Task State Change -> Auto-Healer
# (Catches STOPPED tasks immediately, like a K8s pod-deleted event)
###############################################################################
resource "aws_cloudwatch_event_rule" "ecs_task_stopped" {
  name        = "${var.project_name}-ecs-task-stopped"
  description = "Triggers when an ECS task in our cluster stops unexpectedly"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      lastStatus  = ["STOPPED"]
      clusterArn  = [aws_ecs_cluster.main.arn]
    }
  })
}

resource "aws_cloudwatch_event_target" "auto_healer_target" {
  rule      = aws_cloudwatch_event_rule.ecs_task_stopped.name
  target_id = "auto-healer-lambda"
  arn       = aws_lambda_function.auto_healer.arn
}

resource "aws_lambda_permission" "allow_eventbridge_task_stopped" {
  statement_id  = "AllowExecutionFromEventBridgeTaskStopped"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_healer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecs_task_stopped.arn
}

###############################################################################
# EventBridge Schedule: periodic Chaos Injection
###############################################################################
resource "aws_cloudwatch_event_rule" "chaos_schedule" {
  count               = var.chaos_enabled ? 1 : 0
  name                = "${var.project_name}-chaos-schedule"
  description         = "Periodically invokes the Chaos Injector Lambda"
  schedule_expression = var.chaos_schedule_expression
}

resource "aws_cloudwatch_event_target" "chaos_target" {
  count     = var.chaos_enabled ? 1 : 0
  rule      = aws_cloudwatch_event_rule.chaos_schedule[0].name
  target_id = "chaos-injector-lambda"
  arn       = aws_lambda_function.chaos_injector.arn
}

resource "aws_lambda_permission" "allow_eventbridge_chaos" {
  count         = var.chaos_enabled ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeChaos"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chaos_injector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.chaos_schedule[0].arn
}

###############################################################################
# SNS -> Notifier Lambda subscription
###############################################################################
resource "aws_sns_topic_subscription" "notifier_lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notifier.arn
}

resource "aws_lambda_permission" "allow_sns_notifier" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

###############################################################################
# CloudWatch Dashboard
###############################################################################
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = file("${path.module}/../monitoring/cloudwatch_dashboard.json")
}
