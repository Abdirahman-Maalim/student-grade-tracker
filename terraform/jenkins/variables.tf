variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "admin_cidrs" {
  description = "IP ranges allowed to reach SSH and the Jenkins UI (your home IP as /32)"
  type        = list(string)
}

variable "ssh_user" {
  description = "Linux user created on the VM for Ansible"
  type        = string
  default     = "ansible"
}

variable "ssh_public_key" {
  description = "Public SSH key for ssh_user"
  type        = string
}

variable "github_hook_cidrs" {
  description = "GitHub webhook source ranges (from https://api.github.com/meta, key 'hooks')"
  type        = list(string)
  default     = ["192.30.252.0/22", "185.199.108.0/22", "140.82.112.0/20", "143.55.64.0/20"]
}