# Architecture

## Overview

This platform deploys a containerized application onto **AWS ECS Fargate**
behind an **Application Load Balancer**, then layers on a closed-loop,
event-driven control system that:

1. **Observes** the system via CloudWatch (Container Insights metrics, ALB
   target health, EventBridge events for task state changes).
2. **Detects** drift from desired state via CloudWatch Alarms and
   EventBridge rules.
3. **Reconciles** drift via an "Auto-Healer" Lambda that calls the ECS API.
4. **Injects controlled failure** via a "Chaos Injector" Lambda to
   continuously validate that the reconciliation loop works.
5. **Notifies** operators of every healing/chaos action via SNS → a
   "Notifier" Lambda (Slack/email).

This is intentionally analogous to Kubernetes' controller pattern, but built
entirely from managed AWS services — no self-managed control plane, nodes,
or kubelets required.

## Components

### Networking (`terraform/vpc.tf`)
- Single VPC with 2 public subnets (ALB) and 2 private subnets (ECS tasks)
  across 2 AZs.
- NAT Gateway for outbound access from private subnets (image pulls, AWS API
  calls via VPC endpoints or NAT).

### Load Balancing (`terraform/alb.tf`)
- Internet-facing ALB with HTTP listener on port 80.
- Target group configured with health checks against `/health`
  (matches container `HEALTHCHECK` defined in `app/Dockerfile`).
- Security groups restrict ECS task ingress to traffic from the ALB only.

### Compute (`terraform/ecs.tf`)
- ECS Cluster with **Container Insights enabled** (provides the
  `ECS/ContainerInsights` metric namespace used by alarms and the dashboard).
- Fargate task definition running the sample Flask app
  (`app/app.py`), with:
  - Container-level `HEALTHCHECK`
  - `awslogs` log driver → CloudWatch Logs
- ECS Service with:
  - `deployment_circuit_breaker` (auto-rollback on failed deployments)
  - `health_check_grace_period_seconds`
  - Application Auto Scaling (target-tracking on CPU) — the HPA equivalent.

### Self-Healing Control Loop (`terraform/cloudwatch.tf`, `terraform/lambda.tf`)

```
                ┌────────────────────────────────────────────┐
                │                CloudWatch                    │
                │                                              │
                │  Alarm: HealthyHostCount < N  ───┐           │
                │  Alarm: RunningTaskCount < N  ───┤           │
                │  EventBridge: ECS Task STOPPED ──┤           │
                └───────────────────────────────────┼──────────┘
                                                      │
                                                      ▼
                                          ┌─────────────────────┐
                                          │   Auto-Healer Lambda │
                                          │  (lambda_functions/  │
                                          │   auto_healer)       │
                                          └─────────┬───────────┘
                                                     │ ecs:UpdateService
                                                     │ (restore desiredCount /
                                                     │  forceNewDeployment)
                                                     ▼
                                          ┌─────────────────────┐
                                          │     ECS Service      │
                                          └─────────────────────┘

                ┌────────────────────────────────────────────┐
                │           EventBridge Schedule               │
                │       (rate(15 minutes) by default)          │
                └────────────────────┬───────────────────────┘
                                      ▼
                          ┌──────────────────────┐
                          │ Chaos Injector Lambda  │
                          │ (lambda_functions/     │
                          │  chaos_injector)        │
                          └──────────┬─────────────┘
                                      │ ecs:StopTask (random)
                                      ▼
                          ┌──────────────────────┐
                          │     ECS Service        │
                          └──────────────────────┘

   Both Lambdas publish to:  SNS Topic "alerts" ──► Notifier Lambda ──► Slack/Email
```

### IAM (`terraform/iam.tf`)
- **ECS execution role**: pull images from ECR, write logs (managed policy
  `AmazonECSTaskExecutionRolePolicy`).
- **ECS task role**: minimal permissions for the app itself (CloudWatch Logs).
- **Auto-Healer role**: `ecs:DescribeServices`, `ecs:UpdateService`,
  `ecs:ListTasks`/`DescribeTasks`, `sns:Publish`, CloudWatch read.
- **Chaos Injector role**: `ecs:ListTasks`, `ecs:StopTask`,
  `ecs:DescribeServices`/`UpdateService`, `sns:Publish`.
- **Notifier role**: basic Lambda execution (logs only); reaches Slack via
  outbound HTTPS (requires the Lambda to run with network access — if placed
  in a VPC, ensure NAT/VPC endpoint access; by default Lambdas not attached
  to a VPC have internet access).

### Observability (`monitoring/`)
- `cloudwatch_dashboard.json`: single-pane view of running vs desired tasks,
  ALB healthy/unhealthy hosts, CPU/Memory utilization, request counts/5XX,
  and Lambda invocation counts for the three control-loop functions.
- `alarms.json`: human-readable reference for the alarms and EventBridge
  rules defined in Terraform.

## Design Decisions & Trade-offs

- **Fargate over EC2 launch type**: removes node management entirely,
  keeping the focus on the *application-level* self-healing loop rather than
  infrastructure patching — closer to how most teams consume "Kubernetes"
  via managed node groups or serverless compute today.
- **Lambda-based controllers over a long-running controller process**:
  event-driven, pay-per-use, and naturally maps to CloudWatch
  Alarms/EventBridge as the "watch" mechanism (replacing the Kubernetes API
  server's watch streams).
- **Single NAT Gateway**: cost-optimized for a demo/teaching environment.
  For production, deploy one NAT Gateway per AZ for higher availability.
- **Deployment circuit breaker enabled**: if the Auto-Healer (or a bad image)
  causes repeated failed deployments, ECS automatically rolls back —
  preventing the healer from making things worse.
- **`lifecycle.ignore_changes = [task_definition]`** on the ECS service:
  allows `deploy.sh` / CI to roll out new task definition revisions without
  Terraform reverting them on the next `apply`.
