variable "do_token" {
  description = "DigitalOcean API token. Set this as a sensitive Terraform variable in HCP Terraform."
  type        = string
  default     = null
  sensitive   = true
}

variable "project" {
  description = "Project/resource name prefix."
  type        = string
  default     = "dekin-hosted"
}

variable "digitalocean_project_name" {
  description = "Existing DigitalOcean project that receives the hosted resources."
  type        = string
  default     = "dekin"
}

variable "region" {
  description = "DigitalOcean region slug."
  type        = string
  default     = "fra1"
}

variable "droplet_size" {
  description = "DigitalOcean Droplet size slug. The parser image includes Python/MediaPipe, so 4 GB RAM is the baseline."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "droplet_image" {
  description = "Droplet base image."
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "digitalocean_ssh_key_name" {
  description = "Existing DigitalOcean account SSH key used for admin/root access to the Droplet."
  type        = string
  default     = "dekin"
}

variable "deploy_ssh_public_key" {
  description = "Public key for the CI deploy user. Put the private half in GitHub secret DEPLOY_SSH_PRIVATE_KEY."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDR ranges allowed to SSH into the Droplet."
  type        = list(string)

  validation {
    condition = (
      length(var.ssh_allowed_cidrs) > 0 &&
      alltrue([for cidr in var.ssh_allowed_cidrs : can(cidrhost(cidr, 0))])
    )
    error_message = "ssh_allowed_cidrs must contain at least one valid CIDR block."
  }
}

variable "backend_hostname" {
  description = "Optional hostname already pointed at the Droplet. Empty uses <droplet-ip>.sslip.io."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Optional email for Let's Encrypt registration."
  type        = string
  default     = ""
}

variable "data_volume_size_gb" {
  description = "Persistent volume size for MinIO and parser SQLite data."
  type        = number
  default     = 10

  validation {
    condition     = var.data_volume_size_gb >= 1 && var.data_volume_size_gb <= 16384
    error_message = "data_volume_size_gb must be between 1 and 16384."
  }
}

variable "parser_image" {
  description = "Initial video-parser image pulled on first boot. CI deploys replace this tag."
  type        = string
}

variable "frontend_origin_patterns" {
  description = "Exact browser origins allowed to call the parser."
  type        = list(string)
  default = [
    "http://localhost:3000",
    "http://localhost:8081",
    "http://localhost:8082",
    "http://localhost:19006",
  ]
}

variable "minio_access_key" {
  description = "MinIO root/access key."
  type        = string
  default     = "minioadmin"
  sensitive   = true
}

variable "minio_secret_key" {
  description = "Optional MinIO root/secret key. If null, Terraform generates one."
  type        = string
  default     = null
  sensitive   = true
}

variable "minio_bucket" {
  description = "MinIO bucket used by the parser."
  type        = string
  default     = "videos"
}

variable "swap_size_mb" {
  description = "Swap size to create on the Droplet."
  type        = number
  default     = 2048
}
