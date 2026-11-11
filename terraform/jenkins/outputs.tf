output "jenkins_ip" {
  value = google_compute_address.jenkins.address
}

output "jenkins_url" {
  value = "http://${google_compute_address.jenkins.address}:8080"
}

output "registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}