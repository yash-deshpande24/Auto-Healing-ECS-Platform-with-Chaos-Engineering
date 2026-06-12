"""
Sample microservice for the Auto-Healing ECS Platform.

Exposes:
  GET /            - basic info page
  GET /health      - health check used by ALB target group & ECS container HEALTHCHECK
  GET /metrics     - simple JSON metrics (uptime, request count, sick state)
  POST /chaos/sick - flips the service into an "unhealthy" state (used by chaos injector
                      to simulate an application-level failure that the platform must heal)
  POST /chaos/heal - manually restores healthy state (useful for testing)
  GET /crash       - intentionally exits the process (simulates a hard crash;
                      ECS will restart the task automatically)
"""

import os
import time
import socket
import threading

from flask import Flask, jsonify, request

app = Flask(__name__)

START_TIME = time.time()
REQUEST_COUNT = 0
_lock = threading.Lock()

# In-memory "sickness" flag - when True, /health returns 500
# This simulates an application-level failure (e.g. a stuck dependency)
SICK = {"value": False}


@app.before_request
def _count_requests():
    global REQUEST_COUNT
    with _lock:
        REQUEST_COUNT += 1


@app.route("/")
def index():
    return jsonify({
        "service": "auto-healing-ecs-demo",
        "hostname": socket.gethostname(),
        "message": "Hello from the self-healing ECS platform!",
        "uptime_seconds": round(time.time() - START_TIME, 2),
    })


@app.route("/health")
def health():
    """
    Used by:
      - ALB Target Group health check
      - ECS container HEALTHCHECK (Docker)
    Returns 500 when SICK flag is set, simulating an unhealthy pod.
    """
    if SICK["value"]:
        return jsonify({
            "status": "unhealthy",
            "hostname": socket.gethostname(),
            "reason": "chaos: application marked itself sick",
        }), 500

    return jsonify({
        "status": "healthy",
        "hostname": socket.gethostname(),
        "uptime_seconds": round(time.time() - START_TIME, 2),
    }), 200


@app.route("/metrics")
def metrics():
    with _lock:
        count = REQUEST_COUNT
    return jsonify({
        "hostname": socket.gethostname(),
        "uptime_seconds": round(time.time() - START_TIME, 2),
        "request_count": count,
        "sick": SICK["value"],
    })


@app.route("/chaos/sick", methods=["POST"])
def chaos_sick():
    """Simulates an application-level degradation (used by chaos experiments)."""
    SICK["value"] = True
    return jsonify({"status": "ok", "sick": True, "hostname": socket.gethostname()})


@app.route("/chaos/heal", methods=["POST"])
def chaos_heal():
    """Manually restore healthy state (for testing without waiting for ECS to replace the task)."""
    SICK["value"] = False
    return jsonify({"status": "ok", "sick": False, "hostname": socket.gethostname()})


@app.route("/crash")
def crash():
    """
    Intentionally terminates the process to simulate a hard crash.
    ECS will detect the stopped task and start a replacement,
    and the Auto-Healer Lambda will verify desired-count is restored.
    """
    os._exit(1)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
