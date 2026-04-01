# Step 1 — Local Kubernetes cluster with kind and ArgoCD

This guide sets up a local Kubernetes cluster with [kind](https://kind.sigs.k8s.io/) and installs [ArgoCD](https://argo-cd.readthedocs.io/) as the GitOps engine, plus [kubeseal](https://github.com/bitnami-labs/sealed-secrets) for secret management.

## Prerequisites

Install the following tools on your machine:

| Tool | Install |
|------|---------|
| [Docker](https://docs.docker.com/get-docker/) | Required by kind |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | Local Kubernetes |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Kubernetes CLI |
| [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) | ArgoCD CLI |
| [kubeseal](https://github.com/bitnami-labs/sealed-secrets#installation) | Sealed secrets CLI |
| [Helm](https://helm.sh/docs/intro/install/) | Helm CLI (for manual steps) |

### macOS one-liner (Homebrew)

```bash
brew install kind kubectl argocd kubeseal helm
```

---

## 1. Create the kind cluster

```bash
kind create cluster --name stackable --config bootstrap/kind-config.yaml
```

The cluster has 1 control-plane and 3 worker nodes to handle the full data platform stack.

Verify the cluster is ready:

```bash
kubectl cluster-info --context kind-stackable
kubectl get nodes
```

Expected output (all nodes `Ready`):

```
NAME                     STATUS   ROLES           AGE
stackable-control-plane  Ready    control-plane   1m
stackable-worker         Ready    <none>          1m
stackable-worker2        Ready    <none>          1m
stackable-worker3        Ready    <none>          1m
```

---

## 2. Install ArgoCD

Run the bootstrap script:

```bash
bash bootstrap/argocd-install.sh
```

The script:
1. Creates the `argocd` namespace and installs ArgoCD
2. Patches the `argocd-server` Service to **NodePort 30080/30443** so it is reachable from your host
3. Enables OCI Helm support (required for Stackable operator charts)

The script prints the initial admin password at the end. **Save it.**

### Open the ArgoCD UI

Navigate to [http://localhost:30080](http://localhost:30080) and log in with `admin` / `<password from above>`.

### Log in with the CLI

```bash
argocd login localhost:30443 \
  --username admin \
  --password '<paste password>' \
  --insecure
```

---

## 3. Install the Sealed Secrets controller

The Sealed Secrets controller is deployed by ArgoCD in [Step 2](02-data-platform.md). However, if you need the `kubeseal` cert before the full platform is up (e.g., to pre-generate secrets), you can install **only** the sealed-secrets app first:

```bash
# Apply the ArgoCD Project (required before any Application)
kubectl apply -f argocd/projects/data-platform.yaml

# Apply only the sealed-secrets Application
kubectl apply -f argocd/apps/sealed-secrets.yaml
```

ArgoCD will sync and install the Sealed Secrets controller into the `sealed-secrets` namespace.

Wait for it to be ready:

```bash
kubectl -n sealed-secrets rollout status deployment sealed-secrets-controller
```

### Fetch the cluster public certificate

```bash
kubeseal --fetch-cert \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  > tls.crt
```

> `tls.crt` is git-ignored. Keep it locally to generate sealed secrets.

---

## 4. Fork the repository

Before proceeding to the next guide, fork (or clone) this repository and update the `repoURL` field in the following files to point to your fork:

- `argocd/apps/app-of-apps.yaml`
- `argocd/apps/hive.yaml`
- `argocd/apps/airflow.yaml`
- `argocd/apps/trino.yaml`
- `argocd/apps/superset.yaml`

```bash
# Replace CyberDuck79 with your GitHub username or organization
sed -i '' 's|CyberDuck79|YOUR_ACTUAL_ORG|g' \
  argocd/apps/app-of-apps.yaml \
  argocd/apps/hive.yaml \
  argocd/apps/airflow.yaml \
  argocd/apps/trino.yaml \
  argocd/apps/superset.yaml
```

Then push your changes:

```bash
git add -A
git commit -m "chore: set repo URL"
git push
```

---

## Next step

Continue with **[docs/02-data-platform.md](02-data-platform.md)** to deploy the full data platform.
