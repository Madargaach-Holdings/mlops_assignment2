#!/bin/bash

# Simple HTTP smoke test.
# Usage: scripts/smoke_test.sh <url>

set -euo pipefail

URL="${1:-http://paffenroth-23.dyn.wpi.edu:8010/}"

curl -fsS -m 10 -o /dev/null "${URL}"
echo "OK: ${URL} responded with HTTP 200"


