# Auto-Healing Kubernetes-Like ECS Platform with CloudWatch Chaos Engineering

A self-healing container platform built on **Amazon ECS (Fargate)** that mimics Kubernetes-style reconciliation loops (desired-state enforcement, health checks, automatic rescheduling) and integrates a **Chaos Engineering** layer driven by **CloudWatch Alarms + Lambda** to randomly degrade services and verify that the platform heals itself automatically.

---

## 🌐 Interactive Architecture Demo

Explore the visual architecture and self-healing workflow through the interactive demo:

👉 **[Open Interactive Demo](./autoheal-ecs-demo.html)**

The demo showcases:

* ECS Service & Task Lifecycle
* CloudWatch Monitoring & Alarms
* Chaos Engineering Experiments
* Auto-Healing Reconciliation Loop
* EventBridge Event Flow
* SNS Notifications
* Recovery and MTTR Tracking

---

## 🧠 Core Idea

Kubernetes continuously compares the **desired state** of a system with its **actual state** and automatically takes corrective actions when drift occurs.

This project recreates that behavior using AWS-native services.

| Kubernetes Concept         | AWS Equivalent Used Here                  |
| -------------------------- | ----------------------------------------- |
| Pod                        | ECS Task (Fargate)                        |
| ReplicaSet / Deployment    | ECS Service (Desired Count)               |
| Liveness / Readiness Probe | ALB Health Checks + Container HEALTHCHECK |
| Node                       | AWS Fargate                               |
| Controller Loop            | Auto-Healer Lambda                        |
| Chaos Monkey               | Chaos Injector Lambda                     |
| Metrics Server             | CloudWatch Container Insights             |
| Events                     | EventBridge + CloudWatch Logs             |

---

## 🏗️ Architecture

```text
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
                       │ CloudWatch Insights        │
                       │ Alarms + EventBridge       │
                       └──────┬──────────────┬──────┘
                               │              │
                               │              │
                      ┌────────▼───┐   ┌─────▼─────────┐
                      │ Auto-Healer│   │Chaos Injector │
                      │  Lambda    │   │   Lambda      │
                      └──────┬─────┘   └─────┬─────────┘
                             │               │
                             └──────┬────────┘
                                    │
                              ECS APIs
                                    │
                           ┌────────▼───────┐
                           │ SNS / Slack     │
                           │ Notifications   │
                           └─────────────────┘
```

---

## ✨ Features

### Self-Healing Capabilities

* Automatic detection of unhealthy ECS tasks
* Desired-state reconciliation
* Automatic task replacement
* Service redeployment on failure
* Event-driven recovery using EventBridge
* Recovery notifications through SNS

### Chaos Engineering

* Random ECS task termination
* Desired count manipulation
* Application health degradation
* CPU stress testing
* Availability Zone failure simulation
* Recovery validation and MTTR measurement

### Observability

* CloudWatch Container Insights
* CloudWatch Dashboards
* CloudWatch Logs
* CloudWatch Alarms
* EventBridge Audit Trail
* SNS Notifications

### Infrastructure as Code

* Fully automated deployment using Terraform
* Modular AWS resource provisioning
* Repeatable and version-controlled infrastructure

---

## 📁 Project Structure

```text
auto-healing-ecs-platform/
├── autoheal-ecs-demo.html
│
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── vpc.tf
│   ├── ecs.tf
│   ├── alb.tf
│   ├── cloudwatch.tf
│   ├── iam.tf
│   ├── lambda.tf
│   └── terraform.tfvars.example
│
├── app/
│   ├── app.py
│   ├── health_check.py
│   ├── requirements.txt
│   └── Dockerfile
│
├── lambda_functions/
│   ├── auto_healer/
│   │   ├── handler.py
│   │   └── requirements.txt
│   │
│   ├── chaos_injector/
│   │   ├── handler.py
│   │   └── requirements.txt
│   │
│   └── notifier/
│       └── handler.py
│
├── monitoring/
│   ├── cloudwatch_dashboard.json
│   └── alarms.json
│
├── scripts/
│   ├── deploy.sh
│   ├── inject_chaos.sh
│   └── cleanup.sh
│
├── tests/
│   └── test_healer.py
│
├── docs/
│   └── chaos_scenarios.md
│
├── architecture/
│   └── architecture.md
│
├── README.md
└── .gitignore
```

---

## 🛠️ Technology Stack

| Layer                 | Technology                |
| --------------------- | ------------------------- |
| Container Platform    | Amazon ECS (Fargate)      |
| Load Balancing        | Application Load Balancer |
| Monitoring            | CloudWatch                |
| Event Processing      | EventBridge               |
| Serverless Automation | AWS Lambda                |
| Alerting              | SNS                       |
| Infrastructure        | Terraform                 |
| Application           | Python Flask              |
| Containerization      | Docker                    |
| Testing               | Pytest                    |

---

## 🚀 Quick Start

### Prerequisites

* AWS Account
* AWS CLI configured
* Terraform >= 1.6
* Docker
* Python 3.12

---

### Clone Repository

```bash
git clone https://github.com/yourusername/auto-healing-ecs-platform.git

cd auto-healing-ecs-platform
```

---

### Configure Terraform

```bash
cd terraform

cp terraform.tfvars.example terraform.tfvars
```

Update:

```hcl
aws_region = "ap-south-1"
project_name = "auto-healing-ecs"
environment = "demo"
```

---

### Deploy Infrastructure

```bash
terraform init

terraform validate

terraform plan

terraform apply
```

---

### Deploy Application

```bash
chmod +x scripts/deploy.sh

./scripts/deploy.sh
```

---

### Verify Deployment

Retrieve outputs:

```bash
terraform output
```

Open:

```text
http://<alb-dns-name>
```

Health endpoint:

```text
http://<alb-dns-name>/health
```

---

## 🔁 Self-Healing Reconciliation Loop

### Step 1 — Observe

CloudWatch continuously collects:

* RunningTaskCount
* HealthyHostCount
* CPUUtilization
* MemoryUtilization
* Application Logs

---

### Step 2 — Detect Drift

CloudWatch alarms trigger when:

* Running tasks < desired count
* ALB health checks fail
* ECS task unexpectedly stops
* CPU exceeds threshold
* Memory exceeds threshold

---

### Step 3 — Reconcile

Auto-Healer Lambda performs:

```python
ecs.update_service(
    cluster=cluster_name,
    service=service_name,
    forceNewDeployment=True
)
```

or

```python
ecs.update_service(
    cluster=cluster_name,
    service=service_name,
    desiredCount=desired_count
)
```

---

### Step 4 — Notify

SNS notifications are generated for:

* Task recovery
* Service recovery
* Scaling events
* Chaos experiment results

---

### Step 5 — Verify

Dashboard tracks:

* Recovery success
* MTTR
* Alarm history
* Service availability

---

## 🧪 Chaos Engineering Scenarios

### 1. Task Crash

**Action**

```bash
aws ecs stop-task
```

**Expected Result**

* ECS launches replacement task
* Service remains healthy

---

### 2. Desired Count Drift

**Action**

```bash
aws ecs update-service \
  --desired-count 0
```

**Expected Result**

Auto-Healer restores desired count.

---

### 3. CPU Stress

**Action**

Trigger CPU-intensive workload.

**Expected Result**

* CloudWatch alarm fires
* Auto Scaling increases capacity

---

### 4. Unhealthy Application

**Action**

```http
GET /chaos
```

Application returns:

```http
500 Internal Server Error
```

**Expected Result**

ALB marks target unhealthy and ECS replaces it.

---

### 5. Availability Zone Failure

**Action**

Drain tasks in one subnet.

**Expected Result**

Tasks are rescheduled into healthy AZs.

---

## 📊 Monitoring Dashboard

The project includes:

### Metrics

* RunningTaskCount
* HealthyHostCount
* CPU Utilization
* Memory Utilization
* Lambda Invocations
* Alarm States
* Recovery Time

### Dashboard File

```text
monitoring/cloudwatch_dashboard.json
```

---

## 🔔 Notifications

Supported channels:

* Amazon SNS
* Email
* Slack Webhooks

Notification examples:

```text
[RECOVERY SUCCESS]

Service: demo-service
Cluster: auto-healing-cluster

Issue:
Task stopped unexpectedly

Action:
New deployment initiated

Recovery Time:
21 seconds
```

---

## 🧪 Testing

Run unit tests:

```bash
pytest tests/
```

Run chaos experiments:

```bash
./scripts/inject_chaos.sh
```

---

## 📈 Sample Outcomes

| Experiment          | Recovery Time |
| ------------------- | ------------- |
| Task Kill           | 15-30 sec     |
| Unhealthy Target    | 20-40 sec     |
| CPU Spike           | 1-2 min       |
| Desired Count Drift | < 30 sec      |

---

## 🔐 IAM Permissions

The Auto-Healer Lambda requires:

```json
{
  "Action": [
    "ecs:DescribeServices",
    "ecs:UpdateService",
    "ecs:ListTasks",
    "ecs:DescribeTasks",
    "cloudwatch:GetMetricData"
  ],
  "Effect": "Allow",
  "Resource": "*"
}
```

---

## 📚 Documentation

| File                                 | Description                    |
| ------------------------------------ | ------------------------------ |
| docs/chaos_scenarios.md              | Chaos experiment documentation |
| architecture/architecture.md         | Architecture details           |
| monitoring/cloudwatch_dashboard.json | Dashboard definition           |
| monitoring/alarms.json               | Alarm definitions              |

---

## 🧹 Cleanup

Destroy all infrastructure:

```bash
chmod +x scripts/cleanup.sh

./scripts/cleanup.sh
```

or

```bash
cd terraform

terraform destroy
```

---

## 🎯 Learning Objectives

This project demonstrates:

* Amazon ECS (Fargate)
* CloudWatch Monitoring
* Event-Driven Automation
* Terraform Infrastructure as Code
* Chaos Engineering
* Auto-Healing Systems
* Site Reliability Engineering (SRE)
* High Availability Design
* Observability Best Practices

---

## 👨‍💻 Author

**Yash Deshpande**

Cloud & DevOps Engineer

### Skills Demonstrated

* AWS ECS
* Fargate
* Lambda
* CloudWatch
* EventBridge
* SNS
* Terraform
* Docker
* Python
* Chaos Engineering
* Site Reliability Engineering

---

## 📄 License

This project is licensed under the MIT License.

Feel free to use, modify, and extend this project for learning, portfolio, and production-grade experimentation.
