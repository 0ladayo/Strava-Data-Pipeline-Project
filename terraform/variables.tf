variable "gcp_project_id"{
    type = string
    description = "The GCP Project ID where resources will be deployed"
}

variable "gcp_project_region"{
    type = string
    description = "The region where the GCP resources will be deployed"
}

variable "gcp_project_zone"{
    type = string
    description = "The Zone in the region where the GCP resources will be deployed"
}

variable "gcs_bucket_name"{
    type = string
    description = "Name of the Google Cloud Storage Bucket"
}

variable "gcs_bucket_name_II"{
    type = string
    description = "Name of the Second Google Cloud Storage Bucket"
}

variable "bigquery_dataset_id"{
    type = string
    description = "Name of the BigQuery dataset where tables will be stored"
}

variable "table_id"{
    type = string
    description = "The ID of the BigQuery table where data ingested are stored"
}

variable "state_file_local_path" {
  description = "The local path to the state file."
  type        = string
  default     = "../data ingestion/extract/state.json"
}

variable "state_file_gcs_name" {
  description = "The name of the state file in GCS."
  type        = string
  default     = "state.json"
}

variable "service_account_email" {
  description = "The email of the service account to grant permissions to."
  type        = string
}