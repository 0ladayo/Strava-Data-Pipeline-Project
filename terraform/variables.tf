variable "gcp_project_id"{
    type = string
    description = "The GCP Project ID"
}

variable "gcp_project_region"{
    type = string
    description = "The GCP Project Region"
}

variable "gcp_project_zone"{
    type = string
    description = "The GCP Project Zone"
}

variable "strava_client_id" {
  description = "The Strava client ID."
  type        = string
  sensitive   = true
}

variable "strava_client_secret" {
  description = "The Strava client secret."
  type        = string
  sensitive   = true
}

variable "strava_refresh_token" {
  description = "The Strava refresh token."
  type        = string
  sensitive   = true
}

variable "bigquery_dataset_id" {
  type        = string
  description = "The BigQuery Dataset ID."
}

variable "bigquery_table_id" {
  type        = string
  description = "The BigQuery Table ID."
}

variable "strava_verify_token" {
  type        = string
  description = "The Strava verify token."
}

variable "gcs_bucket_name" {
  description = "The First Bucket where the First Cloud Function Source is stored"
  type        = string
}

variable "pubsub_topic_id" {
  description = "The Pub/Sub Topic ID."
  type        = string
}

variable "gcs_bucket_name_ii" {
  description = "The Second Bucket where the State.json is stored"
  type        = string
}

variable "gcs_bucket_name_iii" {
  description = "The Third where Strava Activity Parquet files are stored"
  type        = string
}

variable "gcs_bucket_name_iv" {
  description = "The Third Bucket where the Second Cloud Function Source is stored"
  type        = string
}