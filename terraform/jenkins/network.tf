resource "google_compute_network" "vpc" {
  name                    = "jenkins-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "jenkins-subnet"
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.50.0.0/24"
}

resource "google_compute_address" "jenkins" {
  name   = "jenkins-ip"
  region = var.region
}

resource "google_compute_firewall" "admin" {
  name          = "jenkins-allow-admin"
  network       = google_compute_network.vpc.id
  source_ranges = var.admin_cidrs
  target_tags   = ["jenkins"]

  allow {
    protocol = "tcp"
    ports    = ["22", "8080"]
  }
}

resource "google_compute_firewall" "github_webhook" {
  name          = "jenkins-allow-github-webhook"
  network       = google_compute_network.vpc.id
  source_ranges = var.github_hook_cidrs
  target_tags   = ["jenkins"]

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}