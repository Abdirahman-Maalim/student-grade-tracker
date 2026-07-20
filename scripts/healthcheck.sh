#!/usr/bin/env bash
#
# healthcheck.sh — verify the running stack is healthy.
#
set -uo pipefail

FRONTEND_URL="${FRONTEND_URL:-http://127.0.0.1:8080/healthz}"
BACKEND_DIRECT_URL="${BACKEND_DIRECT_URL:-http://127.0.0.1:3000/health}"

OVERALL_STATUS=0

check() {
  local name="$1"
  local url="$2"

  if curl --fail --silent --show-error --max-time 5 "$url" > /dev/null; then
    echo "PASS: ${name} is reachable (${url})"
    return 0
  else
    echo "FAIL: ${name} is NOT reachable (${url})"
    return 1
  fi
}

echo "Running health checks..."
echo "-------------------------------"

if ! check "Frontend" "$FRONTEND_URL"; then
  OVERALL_STATUS=1
fi

# Use 127.0.0.1 instead of localhost to avoid IPv6 issues
if docker compose exec -T backend wget -qO- http://127.0.0.1:3000/health > /dev/null 2>&1; then
  echo "PASS: Backend is reachable (via docker compose exec)"
else
  echo "FAIL: Backend is NOT reachable"
  OVERALL_STATUS=1
fi

echo "-------------------------------"

if [[ "$OVERALL_STATUS" -ne 0 ]]; then
  echo "One or more health checks FAILED."
  exit 1
fi

echo "All health checks PASSED."
exit 0
