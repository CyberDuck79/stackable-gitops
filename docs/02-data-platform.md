# Step 2 — Deploy the Stackable Data Platform

This guide deploys the full data platform using the ArgoCD App of Apps pattern.  
Make sure you have completed [Step 1 — Local cluster setup](01-local-cluster-setup.md) first.

## Architecture overview

```
ArgoCD App of Apps (data-platform)
├── [wave -5]  sealed-secrets          ← Sealed Secrets controller
├── [wave -4]  commons-operator        ← Stackable core operators
│              secret-operator
│              listener-operator
├── [wave -3]  hive-operator           ← Stackable product operators
│              airflow-operator
│              trino-operator
│              superset-operator
├── [wave -2]  minio                   ← Infrastructure
│              hive-postgresql
│              airflow-postgresql
│              airflow-redis
│              superset-postgresql
├── [wave -1]  hive                    ← Hive metastore stacklet
├── [wave  0]  airflow                 ← Airflow + Superset stacklets
│              superset
└── [wave  1]  trino                   ← Trino (depends on Hive catalog)
```

Each sync wave ensures its dependencies are available before the next wave starts.

---

## 1. Generate Sealed Secrets

The platform manifests reference `SealedSecret` resources. You must generate these from the templates before applying anything.

### Create the secret templates directory

```bash
mkdir -p secrets-templates
```

The `secrets-templates/` directory is git-ignored. **Never commit anything from it.**

### Create the plain-text templates

Copy the example files provided in `secrets-templates/` (or create them by hand):

#### Hive — MinIO credentials

```bash
cat > secrets-templates/hive-minio-credentials.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: hive-minio-credentials
  namespace: data-platform
  labels:
    secrets.stackable.tech/class: hive-s3-secret-class
type: Opaque
stringData:
  accessKey: hive
  secretKey: hive-secret-key
EOF
```

> **Production**: use a strong, randomly generated `secretKey`.

#### Hive — PostgreSQL credentials

```bash
cat > secrets-templates/hive-db-credentials.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: hive-db-credentials
  namespace: data-platform
type: Opaque
stringData:
  username: hive
  password: hive
EOF
```

#### Airflow credentials

```bash
cat > secrets-templates/airflow-credentials.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: airflow-credentials
  namespace: data-platform
type: Opaque
stringData:
  adminUser.username: airflow
  adminUser.firstname: Airflow
  adminUser.lastname: Admin
  adminUser.email: airflow@example.com
  adminUser.password: airflow
  connections.sqlalchemyDatabaseUri: postgresql+psycopg2://airflow:airflow@airflow-postgresql.data-platform.svc.cluster.local/airflow
  connections.celeryResultBackend: db+postgresql://airflow:airflow@airflow-postgresql.data-platform.svc.cluster.local/airflow
  connections.celeryBrokerUrl: redis://:redis@airflow-redis-master.data-platform.svc.cluster.local:6379/0
EOF
```

> Adjust passwords to match your values in `argocd/apps/airflow-postgresql.yaml` and `argocd/apps/airflow-redis.yaml`.

#### Superset credentials

```bash
cat > secrets-templates/superset-credentials.yaml <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: superset-credentials
  namespace: data-platform
type: Opaque
stringData:
  adminUser.username: admin
  adminUser.firstname: Superset
  adminUser.lastname: Admin
  adminUser.email: admin@example.com
  adminUser.password: admin
  connections.secretKey: a-very-long-random-secret-key-change-me
  connections.sqlalchemyDatabaseUri: postgresql://superset:superset@superset-postgresql.data-platform.svc.cluster.local/superset
EOF
```

> Change `connections.secretKey` to a long random string in production.

### Seal all secrets

```bash
make seal-secrets
```

This runs `kubeseal` against `tls.crt` (fetched in Step 1) for each template and writes the resulting `SealedSecret` YAML into the correct `platform/<component>/` directory.

Alternatively, run the script directly:

```bash
bash scripts/generate-sealed-secrets.sh
```

### Commit the sealed secrets

```bash
git add platform/
git commit -m "chore: add sealed secrets"
git push
```

---

## 2. Apply the ArgoCD Project

```bash
kubectl apply -f argocd/projects/data-platform.yaml
```

---

## 3. Bootstrap the App of Apps

```bash
kubectl apply -f argocd/apps/app-of-apps.yaml
```

ArgoCD will discover all Application manifests in `argocd/apps/` and sync them in wave order. Monitor progress in the ArgoCD UI at [http://localhost:30080](http://localhost:30080) or via CLI:

```bash
argocd app list
argocd app get data-platform
```

The full sync takes **10–20 minutes** on a local machine (mostly image pulls).

---

## 4. Verify each component

### Hive Metastore

```bash
kubectl -n data-platform get statefulset hive-metastore-default
```

Expected:

```
NAME                     READY   AGE
hive-metastore-default   1/1     3m
```

### Airflow

```bash
kubectl -n data-platform get statefulset \
  airflow-webserver-default \
  airflow-scheduler-default \
  airflow-worker-default
```

Access the Airflow UI at <http://localhost:8080> (start port-forwards first — see below).

Log in with the credentials you set in `secrets-templates/airflow-credentials.yaml`.

### Trino

```bash
kubectl -n data-platform get statefulset \
  trino-coordinator-default \
  trino-worker-default
```

Access the Trino UI at <https://localhost:8443/ui> (start port-forwards first — see below).

Log in with username `admin` (no password required — no auth configured in this getting-started setup).

Run a test query via the Trino CLI:

```bash
# Download the Trino CLI (version must match the cluster version)
curl --fail -o trino.jar \
  https://repo.stackable.tech/repository/packages/trino-cli/trino-cli-479
chmod +x trino.jar

./trino.jar --insecure --server https://localhost:8443 --user admin \
  --execute "SHOW CATALOGS"
```

Expected output includes `hive` and `system`.

### Superset

```bash
kubectl -n data-platform get statefulset superset-node-default
```

Access Superset at <http://localhost:8088> (start port-forwards first — see below).

Log in with the credentials you set in `secrets-templates/superset-credentials.yaml`.

#### Connect Superset to Trino

In Superset: **Settings → Database Connections → + Database**

- Database: `Trino`
- SQLAlchemy URI:
  ```
  trino://admin@trino-coordinator.data-platform.svc.cluster.local:8443/hive?http_scheme=https&verify=false
  ```

  > `http_scheme=https` is required — the trino SQLAlchemy dialect defaults to HTTP, which causes a TLS handshake error on port 8443.

### Starting port-forwards

All services above are exposed via `kubectl port-forward`. Run the helper script once to start them all in the background:

```bash
bash scripts/port-forward.sh
```

To stop:

```bash
bash scripts/port-forward.sh stop
```

---

## 5. Sealed secrets — ongoing workflow

When you need to rotate or add a secret:

1. Edit the relevant file in `secrets-templates/`
2. Re-run `make seal-secrets` (or the individual kubeseal command)
3. Commit and push the updated `platform/<component>/*-sealed-secret.yaml`
4. ArgoCD will pick up the change and apply the new SealedSecret automatically

---

## Component reference

| Component | URL (port-forward) | Default credentials |
|-----------|-------------------|---------------------|
| ArgoCD | <http://localhost:30080> | admin / *see bootstrap output* |
| Airflow | <http://localhost:8080> | airflow / airflow |
| Trino UI | <https://localhost:8443/ui> | admin / (none) |
| Superset | <http://localhost:8088> | admin / admin |
| MinIO Console | <https://localhost:9001> | minio-root / minio-root-password |

---

## Troubleshooting

### Operators not starting

```bash
kubectl -n stackable-operators get pods
kubectl -n stackable-operators describe pod <pod-name>
```

OCI Helm pull errors usually mean OCI support is not enabled in ArgoCD — re-run `bash bootstrap/argocd-install.sh` and check that `helm.enable-oci: "true"` is set in the `argocd-cmd-params-cm` ConfigMap.

### SealedSecret decryption failure

```bash
kubectl -n data-platform describe sealedsecret <name>
```

A `no key could decrypt secret` error means the SealedSecret was encrypted with a different cluster key. Re-generate with `make seal-secrets` using the current `tls.crt`.

### HiveCluster not ready

```bash
kubectl -n data-platform describe hivecluster hive
kubectl -n data-platform logs -l app.kubernetes.io/name=hive --tail=50
```

If you see Thrift errors connecting to Trino, try downgrading Hive to `3.1.3` in `platform/hive/hive-cluster.yaml`. See [upstream issue](https://docs.stackable.tech/home/stable/hive/#hive-4-issues).

### Resource pressure on kind

If pods are pending due to insufficient resources, scale down replicas:

```bash
# Example: reduce Trino workers to 0 temporarily
kubectl -n data-platform patch trinocluster trino \
  --type merge \
  -p '{"spec":{"workers":{"roleGroups":{"default":{"replicas":0}}}}}'
```
