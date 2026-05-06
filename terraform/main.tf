locals {
  app_dir                  = "/opt/${var.project}"
  data_dir                 = "/opt/${var.project}-data"
  normalized_backend_host  = trimspace(var.backend_hostname)
  backend_host             = local.normalized_backend_host != "" ? local.normalized_backend_host : "${digitalocean_droplet.app.ipv4_address}.sslip.io"
  backend_url              = "https://${local.backend_host}"
  db_password              = coalesce(var.db_password, random_password.db.result)
  minio_secret_key         = coalesce(var.minio_secret_key, random_password.minio_secret.result)
  frontend_origin_patterns = join(",", var.frontend_origin_patterns)
  data_volume_name         = "${var.project}-data"

  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    acme_email               = var.acme_email
    app_dir                  = local.app_dir
    backend_hostname         = local.normalized_backend_host
    data_dir                 = local.data_dir
    data_volume_name         = local.data_volume_name
    db_name                  = var.db_name
    db_password              = local.db_password
    db_user                  = var.db_user
    deploy_ssh_public_key    = var.deploy_ssh_public_key
    frontend_origin_patterns = local.frontend_origin_patterns
    minio_access_key         = var.minio_access_key
    minio_bucket             = var.minio_bucket
    minio_secret_key         = local.minio_secret_key
    parser_image             = var.parser_image
    project                  = var.project
    server_image             = var.server_image
    swap_size_mb             = var.swap_size_mb
  })

  tags = [
    var.project,
    "terraform",
    "hosted",
  ]
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "minio_secret" {
  length  = 32
  special = false
}

resource "digitalocean_project" "this" {
  name        = var.project
  description = "Hosted Dekin backend runtime."
  purpose     = "Web Application"
  environment = "Production"
  resources   = [digitalocean_droplet.app.urn]
}

resource "digitalocean_ssh_key" "admin" {
  name       = "${var.project}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
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
  ssh_keys   = [digitalocean_ssh_key.admin.fingerprint]
  monitoring = true
  tags       = local.tags
  user_data  = local.cloud_init
  volume_ids = [digitalocean_volume.data.id]
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
