terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
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

data "google_project" "project" {}

resource "google_project_service" "required_apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com"
  ])
  
  service            = each.key
  disable_on_destroy = false
}


resource "google_service_account" "strava_pipeline" {
  account_id   = "strava-service-account"
  display_name = "Service Account for Strava Data Pipeline"
  project      = var.gcp_project_id
  
  depends_on = [google_project_service.required_apis]
}

resource "google_project_iam_member" "strava_pipeline_permissions" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/eventarc.eventReceiver",
    "roles/secretmanager.secretAccessor"
  ])
  
  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_project_iam_member" "cloud_build_permissions" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/cloudfunctions.developer",
    "roles/iam.serviceAccountUser",
    "roles/run.admin"
  ])
  
  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "compute_engine_permissions" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/logging.logWriter"
  ])
  
  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

resource "google_project_iam_member" "gcs_eventarc_permissions" {
  project = var.gcp_project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "service_agent_invokers" {
  for_each = toset([
    "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com",
    "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
  ])
  
  project = var.gcp_project_id
  role    = "roles/run.invoker"
  member  = each.key
}

resource "google_secret_manager_secret" "strava_credentials" {
  secret_id = "strava-client-secrets"
  project   = var.gcp_project_id
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "strava_credentials_version" {
  secret = google_secret_manager_secret.strava_credentials.id
  secret_data = jsonencode({
    client_id           = var.strava_client_id
    client_secret       = var.strava_client_secret
    refresh_token       = var.strava_refresh_token
    strava_verify_token = var.strava_verify_token
  })
}


resource "google_pubsub_topic" "strava_activity_events" {
  name    = var.pubsub_topic_id
  project = var.gcp_project_id
  
  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_topic_iam_member" "strava_pipeline_publisher" {
  project = var.gcp_project_id
  topic   = google_pubsub_topic.strava_activity_events.id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.strava_pipeline.email}"
}


# Function source code buckets
resource "google_storage_bucket" "webhook_function_source" {
  name                        = "${var.gcs_bucket_name}-${var.gcp_project_id}"
  location                    = var.gcp_project_region
  project                     = var.gcp_project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket" "extract_function_source" {
  name                        = "${var.gcs_bucket_name_iv}-${var.gcp_project_id}"
  location                    = var.gcp_project_region
  project                     = var.gcp_project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket" "load_function_source" {
  name                        = "${var.gcs_bucket_name_v}-${var.gcp_project_id}"
  location                    = var.gcp_project_region
  project                     = var.gcp_project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

# Application data buckets
resource "google_storage_bucket" "state_storage" {
  name                        = "${var.gcs_bucket_name_ii}-${var.gcp_project_id}"
  location                    = var.gcp_project_region
  project                     = var.gcp_project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket" "strava_activity_data" {
  name                        = "${var.gcs_bucket_name_iii}-${var.gcp_project_id}"
  location                    = var.gcp_project_region
  project                     = var.gcp_project_id
  uniform_bucket_level_access = true
  force_destroy               = true
}

resource "google_storage_bucket_iam_member" "strava_pipeline_storage_admin" {
  for_each = toset([
    google_storage_bucket.state_storage.name,
    google_storage_bucket.strava_activity_data.name
  ])
  
  bucket = each.key
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_storage_bucket_iam_member" "strava_pipeline_source_viewer" {
  for_each = toset([
    google_storage_bucket.webhook_function_source.name,
    google_storage_bucket.extract_function_source.name,
    google_storage_bucket.load_function_source.name
  ])
  
  bucket = each.key
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.strava_pipeline.email}"
}

resource "google_storage_bucket_iam_member" "cloud_build_source_viewer" {
  for_each = toset([
    google_storage_bucket.webhook_function_source.name,
    google_storage_bucket.extract_function_source.name,
    google_storage_bucket.load_function_source.name
  ])
  
  bucket = each.key
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}


# Webhook receiver function source
data "archive_file" "webhook_receiver_source" {
  type        = "zip"
  output_path = "${path.module}/webhook-receiver-source.zip"
  source_dir  = "../cloud_functions/pubsub"
  excludes = [
    "**/__pycache__",
    "**/*.pyc"
  ]
}

resource "google_storage_bucket_object" "webhook_receiver_source_zip" {
  name   = "source/webhook-receiver-${data.archive_file.webhook_receiver_source.output_base64sha256}.zip"
  bucket = google_storage_bucket.webhook_function_source.name
  source = data.archive_file.webhook_receiver_source.output_path
}

# Activity extractor function source
data "archive_file" "activity_extractor_source" {
  type        = "zip"
  output_path = "${path.module}/activity-extractor-source.zip"
  source_dir  = "../cloud_functions/extract"
  excludes = [
    "state.json",
    "**/__pycache__",
    "**/*.pyc"
  ]
}

resource "google_storage_bucket_object" "activity_extractor_source_zip" {
  name   = "source/activity-extractor-${data.archive_file.activity_extractor_source.output_base64sha256}.zip"
  bucket = google_storage_bucket.extract_function_source.name
  source = data.archive_file.activity_extractor_source.output_path
}

# Activity loader function source
data "archive_file" "activity_loader_source" {
  type        = "zip"
  output_path = "${path.module}/activity-loader-source.zip"
  source_dir  = "../cloud_functions/load"
  excludes = [
    "**/__pycache__",
    "**/*.pyc"
  ]
}

resource "google_storage_bucket_object" "activity_loader_source_zip" {
  name   = "source/activity-loader-${data.archive_file.activity_loader_source.output_base64sha256}.zip"
  bucket = google_storage_bucket.load_function_source.name
  source = data.archive_file.activity_loader_source.output_path
}

# State file for extractor function
resource "google_storage_bucket_object" "extractor_state_file" {
  name   = "state.json"
  bucket = google_storage_bucket.state_storage.name
  source = "../cloud_functions/extract/state.json"
}


# Webhook receiver function
resource "google_cloudfunctions2_function" "webhook_receiver" {
  name     = "strava-webhook-receiver"
  location = var.gcp_project_region
  project  = var.gcp_project_id

  build_config {
    runtime     = "python312"
    entry_point = "main"
    source {
      storage_source {
        bucket = google_storage_bucket.webhook_function_source.name
        object = google_storage_bucket_object.webhook_receiver_source_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "512Mi"
    timeout_seconds    = 60
    ingress_settings   = "ALLOW_ALL"
    
    environment_variables = {
      GCP_PROJECT_ID    = var.gcp_project_id
      SECRET_MANAGER_ID = google_secret_manager_secret.strava_credentials.secret_id
      TOPIC_ID          = var.pubsub_topic_id
    }
    
    service_account_email = google_service_account.strava_pipeline.email
  }

  depends_on = [
    google_project_iam_member.cloud_build_permissions,
    google_project_iam_member.strava_pipeline_permissions,
    google_pubsub_topic_iam_member.strava_pipeline_publisher
  ]
}

# Activity extractor function
resource "google_cloudfunctions2_function" "activity_extractor" {
  name     = "strava-activity-extractor"
  location = var.gcp_project_region
  project  = var.gcp_project_id

  build_config {
    runtime     = "python312"
    entry_point = "main"
    source {
      storage_source {
        bucket = google_storage_bucket.extract_function_source.name
        object = google_storage_bucket_object.activity_extractor_source_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    timeout_seconds    = 540
    available_memory   = "512Mi"
    ingress_settings   = "ALLOW_INTERNAL_ONLY"
    
    environment_variables = {
      GCP_PROJECT_ID         = var.gcp_project_id
      SECRET_MANAGER_ID      = google_secret_manager_secret.strava_credentials.secret_id
      BIGQUERY_DATASET_ID    = var.bigquery_dataset_id
      BIGQUERY_TABLE_ID      = var.bigquery_table_id
      STATE_AUTH_BUCKET      = google_storage_bucket.state_storage.name
      STRAVA_ACTIVITY_BUCKET = google_storage_bucket.strava_activity_data.name
    }
    
    service_account_email = google_service_account.strava_pipeline.email
  }

  event_trigger {
    trigger_region        = var.gcp_project_region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.strava_activity_events.id
    retry_policy          = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = google_service_account.strava_pipeline.email
  }

  depends_on = [
    google_project_iam_member.cloud_build_permissions,
    google_project_iam_member.strava_pipeline_permissions,
    google_storage_bucket_iam_member.strava_pipeline_storage_admin
  ]
}

# Activity loader function
resource "google_cloudfunctions2_function" "activity_loader" {
  name     = "strava-activity-loader"
  location = var.gcp_project_region
  project  = var.gcp_project_id

  build_config {
    runtime     = "python312"
    entry_point = "main"
    source {
      storage_source {
        bucket = google_storage_bucket.load_function_source.name
        object = google_storage_bucket_object.activity_loader_source_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    timeout_seconds    = 540
    available_memory   = "512Mi"
    ingress_settings   = "ALLOW_INTERNAL_ONLY"
    
    environment_variables = {
      GCP_PROJECT_ID      = var.gcp_project_id
      BIGQUERY_DATASET_ID = var.bigquery_dataset_id
      BIGQUERY_TABLE_ID   = var.bigquery_table_id
    }
    
    service_account_email = google_service_account.strava_pipeline.email
  }

  event_trigger {
    trigger_region        = var.gcp_project_region
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.strava_pipeline.email
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.strava_activity_data.name
    }
  }

  depends_on = [
    google_project_iam_member.cloud_build_permissions,
    google_project_iam_member.strava_pipeline_permissions
  ]
}

resource "google_cloud_run_service_iam_member" "webhook_public_invoker" {
  project  = google_cloudfunctions2_function.webhook_receiver.project
  location = google_cloudfunctions2_function.webhook_receiver.location
  service  = google_cloudfunctions2_function.webhook_receiver.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "internal_function_invokers" {
  for_each = toset([
    "strava-activity-extractor",
    "strava-activity-loader"
  ])
  
  project  = var.gcp_project_id
  location = var.gcp_project_region
  service  = each.key
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.strava_pipeline.email}"
  
  depends_on = [
    google_cloudfunctions2_function.activity_extractor,
    google_cloudfunctions2_function.activity_loader
  ]
}


resource "google_bigquery_dataset" "strava_activities" {
  dataset_id                 = var.bigquery_dataset_id
  friendly_name              = "Strava Activities Dataset"
  location                   = var.gcp_project_region
  project                    = var.gcp_project_id
  delete_contents_on_destroy = false
  
  depends_on = [google_project_service.required_apis]
}

resource "google_bigquery_table" "activity_data" {
  dataset_id          = google_bigquery_dataset.strava_activities.dataset_id
  table_id            = var.bigquery_table_id
  project             = var.gcp_project_id
  deletion_protection = false
  
  schema = jsonencode([
    {
      name        = "id"
      type        = "INTEGER"
      mode        = "REQUIRED"
      description = "The unique identifier for the activity"
    },
    {
      name = "distance"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name        = "time"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Elapsed time in seconds"
    },
    {
      name = "elevation_high"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "elevation_low"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "elevation_gain"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "average_speed"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "maximum_speed"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "start_latitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "start_longitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "end_latitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "end_longitude"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "average_cadence"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name        = "start_datetime"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "The start time of the activity"
    },
    {
      name        = "end_datetime"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "The end time of the activity"
    }
  ])
}