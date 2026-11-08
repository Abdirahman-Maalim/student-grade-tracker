output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "get_credentials" {
  description = "Run this to point kubectl at the cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.gke.name} --zone ${var.zone} --project ${var.project_id}"
}