terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "6.40.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_project_region
  zone    = var.gcp_project_zone
}

resource "google_storage_bucket" "static" {
  name          = var.gcs_bucket_name
  location      = var.gcp_project_region
  storage_class = "STANDARD"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket" "static_ii" {
  name          = "${var.gcs_bucket_name_II}-${var.gcp_project_id}"
  location      = var.gcp_project_region
  storage_class = "STANDARD"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "state" {
  name   = var.state_file_gcs_name
  source = var.state_file_local_path
  bucket = google_storage_bucket.static_ii.name
}

resource "google_storage_bucket_iam_member" "static_iam" {
  bucket = google_storage_bucket.static.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_email}"
}

resource "google_storage_bucket_iam_member" "static_ii_iam" {
  bucket = google_storage_bucket.static_ii.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.service_account_email}"
}

resource "google_project_iam_member" "bq_job_user" {
  project = var.gcp_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${var.service_account_email}"
}

resource "google_bigquery_dataset_iam_member" "bq_data_editor" {
  project    = var.gcp_project_id
  dataset_id = google_bigquery_dataset.default.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${var.service_account_email}"
}

resource "google_bigquery_dataset" "default" {
  dataset_id                  = var.bigquery_dataset_id
  friendly_name               = var.bigquery_dataset_id
  location                    = var.gcp_project_region
  delete_contents_on_destroy  = false
}

resource "google_bigquery_table" "default" {
  dataset_id = google_bigquery_dataset.default.dataset_id
  table_id   = var.table_id
  project    = var.gcp_project_id
  deletion_protection = false
  schema = <<EOF
[
  {
    "name": "id",
    "type": "INTEGER",
    "mode": "REQUIRED",
    "description": "The unique identifier for the activity"
  },
  {
    "name": "distance",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "time",
    "type": "INTEGER",
    "mode": "NULLABLE",
    "description": "Elapsed time in seconds"
  },
  {
    "name": "elevation_high",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "elevation_low",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "elevation_gain",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
   {
    "name": "average_speed",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
   {
    "name": "maximum_speed",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
   {
    "name": "start_latitude",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
   {
    "name": "start_longitude",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
   {
    "name": "end_latitude",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
   {
    "name": "end_longitude",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
   {
    "name": "average_cadence",
    "type": "FLOAT",
    "mode": "NULLABLE"
  },
  {
    "name": "start_datetime",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "description": "The start time of the activity"
  },
  {
    "name": "end_datetime",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "description": "The end time of the activity"
  }
]
EOF
}

resource "google_secret_manager_secret" "client_secret_container" {
  project   = var.gcp_project_id
  secret_id = "${var.secret_manager_id}-${var.gcp_project_id}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "client_secret_value" {
  secret = google_secret_manager_secret.client_secret_container.id

  secret_data = jsonencode({
    strava_client_id     = var.client_id
    strava_client_secret = var.client_secret
    refresh_token        = var.refresh_token
    gcs_bucket_name      = var.gcs_bucket_name
    gcs_bucket_name_II   = var.gcs_bucket_name_II
    table_id             = var.table_id
  })
}

resource "google_secret_manager_secret_iam_member" "secret_accessor" {
  secret_id = google_secret_manager_secret.client_secret_container.id
  member    = "serviceAccount:${var.service_account_email}"
  role      = "roles/secretmanager.secretAccessor"
}