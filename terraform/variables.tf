###############################################################################
# variables.tf - Input variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short name used as a prefix for all resources"
  type        = string
  default     = "autoheal-ecs"
}

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (ECS tasks)"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

###############################################################################
# ECS / Application
###############################################################################

variable "container_image" {
  description = "Container image URI for the sample app (ECR repo:tag)"
  type        = string
  default     = "" # populated by deploy.sh / CI, or set ECR repo created here
}

variable "container_port" {
  description = "Port the application listens on inside the container"
  type        = number
  default     = 8080
}

variable "desired_count" {
  description = "Desired number of running ECS tasks (replica count)"
  type        = number
  default     = 3
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto scaling"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto scaling"
  type        = number
  default     = 6
}

variable "task_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, ...)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory in MiB"
  type        = string
  default     = "512"
}

###############################################################################
# Auto-healing / Chaos thresholds
###############################################################################

variable "healthy_host_alarm_threshold" {
  description = "Alarm fires if HealthyHostCount drops below this value"
  type        = number
  default     = 2
}

variable "cpu_high_threshold" {
  description = "CPU utilization (%) that triggers scale-out / alarm"
  type        = number
  default     = 70
}

variable "chaos_schedule_expression" {
  description = "EventBridge schedule expression for the chaos injector (rate or cron)"
  type        = string
  default     = "rate(15 minutes)"
}

variable "chaos_enabled" {
  description = "Master switch to enable/disable scheduled chaos injection"
  type        = bool
  default     = true
}

variable "chaos_kill_probability" {
  description = "Probability (0-1) that the chaos injector stops a random task on each invocation"
  type        = number
  default     = 0.5
}

###############################################################################
# Notifications
###############################################################################

variable "notification_email" {
  description = "Email address to subscribe to the SNS alerting topic (optional)"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for the notifier Lambda (optional)"
  type        = string
  default     = ""
  sensitive   = true
}
