from google.cloud import secretmanager
import os

os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = '../service_key.json'

def access_secret_version(project_id, secret_id, version_id = "latest"):
    """
    Access the payload for the given secret version.
    """
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{project_id}/secrets/{secret_id}/versions/{version_id}"
        response = client.access_secret_version(request={"name": name})
        payload = response.payload.data.decode("UTF-8")
        return payload
    except Exception as e:
        print(f'error {e} has occurred')
        raise