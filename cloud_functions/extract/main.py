import os
import sys
from utils.secrets import access_secret_version, get_required_secret
import gcsfs
from datetime import datetime, timedelta
from read_json_from_gcs_utils import read_json_from_gcs
import json
from refresh_access_token_utils import refresh_access_token
from stravalib.client import Client
from extract_data_utils import get_activity_data
import pandas as pd
from write_to_gcs_utils import write_to_gcs

def extract_and_load_data(request):
    project_id = "strava-project-463820"
    secret_id = "secret_manager_id-strava-project-463820"

    secrets = access_secret_version(project_id, secret_id, version_id = "latest")

    STRAVA_CLIENT_ID = int(get_required_secret(secrets, "strava_client_id"))
    STRAVA_CLIENT_SECRET = get_required_secret(secrets, "strava_client_secret")
    REFRESH_TOKEN = get_required_secret(secrets, "refresh_token")
    GCS_BUCKET_NAME = get_required_secret(secrets, "gcs_bucket_name")
    GCS_BUCKET_NAME_II = get_required_secret(secrets, "gcs_bucket_name_II")

    state_data = read_json_from_gcs(GCS_BUCKET_NAME_II, "state.json")

    if state_data:
        EXPIRES_AT = state_data['expires_at']
        EXPIRES_AT_DT = datetime.fromtimestamp(int(EXPIRES_AT))
        LAST_ACTIVITY_DT = state_data['last_activity_dt']

    else:
        print('the state.json load returned None')
        return 'No state data found', 500

    try:
        if datetime.now() > EXPIRES_AT_DT:
            ACCESS_TOKEN, state_data = refresh_access_token(STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, REFRESH_TOKEN, state_data)
        else:
            ACCESS_TOKEN = state_data['access_token']
    except Exception as e:
        print('Could not obtain a valid access token. Exiting.')
        return 'Could not obtain a valid access token', 500

    try:
        client = Client(access_token = ACCESS_TOKEN)
        activities = client.get_activities(after = LAST_ACTIVITY_DT)
    except Exception as e:
        print(f'error {e} while trying to get strava activities')
        return 'Error getting Strava activities', 500

    all_activities = get_activity_data(activities)
    stravadata_df = pd.DataFrame(all_activities)

    if stravadata_df.empty:
        print('No new activities found. Exiting')
        return 'No new activities found', 200

    try:
        write_to_gcs(stravadata_df, GCS_BUCKET_NAME, GCS_BUCKET_NAME_II, state_data)
    except Exception as e:
        print(f"An error occurred during GCS write operation: {e}")
        return 'Failed to write data to GCS', 500

    return 'Function executed successfully', 200