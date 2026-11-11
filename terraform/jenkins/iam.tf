resource "google_service_account" "jenkins" {
  account_id   = "jenkins-ci"
  display_name = "Jenkins CI VM"
}

resource "google_project_iam_member" "jenkins" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.jenkins.email}"
}

resource "google_artifact_registry_repository_iam_member" "jenkins_push" {
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.jenkins.email}"
}