#!/usr/bin/env python3
"""
Standalone health-check script used inside the container's HEALTHCHECK
directive as a lightweight alternative to curl.

Exit code 0 = healthy, 1 = unhealthy (Docker/ECS treats non-zero as failure).
"""

import os
import sys
import urllib.request

PORT = os.environ.get("PORT", "8080")
URL = f"http://localhost:{PORT}/health"


def main() -> int:
    try:
        with urllib.request.urlopen(URL, timeout=3) as resp:
            if resp.status == 200:
                return 0
            return 1
    except Exception:
        return 1


if __name__ == "__main__":
    sys.exit(main())
