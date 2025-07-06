import json
from stravalib.client import Client
import gcsfs

def refresh_access_token(STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, REFRESH_TOKEN, state_data):
    """Refresh the access token"""
    try:
        client = Client()
        refresh_response = client.refresh_access_token(
            client_id = STRAVA_CLIENT_ID,  
            client_secret = STRAVA_CLIENT_SECRET, 
            refresh_token = REFRESH_TOKEN, 
            )
        state_data['access_token'] = refresh_response['access_token']
        state_data['expires_at'] = str(refresh_response['expires_at'])
        REFRESH_ACCESS_TOKEN = refresh_response['access_token']
        print('Token refreshed successfully!')
        return REFRESH_ACCESS_TOKEN, state_data
        
    except Exception as e:
        raise ConnectionError(f'Error refreshing token: {e}') from e