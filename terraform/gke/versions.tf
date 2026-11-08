terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  backend "gcs" {
    bucket = "project-aa2f0371-cdbf-4df1-8c0-tfstate"
    prefix = "gke"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
