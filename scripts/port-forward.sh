#!/usr/bin/env bash
# port-forward.sh — exposes all data platform services on localhost.
#
# Use this when the kind cluster was created without all extraPortMappings.
# For a fresh cluster with the updated kind-config.yaml, NodePorts work directly.
#
# Usage:
#   Start: ./scripts/port-forward.sh
#   Stop:  ./scripts/port-forward.sh stop

set -euo pipefail

NAMESPACE="data-platform"
PID_FILE="/tmp/stackable-pf-pids.txt"

stop_all() {
  if [[ -f "$PID_FILE" ]]; then
    echo "Stopping port-forwards..."
    # shellcheck disable=SC2046
    kill $(cat "$PID_FILE") 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "Done."
  else
    echo "No port-forwards running (no PID file found)."
  fi
  exit 0
}

[[ "${1:-}" == "stop" ]] && stop_all

# Kill any stale port-forwards from a previous run
[[ -f "$PID_FILE" ]] && kill $(cat "$PID_FILE") 2>/dev/null || true
: > "$PID_FILE"

forward() {
  local svc="$1" local_port="$2" remote_port="$3"
  kubectl -n "$NAMESPACE" port-forward "svc/$svc" "${local_port}:${remote_port}" \
    >/dev/null 2>&1 &
  echo "$!" >> "$PID_FILE"
}

echo "Starting port-forwards for all data platform services..."

forward airflow-webserver  8080  8080
forward minio              9000  9000
forward minio-console      9001  9001
forward superset-node      8088  8088
forward trino-coordinator  8443  8443

sleep 1  # give port-forwards a moment to establish

echo ""
echo "Services available at:"
echo "  http://localhost:8080   — Airflow       (admin / airflow)"
echo "  https://localhost:9000  — MinIO API (S3)"
echo "  https://localhost:9001  — MinIO Console (minio-root / minio-root-password)"
echo "  http://localhost:8088   — Superset"
echo "  https://localhost:8443  — Trino CLI     (--user admin --insecure)"
echo ""
echo "PIDs written to $PID_FILE"
echo "Stop with: ./scripts/port-forward.sh stop"
