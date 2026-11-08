variable "project_id" {
  description = "Google Cloud project ID to deploy into"
  type        = string
}

variable "region" {
  description = "Region for the network"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for the GKE cluster"
  type        = string
  default     = "us-central1-a"
}

variable "name" {
  description = "Prefix for every resource name"
  type        = string
  default     = "grade-tracker"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "Worker node machine type"
  type        = string
  default     = "e2-medium"
}
