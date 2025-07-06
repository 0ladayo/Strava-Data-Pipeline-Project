terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "6.40.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "2.7.1"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_project_region
  zone    = var.gcp_project_zone
}

resource "google_project_service" "gcp_services" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "secretmanager.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "eventarc.googleapis.com"
  ])
  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "strava_service_account" {
  account_id   = "strava-service-account"
  display_name = "Service Account for Strava Data Pipeline"
  project      = var.gcp_project_id
}

resource "google_secret_manager_secret" "client_secret_container" {
  depends_on = [
    google_project_service.gcp_services
  ]
  secret_id = "secret_manager_id-${var.gcp_project_id}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "strava_secret_version" {
  secret = google_secret_manager_secret.client_secret_container.id
  
  secret_data = jsonencode({
    client_id            = var.strava_client_id
    client_secret        = var.strava_client_secret
    refresh_token        = var.strava_refresh_token
    strava_verify_token  = var.strava_verify_token
  })
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.strava_service_account.email}"
}

resource "google_pubsub_topic" "strava_activity_create" {
  depends_on = [
    google_project_service.gcp_services
  ]
  name    = var.pubsub_topic_id
}

resource "google_storage_bucket" "function_source_bucket" {
  name          = "${var.gcs_bucket_name}-${var.gcp_project_id}"
  location      = var.gcp_project_region
  storage_class = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy = true
}

data "archive_file" "strava_webhook_receiver_source" {
  type        = "zip"
  output_path = "${path.module}/strava-webhook-receiver-source.zip"
  source_dir  = "../cloud_functions/pubsub"
  excludes = [
    "**/__pycache__",
    "**/*.pyc"
  ]
}

resource "google_storage_bucket_object" "strava_webhook_receiver_source_zip" {
  name   = "strava-webhook-receiver-source-${data.archive_file.strava_webhook_receiver_source.output_base64sha256}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.strava_webhook_receiver_source.output_path
}

resource "google_cloudfunctions2_function" "strava_webhook_receiver" {
  name     = "strava-webhook-receiver"
  location = var.gcp_project_region

  build_config {
    runtime     = "python312"
    entry_point = "main"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.strava_webhook_receiver_source_zip.name
      }
    }
    service_account = google_service_account.strava_service_account.name
  }

  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "512Mi"
    timeout_seconds    = 60
    environment_variables = {
      GCP_PROJECT_ID    = var.gcp_project_id
      SECRET_MANAGER_ID = google_secret_manager_secret.client_secret_container.secret_id
      TOPIC_ID          = var.pubsub_topic_id
    }
    ingress_settings = "ALLOW_ALL"
    service_account_email = google_service_account.strava_service_account.email
  }
}

resource "google_project_iam_member" "storage_object_viewer" {
  project = var.gcp_project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.strava_service_account.email}"
}

resource "google_project_iam_member" "build_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.strava_service_account.email}"
}

resource "google_project_iam_member" "artifact_registry_writer" {
  project = var.gcp_project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.strava_service_account.email}"
}

resource "google_cloud_run_service_iam_member" "webhook_invoker" {
  service  = google_cloudfunctions2_function.strava_webhook_receiver.name
  location = google_cloudfunctions2_function.strava_webhook_receiver.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_pubsub_topic_iam_member" "strava_webhook_publisher" {
  topic  = google_pubsub_topic.strava_activity_create.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.strava_service_account.email}"
}

resource "google_storage_bucket" "statejson_bucket" {
  name          = "${var.gcs_bucket_name_ii}-${var.gcp_project_id}"
  location      = var.gcp_project_region
  storage_class = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy = true
}

resource "google_storage_bucket_iam_member" "statejson_bucket_iam_builder" {
  bucket = google_storage_bucket.statejson_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.strava_service_account.email}"
}


resource "google_storage_bucket_object" "state_json" {
  name   = "state.json"
  bucket = google_storage_bucket.statejson_bucket.name
  source = "../cloud_functions/extract/state.json"
}

resource "google_storage_bucket" "strava_activity_bucket" {
  name          = "${var.gcs_bucket_name_iii}-${var.gcp_project_id}"
  location      = var.gcp_project_region
  storage_class = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy = true
}

resource "google_storage_bucket_iam_member" "strava_activity_bucket_iam_builder" {
  bucket = google_storage_bucket.strava_activity_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.strava_service_account.email}"
}

resource "google_storage_bucket" "function_source_bucket_ii" {
  name          = "${var.gcs_bucket_name_iv}-${var.gcp_project_id}"
  location      = var.gcp_project_region
  storage_class = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy = true
}

data "archive_file" "strava_activity_extract_source" {
  type        = "zip"
  output_path = "${path.module}/strava-activity-extract-source.zip"
  source_dir  = "../cloud_functions/extract"
  excludes = [
    "state.json",
    "**/__pycache__",
    "**/*.pyc"
  ]
}

resource "google_storage_bucket_object" "strava_activity_extract_source_zip" {
  name   = "strava_activity_extract_source-${data.archive_file.strava_activity_extract_source.output_base64sha256}.zip"
  bucket = google_storage_bucket.function_source_bucket_ii.name
  source = data.archive_file.strava_activity_extract_source.output_path
}

resource "google_cloudfunctions2_function" "strava_activity_extract" {
  name     = "strava_activity_extract"
  location = var.gcp_project_region

  build_config {
    runtime     = "python312"
    entry_point = "main"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket_ii.name
        object = google_storage_bucket_object.strava_activity_extract_source_zip.name
      }
    }
    service_account = google_service_account.strava_service_account.name
  }

  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "512Mi"
    timeout_seconds    = 540
    environment_variables = {
      GCP_PROJECT_ID             = var.gcp_project_id
      SECRET_MANAGER_ID          = google_secret_manager_secret.client_secret_container.secret_id
      BIGQUERY_DATASET_ID        = var.bigquery_dataset_id
      BIGQUERY_TABLE_ID          = var.bigquery_table_id
      STATE_AUTH_BUCKET          = google_storage_bucket.statejson_bucket.name
      STRAVA_ACTIVITY_BUCKET     = google_storage_bucket.strava_activity_bucket.name
    }
    service_account_email = google_service_account.strava_service_account.email
    ingress_settings      = "ALLOW_ALL"
  }

  event_trigger {
    trigger_region = var.gcp_project_region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.strava_activity_create.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}