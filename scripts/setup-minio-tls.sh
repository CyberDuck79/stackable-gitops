#!/usr/bin/env bash
# setup-minio-tls.sh — generates a self-signed CA + server cert for MinIO
# and stores them as Kubernetes Secrets.
#
# Run this ONCE before first deployment, or when certs expire.
# The private key is never committed to git.
#
# Usage: ./scripts/setup-minio-tls.sh
set -euo pipefail

NAMESPACE="data-platform"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Generating self-signed CA for MinIO..."
openssl req -new -x509 -days 3650 -nodes \
  -subj "/CN=minio-local-ca" \
  -out "$WORK_DIR/ca.crt" -keyout "$WORK_DIR/ca.key"

echo "==> Generating MinIO server key and CSR..."
openssl req -new -nodes \
  -subj "/CN=minio.data-platform.svc.cluster.local" \
  -out "$WORK_DIR/server.csr" -keyout "$WORK_DIR/server.key"

echo "==> Signing server certificate with local CA..."
cat > "$WORK_DIR/san.ext" << 'EOF'
subjectAltName=DNS:minio.data-platform.svc.cluster.local,DNS:minio.data-platform,DNS:minio,DNS:localhost,IP:127.0.0.1
EOF
openssl x509 -req -days 3650 \
  -CA "$WORK_DIR/ca.crt" -CAkey "$WORK_DIR/ca.key" -CAcreateserial \
  -extfile "$WORK_DIR/san.ext" \
  -in "$WORK_DIR/server.csr" -out "$WORK_DIR/server.crt"

echo "==> Creating namespace (if not exists)..."
kubectl get namespace "$NAMESPACE" &>/dev/null || \
  kubectl create namespace "$NAMESPACE"

echo "==> Creating MinIO TLS secret (cert + key)..."
kubectl -n "$NAMESPACE" create secret generic minio-tls \
  --from-file=public.crt="$WORK_DIR/server.crt" \
  --from-file=private.key="$WORK_DIR/server.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating MinIO CA cert secret (for Trino/Hive TLS verification)..."
kubectl -n "$NAMESPACE" create secret generic minio-tls-ca \
  --from-file=ca.crt="$WORK_DIR/ca.crt" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" label secret minio-tls-ca \
  secrets.stackable.tech/class=minio-tls-ca \
  --overwrite

echo ""
echo "✓ TLS secrets created in namespace '$NAMESPACE':"
echo "    minio-tls       — server cert + key (for MinIO)"
echo "    minio-tls-ca    — CA cert (for Trino/Hive to verify MinIO)"
echo ""
echo "Next: commit the manifest changes and sync ArgoCD, or run:"
echo "    kubectl apply -k platform/hive/"
echo "    kubectl apply -f argocd/apps/minio.yaml && argocd app sync minio"
