import os
from google.cloud import storage
import json

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = '../service_key.json' 

def read_json_from_gcs(bucket_name, file_path):
    """
    Reads a JSON file from a GCS bucket.
    """
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_path)
        json_string = blob.download_as_string()
        data = json.loads(json_string)
        return data
    except Exception as e:
        print(f"Error reading JSON from GCS: {e}")
        return None