# secrets-templates/

This directory contains plain-text Kubernetes `Secret` templates.

**It is git-ignored — never commit anything here.**

These files are used as input to `kubeseal` to generate the `SealedSecret`
resources that live in `platform/<component>/`.

## Files to create

Follow the instructions in [docs/02-data-platform.md](../docs/02-data-platform.md) to populate:

| File | Used by |
|------|---------|
| `hive-minio-credentials.yaml` | Hive → MinIO S3 connection |
| `hive-db-credentials.yaml` | Hive → PostgreSQL connection |
| `airflow-credentials.yaml` | Airflow cluster (DB + Redis + admin user) |
| `superset-credentials.yaml` | Superset cluster (DB + secret key + admin user) |

Then run:

```bash
make fetch-cert   # once, after the sealed-secrets controller is running
make seal-secrets # generates platform/*/<name>-sealed-secret.yaml
```
