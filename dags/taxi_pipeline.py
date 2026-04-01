"""
NYC Taxi demo pipeline
======================

Generates a synthetic NYC taxi dataset, uploads it to MinIO as Parquet,
creates Hive schemas and tables via Trino, and produces an aggregated
mart table ready for Superset dashboards.

Trigger this DAG manually once after the platform is fully deployed.

Pipeline tasks:
  generate_and_upload  — 5 000 synthetic rows → s3://hive/raw/taxi/
  create_hive_tables   — hive.raw.taxi_trips (EXTERNAL) + hive.mart.taxi_summary

Note: boto3, pandas, pyarrow and trino are all pre-installed in the
Stackable Airflow 3.1.6 worker image — no virtualenv required.
"""
from __future__ import annotations

import io
import random
from datetime import datetime, timedelta

import boto3
import pandas as pd
import trino
import urllib3
from botocore.config import Config

from airflow.sdk import dag, task


@dag(
    dag_id="taxi_pipeline",
    description=(
        "NYC Taxi demo — uploads synthetic data to MinIO, "
        "creates Hive raw + mart tables via Trino."
    ),
    schedule=None,  # manual trigger only
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["demo", "nyc-taxi"],
)
def taxi_pipeline():

    @task
    def generate_and_upload() -> None:
        """Generate 5 000 synthetic taxi rows and upload as Parquet to MinIO."""
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        random.seed(42)
        ZONES = [
            "Midtown Manhattan", "JFK Airport", "LaGuardia Airport",
            "Downtown Brooklyn", "Upper West Side", "Harlem",
            "Queens", "Staten Island", "The Bronx", "Flushing",
        ]
        PAYMENT = ["credit_card", "cash", "no_charge", "dispute"]

        rows = []
        base = datetime(2024, 1, 1)
        for _ in range(5_000):
            pickup = base + timedelta(
                hours=random.randint(0, 24 * 30),
                minutes=random.randint(0, 59),
            )
            minutes = random.randint(5, 90)
            dropoff = pickup + timedelta(minutes=minutes)
            dist = round(random.uniform(0.5, 25.0), 2)
            fare = round(3.00 + dist * 2.50 + minutes * 0.50, 2)
            tip = round(
                fare * random.uniform(0.0, 0.30) * (1 if random.random() > 0.3 else 0),
                2,
            )
            rows.append({
                "pickup_datetime":  pickup,
                "dropoff_datetime": dropoff,
                "passenger_count":  random.randint(1, 4),
                "trip_distance":    dist,
                "pickup_zone":      random.choice(ZONES),
                "dropoff_zone":     random.choice(ZONES),
                "fare_amount":      fare,
                "tip_amount":       tip,
                "total_amount":     round(fare + tip + 0.50, 2),
                "payment_type":     random.choice(PAYMENT),
            })

        buf = io.BytesIO()
        pd.DataFrame(rows).to_parquet(buf, index=False, engine="pyarrow")
        buf.seek(0)

        s3 = boto3.client(
            "s3",
            endpoint_url="https://minio.data-platform.svc.cluster.local:9000",
            aws_access_key_id="hive",
            aws_secret_access_key="hive-secret-key",
            config=Config(signature_version="s3v4"),
            verify=False,
        )
        s3.put_object(
            Bucket="hive",
            Key="raw/taxi/yellow_tripdata_sample.parquet",
            Body=buf.getvalue(),
        )
        print("Uploaded 5 000 rows → s3://hive/raw/taxi/yellow_tripdata_sample.parquet")

    @task
    def create_hive_tables() -> None:
        """Create Hive schemas, external raw table, and aggregated mart table."""

        conn = trino.dbapi.connect(
            host="trino-coordinator.data-platform.svc.cluster.local",
            port=8443,
            user="admin",
            http_scheme="https",
            verify=False,
        )
        cur = conn.cursor()

        statements = [
            "CREATE SCHEMA IF NOT EXISTS hive.raw WITH (location = 's3a://hive/raw/')",
            "CREATE SCHEMA IF NOT EXISTS hive.mart WITH (location = 's3a://hive/mart/')",
            # External table — reads the Parquet files written by the previous task
            """CREATE TABLE IF NOT EXISTS hive.raw.taxi_trips (
  pickup_datetime  TIMESTAMP,
  dropoff_datetime TIMESTAMP,
  passenger_count  INTEGER,
  trip_distance    DOUBLE,
  pickup_zone      VARCHAR,
  dropoff_zone     VARCHAR,
  fare_amount      DOUBLE,
  tip_amount       DOUBLE,
  total_amount     DOUBLE,
  payment_type     VARCHAR
) WITH (
  external_location = 's3a://hive/raw/taxi/',
  format = 'PARQUET'
)""",
            # Recreate mart table to keep it fresh on re-runs
            "DROP TABLE IF EXISTS hive.mart.taxi_summary",
            """CREATE TABLE hive.mart.taxi_summary WITH (format = 'ORC') AS
SELECT
  pickup_zone,
  CAST(pickup_datetime AS DATE)  AS trip_date,
  HOUR(pickup_datetime)          AS pickup_hour,
  COUNT(*)                       AS trip_count,
  ROUND(AVG(fare_amount),   2)   AS avg_fare,
  ROUND(AVG(trip_distance), 2)   AS avg_distance,
  ROUND(SUM(tip_amount),    2)   AS total_tips
FROM hive.raw.taxi_trips
GROUP BY
  pickup_zone,
  CAST(pickup_datetime AS DATE),
  HOUR(pickup_datetime)
ORDER BY trip_count DESC""",
        ]

        for stmt in statements:
            label = stmt.strip()[:60].replace("\n", " ")
            print(f"  → {label}…")
            cur.execute(stmt)

        cur.execute("SELECT COUNT(*) FROM hive.mart.taxi_summary")
        print(f"hive.mart.taxi_summary ready — {cur.fetchone()[0]} rows")

    generate_and_upload() >> create_hive_tables()


taxi_pipeline()
