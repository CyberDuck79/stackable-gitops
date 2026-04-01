#!/usr/bin/env bash
# scripts/generate-sealed-secrets.sh
#
# Converts plain-text Secret templates in secrets-templates/ into
# SealedSecret resources and writes them into the correct platform/ directory.
#
# Prerequisites:
#   - kubeseal CLI installed
#   - tls.crt present (fetch with: make fetch-cert)
#   - secrets-templates/ directory populated (see docs/02-data-platform.md)
#
# Usage:
#   bash scripts/generate-sealed-secrets.sh
#   make seal-secrets

set -euo pipefail

CERT="${CERT:-tls.crt}"
NAMESPACE="data-platform"
SCOPE="namespace-wide"

seal() {
  local src="$1"
  local dst="$2"

  if [[ ! -f "${src}" ]]; then
    echo "  [SKIP] ${src} not found — create it from the template in docs/02-data-platform.md"
    return
  fi

  echo "  Sealing ${src} → ${dst}"
  kubeseal \
    --cert "${CERT}" \
    --namespace "${NAMESPACE}" \
    --scope "${SCOPE}" \
    --format yaml \
    < "${src}" \
    > "${dst}"
}

if [[ ! -f "${CERT}" ]]; then
  echo "ERROR: ${CERT} not found."
  echo "       Run 'make fetch-cert' first to download the cluster public key."
  exit 1
fi

echo "==> Sealing Hive secrets..."
seal secrets-templates/hive-minio-credentials.yaml \
     platform/hive/minio-sealed-secret.yaml

seal secrets-templates/hive-db-credentials.yaml \
     platform/hive/db-sealed-secret.yaml

echo "==> Sealing Airflow secrets..."
seal secrets-templates/airflow-credentials.yaml \
     platform/airflow/credentials-sealed-secret.yaml

echo "==> Sealing Superset secrets..."
seal secrets-templates/superset-credentials.yaml \
     platform/superset/credentials-sealed-secret.yaml

echo ""
echo "Done. Commit the updated files in platform/ to Git."
echo "  git add platform/"
echo "  git commit -m 'chore: update sealed secrets'"
