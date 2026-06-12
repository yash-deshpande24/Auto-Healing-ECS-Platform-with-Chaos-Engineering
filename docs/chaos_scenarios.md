# Chaos Engineering Scenarios

This document describes the chaos experiments supported by this platform,
how to trigger them, what CloudWatch signals they produce, and the expected
self-healing behavior.

All experiments assume the platform has been deployed via
`scripts/deploy.sh` and the ECS service is in a steady state
(`runningCount == desiredCount`, all ALB targets healthy).

---

## 1. Random Task Termination ("Kill a Pod")

**Trigger:**
```bash
./scripts/inject_chaos.sh stop_random_task
```
or wait for the scheduled Chaos Injector (`chaos_schedule_expression`,
default every 15 minutes) to randomly select this action based on
`chaos_kill_probability`.

**What happens:**
1. The Chaos Injector Lambda calls `ecs:ListTasks` then `ecs:StopTask` on a
   randomly chosen running task.
2. ECS emits an `ECS Task State Change` event with `lastStatus: STOPPED`.
3. The EventBridge rule `*-ecs-task-stopped` invokes the Auto-Healer Lambda.
4. ECS service scheduler independently starts a replacement task to restore
   `runningCount == desiredCount` (this is native ECS behavior).
5. The Auto-Healer Lambda double-checks `runningCount` vs `desiredCount`; if
   ECS hasn't yet caught up, it issues `ecs:UpdateService` with
   `forceNewDeployment=true` as a backstop.
6. SNS notification is sent describing the kill + any healer action.

**Expected outcome:** Within ~30-90 seconds, `runningCount` returns to
`desiredCount` and all ALB targets are healthy again.

**CloudWatch signals to watch:**
- ECS Console → Service → "Events" tab (task stopped / started)
- `RunningTaskCount` and `PendingTaskCount` metrics dip then recover
- Auto-Healer Lambda CloudWatch Logs

---

## 2. Service Under-Capacity ("Scale to Zero")

**Trigger (manual, via AWS CLI):**
```bash
aws ecs update-service \
  --cluster <cluster-name> \
  --service <service-name> \
  --desired-count 0
```

**What happens:**
1. ECS stops all running tasks to match `desiredCount = 0`.
2. `RunningTaskCount` drops to 0, breaching the
   `*-running-task-count-low` alarm (2 evaluation periods).
3. The alarm invokes the Auto-Healer Lambda.
4. The Auto-Healer detects `desiredCount (0) < DESIRED_COUNT (baseline, e.g. 3)`
   and calls `ecs:UpdateService` to restore `desiredCount` to the baseline,
   then forces a new deployment.

**Expected outcome:** The service scales back from 0 to the configured
baseline (`var.desired_count`) without any human intervention, demonstrating
recovery from a "scaled to zero" incident — similar to a Kubernetes
Deployment being reconciled back to its replica spec.

---

## 3. CPU Spike / Hot Shard

**Trigger (manual, exec into a running task or use SSM):**
Generate CPU load inside a container, e.g.:
```bash
# inside the container
yes > /dev/null &
yes > /dev/null &
```

**What happens:**
1. `CPUUtilization`/`CpuUtilized` rises above `cpu_high_threshold` (default 70%).
2. The Application Auto Scaling target tracking policy
   (`aws_appautoscaling_policy.cpu_scale_out`) increases `desiredCount`
   toward `max_capacity`.
3. New tasks are scheduled to absorb load; once average CPU drops back below
   the target, scale-in cooldown eventually reduces `desiredCount` back
   toward `min_capacity`.

**Expected outcome:** Horizontal scale-out under load and scale-in once load
subsides — analogous to a Kubernetes HorizontalPodAutoscaler.

---

## 4. Application-Level Unhealthy Response (HTTP 500 on /health)

**Trigger:**
```bash
# Get the ALB DNS name from terraform output, then:
curl -X POST http://<alb-dns-name>/chaos/sick
```

**What happens:**
1. The targeted task's `/health` endpoint starts returning HTTP 500.
2. After `unhealthy_threshold` (2) consecutive failed health checks
   (interval 15s), the ALB marks that target `unhealthy`.
3. `UnHealthyHostCount` rises and `HealthyHostCount` falls, potentially
   breaching the `*-unhealthy-hosts` alarm if enough targets are affected.
4. ECS's own task health check (container `HEALTHCHECK`) will also begin
   failing; after `retries` consecutive failures the container is marked
   unhealthy and ECS replaces the task.
5. The Auto-Healer Lambda (via the unhealthy-hosts alarm) double-checks
   service state and forces a new deployment if `runningCount` lags.

**Expected outcome:** The "sick" task is automatically replaced; new tasks
register as healthy targets and traffic is routed away from the bad task
throughout the recovery.

**Manual recovery (optional, for testing without waiting for replacement):**
```bash
curl -X POST http://<alb-dns-name>/chaos/heal
```

---

## 5. Availability Zone Failure Simulation

**Trigger (manual, via AWS CLI):**
Temporarily remove one private subnet from the ECS service's network
configuration, or use `ecs:StopTask` repeatedly targeting tasks in a single
AZ (combine with scenario 1, filtering `task_arns` by AZ using
`ecs:DescribeTasks`).

**What happens:**
1. Tasks in the affected AZ are stopped.
2. ECS reschedules replacement tasks into the remaining healthy private
   subnets/AZs (since the service spans multiple subnets).
3. ALB continues routing traffic to healthy targets in unaffected AZs
   throughout.

**Expected outcome:** No downtime at the ALB level; `desiredCount` is
maintained by redistributing tasks across the remaining AZs.

---

## 6. Hard Crash (Process Exit)

**Trigger:**
```bash
curl http://<alb-dns-name>/crash
```

**What happens:**
1. The Flask process calls `os._exit(1)`, immediately terminating the
   container process.
2. The container's `HEALTHCHECK`/Docker exit triggers ECS to mark the task
   `STOPPED`.
3. EventBridge `ECS Task State Change` (STOPPED) fires → Auto-Healer Lambda.
4. ECS service scheduler starts a replacement task automatically.

**Expected outcome:** Fast detection (within the container health-check
interval) and automatic replacement, with the Auto-Healer Lambda logging the
event for audit purposes.

---

## Measuring MTTR (Mean Time To Recovery)

For each scenario, you can measure recovery time using the CloudWatch
dashboard (`monitoring/cloudwatch_dashboard.json`):

1. Note the timestamp when `RunningTaskCount` first drops below
   `DesiredTaskCount`.
2. Note the timestamp when `RunningTaskCount` returns to
   `DesiredTaskCount` AND `UnHealthyHostCount` returns to 0.
3. The difference is the MTTR for that experiment.

Auto-Healer and Chaos Injector Lambda logs (CloudWatch Logs) include
timestamps for every action taken, making it straightforward to build a
timeline of "fault injected" → "detected" → "healed" events.
