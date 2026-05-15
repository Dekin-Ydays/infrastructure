terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "dekin"

    workspaces {
      name = "dekin-hosted"
    }
  }

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}
