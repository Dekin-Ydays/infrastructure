locals {
  app_dir                  = "/opt/${var.project}"
  data_dir                 = "/opt/${var.project}-data"
  normalized_backend_host  = trimspace(var.backend_hostname)
  backend_host             = local.normalized_backend_host != "" ? local.normalized_backend_host : "${digitalocean_droplet.app.ipv4_address}.sslip.io"
  backend_url              = "https://${local.backend_host}"
  minio_secret_key         = coalesce(var.minio_secret_key, random_password.minio_secret.result)
  frontend_origin_patterns = join(",", var.frontend_origin_patterns)
  data_volume_name         = "${var.project}-data"

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    acme_email               = var.acme_email
    app_dir                  = local.app_dir
    backend_hostname         = local.normalized_backend_host
    data_dir                 = local.data_dir
    data_volume_name         = local.data_volume_name
    deploy_ssh_public_key    = var.deploy_ssh_public_key
    frontend_origin_patterns = local.frontend_origin_patterns
    minio_access_key         = var.minio_access_key
    minio_bucket             = var.minio_bucket
    minio_secret_key         = local.minio_secret_key
    parser_image             = var.parser_image
    project                  = var.project
    swap_size_mb             = var.swap_size_mb
  })

  tags = [
    var.project,
    "terraform",
    "hosted",
  ]
}

resource "random_password" "minio_secret" {
  length  = 32
  special = false
}

data "digitalocean_project" "this" {
  name = var.digitalocean_project_name
}

data "digitalocean_ssh_key" "admin" {
  name = var.digitalocean_ssh_key_name
}

resource "digitalocean_project_resources" "this" {
  project   = data.digitalocean_project.this.id
  resources = [digitalocean_droplet.app.urn]
}

resource "digitalocean_volume" "data" {
  region                  = var.region
  name                    = local.data_volume_name
  size                    = var.data_volume_size_gb
  initial_filesystem_type = "ext4"
  description             = "Persistent data for ${var.project}"
}

resource "digitalocean_droplet" "app" {
  name       = "${var.project}-app"
  image      = var.droplet_image
  region     = var.region
  size       = var.droplet_size
  ssh_keys   = [data.digitalocean_ssh_key.admin.fingerprint]
  monitoring = true
  tags       = local.tags
  user_data  = local.cloud_init
  volume_ids = [digitalocean_volume.data.id]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "digitalocean_firewall" "app" {
  name        = "${var.project}-firewall"
  droplet_ids = [digitalocean_droplet.app.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_cidrs
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
