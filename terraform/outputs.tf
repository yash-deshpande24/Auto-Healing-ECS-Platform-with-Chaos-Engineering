###############################################################################
# outputs.tf
###############################################################################

output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for the sample app image"
  value       = aws_ecr_repository.app.repository_url
}

output "auto_healer_function_name" {
  description = "Name of the Auto-Healer Lambda function"
  value       = aws_lambda_function.auto_healer.function_name
}

output "chaos_injector_function_name" {
  description = "Name of the Chaos Injector Lambda function"
  value       = aws_lambda_function.chaos_injector.function_name
}

output "notifier_function_name" {
  description = "Name of the Notifier Lambda function"
  value       = aws_lambda_function.notifier.function_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
