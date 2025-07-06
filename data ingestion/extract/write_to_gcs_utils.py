from google.cloud import bigquery
import json
import pyarrow
import gcsfs
from write_json_to_gcs_utils import upload_json_object_to_gcs

def write_to_gcs(stravadata_df, GCS_BUCKET_NAME, GCS_BUCKET_NAME_II, state_data):
    try:
        client_bigquery = bigquery.Client()
        query = ('SELECT id FROM `strava-project-463820.strava_activity_dataset.strava_activity_data`')
        query_job = client_bigquery.query(query)
        existing_ids = {row['id'] for row in query_job}
        new_stravadata_df = stravadata_df[~stravadata_df['id'].isin(list(existing_ids))]

        if not new_stravadata_df.empty:
            LAST_ACTIVITY_DT = new_stravadata_df['end_datetime'].max().strftime("%Y-%m-%d %H-%M-%S")
            output_filename = f'activity_{LAST_ACTIVITY_DT}.parquet'
            gcs_path = f'gs://{GCS_BUCKET_NAME}/{output_filename}'
            print(f"Writing new data to {gcs_path}...")
            new_stravadata_df.to_parquet(gcs_path, engine = 'pyarrow', index = False)
            state_data['last_activity_dt'] = LAST_ACTIVITY_DT
            print('Successfully wrote new data')
            if not upload_json_object_to_gcs(GCS_BUCKET_NAME_II, 'state.json', state_data):
                raise Exception("Failed to upload updated state.json to GCS")
            print('Successfully updated state.json in GCS')
            return new_stravadata_df
        else:
            print('No new activities to load after filtering')
            return None

    except Exception as e:
        print(f'An error occurred during BigQuery deduplication or GCS write: {e}')
        raise