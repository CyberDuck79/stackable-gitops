# Step 3 — Run the NYC Taxi Example

This guide walks you through the built-in demo: a synthetic NYC taxi pipeline that
exercises the full stack — Airflow → MinIO → Hive → Trino → Superset.

Make sure you have completed [Step 2 — Deploy the Data Platform](02-data-platform.md)
and that all pods are ready before continuing.

---

## What the example does

```
Airflow DAG: taxi_pipeline
│
├── generate_and_upload
│   Generates 5 000 synthetic taxi trips (seed=42, reproducible)
│   and uploads them as a single Parquet file to MinIO:
│     s3://hive/raw/taxi/yellow_tripdata_sample.parquet
│
└── create_hive_tables
    Creates two tables via Trino:
      hive.raw.taxi_trips    — EXTERNAL table reading the Parquet file
      hive.mart.taxi_summary — ORC CTAS aggregated by zone / date / hour
```

The mart table (`taxi_summary`) has these columns:

| Column | Type | Description |
|---|---|---|
| `pickup_zone` | VARCHAR | One of 10 NYC zones |
| `trip_date` | DATE | Calendar date of pickup |
| `pickup_hour` | INTEGER | Hour of pickup (0–23) |
| `trip_count` | BIGINT | Number of trips in that zone/date/hour |
| `avg_fare` | DOUBLE | Average fare amount ($) |
| `avg_distance` | DOUBLE | Average trip distance (miles) |
| `total_tips` | DOUBLE | Sum of tips ($) |

Superset is seeded automatically on each ArgoCD sync (PostSync job) with:
- A Trino database connection
- The `taxi_summary` dataset
- Four charts and the **NYC Taxi Summary** dashboard

---

## 1. Start port-forwards

```bash
bash scripts/port-forward.sh
```

---

## 2. Trigger the DAG

Open the Airflow UI at <http://localhost:8080> and log in (default: `airflow` / `airflow`).

Navigate to **DAGs → taxi_pipeline** and click **Trigger DAG ▶**.

Or trigger via the API:

```bash
curl -s -X POST "http://localhost:8080/api/v1/dags/taxi_pipeline/dagRuns" \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n 'admin:adminadmin' | base64)" \
  -d '{"logical_date": null}'
```

The pipeline runs in **~30 seconds**. Both tasks should turn green.

---

## 3. Verify the data in Trino

You can query the tables directly from the Trino UI at <https://localhost:8443/ui>
or with the CLI:

```bash
./trino.jar --insecure --server https://localhost:8443 --user admin \
  --execute "SELECT pickup_zone, SUM(trip_count) AS trips
             FROM hive.mart.taxi_summary
             GROUP BY pickup_zone
             ORDER BY trips DESC"
```

Expected: 10 rows, one per zone, ~500 trips each.

---

## 4. View the dashboard in Superset

Open Superset at <http://localhost:8088> and log in (default: `admin` / `admin`).

Navigate to **Dashboards → NYC Taxi Summary**.

The dashboard contains four panels:

| Panel | Type | Shows |
|---|---|---|
| Total Taxi Trips | KPI | `SUM(trip_count)` across all data |
| Trips by Pickup Zone | Pie chart | Share of trips per zone |
| Daily Trip Volume | Bar chart | Trips per day over the sample month |
| Zone Fare Summary | Table | Trips, avg fare, avg distance, total tips by zone |

If the dashboard was not created automatically (e.g. the PostSync job ran before the
DAG), re-sync the `superset` ArgoCD app:

```bash
argocd app sync superset --server localhost:30443 --insecure
```

The PostSync job is idempotent — it skips any resources that already exist.
