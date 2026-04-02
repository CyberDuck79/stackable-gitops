# Stackable GitOps

A GitOps repository for deploying the [Stackable Data Platform](https://docs.stackable.tech/home/stable/) on Kubernetes using [ArgoCD](https://argo-cd.readthedocs.io/).

## What's included

| Component | Version | Role |
|-----------|---------|------|
| [Apache Hive Metastore](https://docs.stackable.tech/home/stable/hive/) | 4.0.1 | Table metadata store |
| [MinIO](https://min.io/) | 5.4.0 (chart) | S3-compatible object storage |
| [PostgreSQL](https://www.postgresql.org/) | 16.5.0 (chart) | Relational metadata backend |
| [Apache Airflow](https://docs.stackable.tech/home/stable/airflow/) | 3.1.6 | Workflow orchestration |
| [Trino](https://docs.stackable.tech/home/stable/trino/) | 479 | Distributed SQL query engine |
| [Apache Superset](https://docs.stackable.tech/home/stable/superset/) | 6.0.0 | Data visualization |

All secrets are managed with [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) (kubeseal).

## Repository structure

```
.
├── bootstrap/              # One-time cluster bootstrap scripts
│   ├── kind-config.yaml    # Kind cluster configuration
│   └── argocd-install.sh   # ArgoCD installation script
├── argocd/
│   ├── projects/           # ArgoCD Project definitions
│   └── apps/               # ArgoCD Application definitions (App of Apps)
├── platform/               # Kubernetes manifests for each component
│   ├── hive/
│   ├── airflow/
│   ├── trino/
│   └── superset/
├── secrets-templates/      # Plain-text secret templates (git-ignored)
├── scripts/                # Helper scripts
│   └── generate-sealed-secrets.sh
└── docs/
    ├── 01-local-cluster-setup.md
    ├── 02-data-platform.md
    ├── 03-taxi-example.md
    └── 04-going-further.md
```

## Getting started

### Step 1 — Local cluster with kind and ArgoCD

Follow **[docs/01-local-cluster-setup.md](docs/01-local-cluster-setup.md)** to:
- Create a local Kubernetes cluster with kind
- Install and configure ArgoCD
- Install the kubeseal CLI and the sealed-secrets controller

### Step 2 — Deploy the data platform

Follow **[docs/02-data-platform.md](docs/02-data-platform.md)** to:
- Generate your sealed secrets
- Configure this repository as an ArgoCD source
- Deploy all platform components via the App of Apps pattern

### Step 3 — Run the NYC Taxi example

Follow **[docs/03-taxi-example.md](docs/03-taxi-example.md)** to:
- Trigger the `taxi_pipeline` DAG in Airflow
- Verify the data in Trino
- View the auto-generated NYC Taxi Summary dashboard in Superset

### Step 4 — Going further

Follow **[docs/04-going-further.md](docs/04-going-further.md)** to:
- Understand Stackable concepts (operators, stacklets, roles, role groups)
- Add a new stacklet to the platform following the established GitOps pattern

## Secret management workflow

This repo uses [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) so that encrypted secrets can be safely committed to Git.

```
plaintext secret template          sealed secret (committed to Git)
  secrets-templates/  ──kubeseal──►  platform/<component>/*-sealed-secret.yaml
```

See the Makefile for helper targets:

```bash
# Fetch the cluster public cert (run once after cluster setup)
make fetch-cert

# Generate all sealed secrets from templates
make seal-secrets
```

> **Never commit anything from `secrets-templates/`** — it is git-ignored.

## Stackable operator versions

All operators use the Stackable Data Platform release **26.3.0**, installed from the OCI registry:
```
oci://oci.stackable.tech/sdp-charts/<operator>:26.3.0
```

## References

- [Stackable Documentation](https://docs.stackable.tech/home/stable/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [kind](https://kind.sigs.k8s.io/)
