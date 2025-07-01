import os
import sys
from dotenv import load_dotenv, set_key
import gcsfs
from datetime import datetime, timedelta
from read_json_from_gcs_utils import read_json_from_gcs
import json
from refresh_access_token_utils import refresh_access_token
from stravalib.client import Client
from extract_data_utils import get_activity_data
import pandas as pd
from write_to_gcs_utils import write_to_gcs

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = '../service_key.json'

env_file_path = '../../.env'
load_dotenv(env_file_path)

def get_required_env_var(var_name: str) -> str:
    """Gets a required environment variable or raises an error."""
    value = os.getenv(var_name)
    if value is None:
        raise ValueError(f'Required Environment Variable {var_name} is not set.')
    return value

STRAVA_CLIENT_ID = int(get_required_env_var('strava_client_id'))
STRAVA_CLIENT_SECRET = get_required_env_var('strava_client_secret')
REFRESH_TOKEN = get_required_env_var('refresh_token')
GCS_BUCKET_NAME = get_required_env_var('gcs_bucket_name')
GCS_BUCKET_NAME_II = get_required_env_var('gcs_bucket_name_ii')

state_data = read_json_from_gcs(GCS_BUCKET_NAME_II, "state.json")

if state_data:
    EXPIRES_AT = state_data['expires_at']
    EXPIRES_AT_DT = datetime.fromtimestamp(int(EXPIRES_AT))
    LAST_ACTIVITY_DT = state_data['last_activity_dt']

else:
    print('the state.json load returned None')
    sys.exit(0)


try:
    if datetime.now() > EXPIRES_AT_DT:
        ACCESS_TOKEN, state_data = refresh_access_token(STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, REFRESH_TOKEN, state_data)
    else:
        ACCESS_TOKEN = state_data['access_token']
except Exception as e:
    print('Could not obtain a valid access token. Exiting.')
    sys.exit(1)

try:
    client = Client(access_token = ACCESS_TOKEN)
    activities = client.get_activities(after = LAST_ACTIVITY_DT)
except Exception as e:
    print(f'error {e} while trying to get strava activities')
    sys.exit(1)

all_activities = get_activity_data(activities)
stravadata_df = pd.DataFrame(all_activities)

if stravadata_df.empty:
    print('No new activities found. Exiting')
    sys.exit(0)

write_to_gcs(stravadata_df, GCS_BUCKET_NAME, GCS_BUCKET_NAME_II, state_data)