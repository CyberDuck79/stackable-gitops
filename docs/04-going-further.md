# Step 4 — Going Further: Adding a New Stacklet

Once you are comfortable with the platform, the natural next step is adding another
Stackable product. This guide walks through the pattern using Apache Kafka as an
example — the same steps apply to any product in the
[Stackable ecosystem](https://docs.stackable.tech/home/stable/).

## Quick recap of the concepts

**Operator** — a controller pod that runs in the cluster and reacts to a custom
resource (e.g. `KafkaCluster`). It owns all the generated pods, services, and
configmaps. You never edit those directly.

**Stacklet** — the running product instance managed by a CR. One `KafkaCluster`
manifest = one Kafka stacklet.

**Role** — a distinct process type within the product
(e.g. `brokers`, `coordinators`, `workers`). Each role runs different code, needs
different resources, and gets different config. Roles are the direct children of
`spec` that contain a `roleGroups:` key.

**Role group** — a named subset of replicas within a role that share the same
configuration. `default` is the conventional name when you only need one group.
You can add more groups for heterogeneous hardware (e.g. a `heavy` group with more
memory on specific nodes).

```
spec:
  image: ...
  clusterConfig: ...        ← cluster-wide settings (not a role)
  brokers:                  ← ROLE
    roleGroups:
      default:              ← role group → 1 pod
        replicas: 1
        config:
          resources:
            cpu:  { min: "200m", max: "1000m" }
            memory: { limit: "1Gi" }
```

---

## How to add a new stacklet — step by step

### 1. Read the product docs

Every Stackable product has a dedicated page at
`https://docs.stackable.tech/home/stable/<product>/`.

Key things to find:
- Which **roles** exist and what each one does
- What **`clusterConfig`** fields are required (database, S3, credentials secret…)
- Any **dependencies** (e.g. a ZooKeeper stacklet for older Kafka versions)
- The **supported product versions** for your SDP release (26.3.0 here)

---

### 2. Add the operator Application

Create `argocd/apps/kafka-operator.yaml` following the pattern of the existing
operators:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kafka-operator
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-3"   # same wave as all other operators
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: data-platform
  source:
    repoURL: oci://oci.stackable.tech/sdp-charts/kafka-operator
    chart: kafka-operator
    targetRevision: 26.3.0
  destination:
    server: https://kubernetes.default.svc
    namespace: stackable-operators
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

> Use wave `-3` for all product operators — the same as `airflow-operator`,
> `trino-operator`, etc. in this repo.

---

### 3. Create the platform manifest

Create `platform/kafka/kafka-cluster.yaml`. Use the docs to fill in the correct
roles and `clusterConfig` fields:

```yaml
---
apiVersion: kafka.stackable.tech/v1alpha1
kind: KafkaCluster
metadata:
  name: kafka
  namespace: data-platform
spec:
  image:
    productVersion: "3.7.0"
    pullPolicy: IfNotPresent
  clusterConfig:
    zookeeper:
      reference: zookeeper      # name of a ZookeeperCluster CR in the same namespace
  brokers:                      # the only role for Kafka
    roleGroups:
      default:
        replicas: 1
        config:
          resources:
            cpu:  { min: "200m", max: "1000m" }
            memory: { limit: "1Gi" }
```

---

### 4. Add a kustomization

Create `platform/kafka/kustomization.yaml`:

```yaml
resources:
  - kafka-cluster.yaml
```

If the product needs secrets (database credentials, MinIO keys…), add them here
too and generate the `SealedSecret` with `make seal-secrets` as in Step 2.

---

### 5. Add the stacklet Application

Create `argocd/apps/kafka.yaml`. Set the sync wave **after** the operator and any
infrastructure dependencies:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kafka
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"   # after operator (-3) and infra (-2/-1)
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: data-platform
  source:
    repoURL: https://github.com/your-org/stackable-gitops.git
    targetRevision: HEAD
    path: platform/kafka
  destination:
    server: https://kubernetes.default.svc
    namespace: data-platform
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

---

### 6. Commit and push — ArgoCD does the rest

```bash
git add argocd/apps/kafka-operator.yaml argocd/apps/kafka.yaml platform/kafka/
git commit -m "feat: add Kafka stacklet"
git push
```

ArgoCD will detect the new Applications (they are in the same directory as the
existing ones, which the App of Apps already watches) and sync them in wave order.

---

## Debugging a new stacklet

When something does not come up, work through these in order:

```bash
# 1. Check the operator is running
kubectl -n stackable-operators get pods -l app.kubernetes.io/name=kafka-operator

# 2. Read operator logs — it will say exactly why it cannot reconcile
kubectl -n stackable-operators logs -l app.kubernetes.io/name=kafka-operator --tail=60

# 3. Describe the CR to see operator-written status/conditions
kubectl -n data-platform describe kafkacluster kafka

# 4. Check the generated ConfigMaps to verify config was rendered correctly
kubectl -n data-platform get configmap -l app.kubernetes.io/name=kafka -o yaml

# 5. Check the pods themselves
kubectl -n data-platform get pods -l app.kubernetes.io/name=kafka
kubectl -n data-platform logs -l app.kubernetes.io/name=kafka --tail=50
```

Common problems:
- **CR created before the operator is ready** — the operator will reconcile it once it starts; no action needed.
- **Missing secret key** — the operator log will name the exact key it expected.
- **Dependency not found** (e.g. ZookeeperCluster) — add it at a lower wave number so it is ready first.
- **Wrong product version** — check the SDP release notes for the list of supported versions at `docs.stackable.tech/home/stable/release-notes/`.
