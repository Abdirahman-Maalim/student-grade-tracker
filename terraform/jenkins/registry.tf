resource "google_artifact_registry_repository" "images" {
  repository_id = "grade-tracker"
  location      = var.region
  format        = "DOCKER"
  description   = "Images built by Jenkins CI"

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}