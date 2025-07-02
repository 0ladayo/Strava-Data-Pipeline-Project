import os
import sys
from utils.secrets import access_secret_version, get_required_secret
from google.cloud import storage
from numpy import append
import pandas as pd
from google.cloud import bigquery
import pandas_gbq

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = '../service_key.json'

PROJECT_ID  = "strava-project-463820"
SECRET_ID = "secret_manager_id-strava-project-463820"
secrets = access_secret_version(PROJECT_ID, SECRET_ID, version_id = "latest")

GCS_BUCKET_NAME = get_required_secret(secrets, "gcs_bucket_name")
TABLE_ID =get_required_secret(secrets, "table_id")

storage_client = storage.Client()
bigquery_client = bigquery.Client()

try:
    bucket = storage_client.get_bucket(GCS_BUCKET_NAME)
except Exception as e:
    print(f"Error getting bucket '{GCS_BUCKET_NAME}': {e}")
    sys.exit(0)

blobs = list(bucket.list_blobs())

try:
    if blobs:
        latest_blob = max(blobs, key=lambda b: b.updated)
        latest_file_name = latest_blob.name
        print(f"Processing latest file: {latest_file_name}")
        df = pd.read_parquet(f'gs://{GCS_BUCKET_NAME}/{latest_file_name}')
        pandas_gbq.to_gbq(df, TABLE_ID, project_id=PROJECT_ID, if_exists='append')
        print(f"Successfully appended data to {TABLE_ID}")
    else:
        print(f'There are no files in the {GCS_BUCKET_NAME} bucket.')

except Exception as e:
    print(f'An error occurred: {e}')