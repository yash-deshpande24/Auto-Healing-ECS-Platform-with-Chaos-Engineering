###############################################################################
# lambda.tf - Auto-Healer, Chaos Injector, Notifier Lambda functions
###############################################################################

# ---------------------------------------------------------------------------
# Package source code into zip archives
# ---------------------------------------------------------------------------
data "archive_file" "auto_healer" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/auto_healer"
  output_path = "${path.module}/build/auto_healer.zip"
}

data "archive_file" "chaos_injector" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/chaos_injector"
  output_path = "${path.module}/build/chaos_injector.zip"
}

data "archive_file" "notifier" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_functions/notifier"
  output_path = "${path.module}/build/notifier.zip"
}

# ---------------------------------------------------------------------------
# Auto-Healer Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "auto_healer" {
  function_name    = "${var.project_name}-auto-healer"
  role              = aws_iam_role.auto_healer.arn
  handler           = "handler.lambda_handler"
  runtime           = "python3.12"
  timeout           = 60
  memory_size       = 128

  filename          = data.archive_file.auto_healer.output_path
  source_code_hash  = data.archive_file.auto_healer.output_base64sha256

  environment {
    variables = {
      CLUSTER_NAME    = aws_ecs_cluster.main.name
      SERVICE_NAME    = aws_ecs_service.app.name
      DESIRED_COUNT   = tostring(var.desired_count)
      SNS_TOPIC_ARN   = aws_sns_topic.alerts.arn
    }
  }

  tags = {
    Name = "${var.project_name}-auto-healer"
  }
}

resource "aws_cloudwatch_log_group" "auto_healer" {
  name              = "/aws/lambda/${aws_lambda_function.auto_healer.function_name}"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# Chaos Injector Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "chaos_injector" {
  function_name    = "${var.project_name}-chaos-injector"
  role              = aws_iam_role.chaos_injector.arn
  handler           = "handler.lambda_handler"
  runtime           = "python3.12"
  timeout           = 60
  memory_size       = 128

  filename          = data.archive_file.chaos_injector.output_path
  source_code_hash  = data.archive_file.chaos_injector.output_base64sha256

  environment {
    variables = {
      CLUSTER_NAME        = aws_ecs_cluster.main.name
      SERVICE_NAME        = aws_ecs_service.app.name
      KILL_PROBABILITY    = tostring(var.chaos_kill_probability)
      SNS_TOPIC_ARN       = aws_sns_topic.alerts.arn
    }
  }

  tags = {
    Name = "${var.project_name}-chaos-injector"
  }
}

resource "aws_cloudwatch_log_group" "chaos_injector" {
  name              = "/aws/lambda/${aws_lambda_function.chaos_injector.function_name}"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# Notifier Lambda
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "notifier" {
  function_name    = "${var.project_name}-notifier"
  role              = aws_iam_role.notifier.arn
  handler           = "handler.lambda_handler"
  runtime           = "python3.12"
  timeout           = 30
  memory_size       = 128

  filename          = data.archive_file.notifier.output_path
  source_code_hash  = data.archive_file.notifier.output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }

  tags = {
    Name = "${var.project_name}-notifier"
  }
}

resource "aws_cloudwatch_log_group" "notifier" {
  name              = "/aws/lambda/${aws_lambda_function.notifier.function_name}"
  retention_in_days = 14
}
