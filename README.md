# Auto-Healing Kubernetes-Like ECS Platform with CloudWatch Chaos Engineering

A self-healing container platform built on **Amazon ECS (Fargate)** that mimics
Kubernetes-style reconciliation loops (desired-state enforcement, health
checks, automatic rescheduling) and integrates a **Chaos Engineering** layer
driven by **CloudWatch alarms + Lambda** to randomly degrade services and
verify that the platform heals itself automatically.

---

## 🧠 Core Idea

Kubernetes constantly compares *desired state* vs *actual state* and takes
corrective action (restarting pods, rescheduling, scaling). This project
replicates that control loop on top of AWS-native primitives:

| Kubernetes Concept | AWS Equivalent Used Here |
|---------------------|---------------------------|
| Pod | ECS Task (Fargate) |
| ReplicaSet / Deployment | ECS Service (desired count) |
| Liveness / Readiness Probe | ALB Target Group Health Check + Container HEALTHCHECK |
| Node | Fargate (serverless, no node mgmt) |
| Self-Healing Controller | Lambda "Auto-Healer" triggered by CloudWatch Alarms/Events |
| Chaos Monkey | Lambda "Chaos Injector" (kills tasks, throttles CPU, injects 500s) |
| Metrics Server | CloudWatch Container Insights |
| kubectl describe / events | CloudWatch Logs + EventBridge audit trail |

---

## 🏗️ Architecture

```
                       ┌─────────────────────────┐
                       │      Internet / User     │
                       └────────────┬─────────────┘
                                     │
                              ┌──────▼──────┐
                              │     ALB     │
                              └──────┬──────┘
                                     │
                         ┌───────────▼────────────┐
                         │   ECS Service (Fargate) │
                         │   desired_count = N     │
                         │  ┌─────┐ ┌─────┐ ┌─────┐│
                         │  │Task1│ │Task2│ │Task3││
                         │  └─────┘ └─────┘ └─────┘│
                         └───────────┬────────────┘
                                     │ metrics/logs
                       ┌─────────────▼─────────────┐
                       │   CloudWatch (Alarms,      │
                       │   Container Insights,      │
                       │   Logs, EventBridge)        │
                       └──────┬──────────────┬──────┘
                               │              │
                  alarm: unhealthy   schedule: every N min
                               │              │
                        ┌──────▼──────┐ ┌─────▼──────────┐
                        │ Auto-Healer │ │ Chaos Injector  │
                        │   Lambda    │ │     Lambda      │
                        └──────┬──────┘ └─────┬───────────┘
                               │              │
                        ECS API: ForceNewDeployment /
                        UpdateService / StopTask
                               │
                        ┌──────▼──────┐
                        │  SNS Topic  │──► Slack / Email Notifier Lambda
                        └─────────────┘
```

---

## 📁 Project Structure

```
auto-healing-ecs-platform/
├── terraform/                 # All infrastructure as code
│   ├── main.tf                # Providers, backend, module wiring
│   ├── variables.tf           # Input variables
│   ├── outputs.tf              # Useful outputs (ALB DNS, ARNs, etc.)
│   ├── vpc.tf                  # VPC, subnets, routing
│   ├── ecs.tf                  # ECS cluster, task definition, service
│   ├── alb.tf                  # ALB, target group, listener, health checks
│   ├── cloudwatch.tf           # Alarms, dashboards, Container Insights, EventBridge rules
│   ├── iam.tf                  # IAM roles/policies for ECS, Lambda
│   ├── lambda.tf               # Auto-healer, chaos injector, notifier Lambdas
│   └── terraform.tfvars.example
│
├── app/                        # Sample microservice (Flask) deployed to ECS
│   ├── app.py
│   ├── health_check.py
│   ├── requirements.txt
│   └── Dockerfile
│
├── lambda_functions/
│   ├── auto_healer/             # Watches alarms/events, restores desired state
│   │   ├── handler.py
│   │   └── requirements.txt
│   ├── chaos_injector/          # Randomly kills tasks / induces failures
│   │   ├── handler.py
│   │   └── requirements.txt
│   └── notifier/                # Sends Slack/SNS notifications of healing events
│       └── handler.py
│
├── monitoring/
│   ├── cloudwatch_dashboard.json
│   └── alarms.json
│
├── scripts/
│   ├── deploy.sh                # Build, push image, terraform apply
│   ├── inject_chaos.sh          # Manually trigger chaos injector
│   └── cleanup.sh                # Tear down all resources
│
├── tests/
│   └── test_healer.py           # Unit tests for auto-healer logic
│
├── docs/
│   └── chaos_scenarios.md       # Documented chaos experiments & expected healing behavior
│
├── architecture/
│   └── architecture.md
│
├── .gitignore
└── README.md
```

---

## 🚀 Quick Start

```bash
# 1. Build and push the sample app image to ECR (done by deploy.sh)
# 2. Deploy infrastructure
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit values
terraform init
terraform apply

# 3. Run a chaos experiment
../scripts/inject_chaos.sh

# 4. Watch CloudWatch dashboard + ECS console:
#    - Chaos Injector kills/throttles a task
#    - CloudWatch Alarm fires (UnhealthyHostCount / RunningTaskCount < desired)
#    - EventBridge triggers Auto-Healer Lambda
#    - Auto-Healer calls ecs:UpdateService (force new deployment) or
#      ecs:StartTask to restore desired_count
#    - SNS notification sent via Notifier Lambda
```

---

## 🔁 Self-Healing Loop (Reconciliation)

1. **Observe** – CloudWatch Container Insights + ALB metrics continuously
   monitor `RunningTaskCount`, `HealthyHostCount`, `CPUUtilization`,
   `MemoryUtilization`.
2. **Detect Drift** – CloudWatch Alarms fire when:
   - `HealthyHostCount < desired_count`
   - A task transitions to `STOPPED` unexpectedly (captured via EventBridge
     rule on `ECS Task State Change`)
   - CPU/Memory exceeds thresholds (triggers scale-out, like HPA)
3. **Reconcile** – Auto-Healer Lambda:
   - Calls `ecs update-service --force-new-deployment` to replace unhealthy
     tasks
   - Calls `ecs update-service --desired-count` to restore replica count
   - Optionally scales out via Application Auto Scaling if CPU/Mem high
4. **Notify** – Notifier Lambda posts a summary to SNS/Slack with what was
   healed and why.
5. **Verify** – Dashboard shows recovery time (MTTR) for each chaos event.

---

## 🧪 Chaos Engineering Scenarios

See [`docs/chaos_scenarios.md`](docs/chaos_scenarios.md) for full details.
Summary:

| Scenario | Chaos Action | Expected Self-Healing |
|----------|--------------|------------------------|
| Task Crash | `StopTask` on a random running task | ECS reschedules task; Auto-Healer forces redeployment if needed |
| Service Under-Capacity | Manually set `desired_count` to 0 temporarily | Auto-Healer restores desired count |
| CPU Spike | Inject CPU stress via SSM command in container | CloudWatch Alarm triggers Application Auto Scaling scale-out |
| Unhealthy Target | App returns HTTP 500 on `/health` | ALB marks target unhealthy → ECS replaces task |
| AZ Failure Simulation | Drain all tasks in one subnet/AZ | Service reschedules tasks into healthy AZs |

---

## 🛠️ Tech Stack

- **AWS ECS (Fargate)** – container orchestration
- **Application Load Balancer** – traffic routing + health checks
- **CloudWatch** – metrics, alarms, dashboards, Container Insights, Logs
- **EventBridge** – event-driven triggers for ECS task state changes
- **Lambda (Python 3.12)** – auto-healer, chaos injector, notifier
- **SNS** – alerting
- **Terraform** – infrastructure as code
- **Flask** – sample microservice with `/health` and `/chaos` endpoints

---

## 📊 Observability

- `monitoring/cloudwatch_dashboard.json` — pre-built dashboard showing
  RunningTaskCount, HealthyHostCount, CPU/Mem, alarm states, and Lambda
  invocation counts (heal events).
- `monitoring/alarms.json` — reference definitions for all CloudWatch alarms
  created by `terraform/cloudwatch.tf`.

---

## 🧹 Cleanup

```bash
./scripts/cleanup.sh
```

This runs `terraform destroy` and removes any ECR images pushed for the demo.
