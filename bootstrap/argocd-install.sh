#!/usr/bin/env bash
# bootstrap/argocd-install.sh
#
# Installs ArgoCD into the 'argocd' namespace and patches the argocd-server
# Service to NodePort so it is reachable from the host via the ports exposed
# in bootstrap/kind-config.yaml (30080 / 30443).
#
# Usage: bash bootstrap/argocd-install.sh

set -euo pipefail

ARGOCD_VERSION="v2.14.6"
ARGOCD_NAMESPACE="argocd"

echo "==> Installing ArgoCD ${ARGOCD_VERSION}..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "${ARGOCD_NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for ArgoCD deployments to be ready..."
kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment argocd-server --timeout=120s
kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment argocd-repo-server --timeout=120s
kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment argocd-application-controller --timeout=120s 2>/dev/null || \
  kubectl -n "${ARGOCD_NAMESPACE}" rollout status statefulset argocd-application-controller --timeout=120s

echo "==> Patching argocd-server Service to NodePort..."
kubectl -n "${ARGOCD_NAMESPACE}" patch svc argocd-server \
  -p '{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"nodePort":30080},{"name":"https","port":443,"nodePort":30443}]}}'

echo "==> Enabling OCI Helm support in ArgoCD..."
# repoURL for OCI Helm charts must NOT include the oci:// scheme prefix.
# ArgoCD v2.x requires the repo-server to be started with --enable-helm-oci,
# which maps to reposerver.enable.helm.oci in argocd-cmd-params-cm.
kubectl -n "${ARGOCD_NAMESPACE}" patch configmap argocd-cmd-params-cm \
  --type merge \
  -p '{"data":{"reposerver.enable.helm.oci":"true"}}'

echo "==> Restarting repo-server to pick up config changes..."
kubectl -n "${ARGOCD_NAMESPACE}" rollout restart deployment argocd-repo-server
kubectl -n "${ARGOCD_NAMESPACE}" rollout status deployment argocd-repo-server --timeout=60s

echo ""
echo "==> ArgoCD is ready!"
echo ""
echo "    UI:       http://localhost:30080"
echo "    Username: admin"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "    Password: ${ARGOCD_PASSWORD}"
echo ""
echo "==> Login with the ArgoCD CLI:"
echo "    argocd login localhost:30443 --username admin --password '${ARGOCD_PASSWORD}' --insecure"
