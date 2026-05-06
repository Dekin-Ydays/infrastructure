output "public_ip" {
  description = "Droplet public IPv4 address."
  value       = digitalocean_droplet.app.ipv4_address
}

output "backend_host" {
  description = "Hostname Caddy serves."
  value       = local.backend_host
}

output "backend_url" {
  description = "Public backend HTTPS URL."
  value       = local.backend_url
}

output "ssh_command" {
  description = "Admin SSH command."
  value       = "ssh root@${digitalocean_droplet.app.ipv4_address}"
}

output "deploy" {
  description = "GitHub Actions deploy connection values."
  value = {
    DEPLOY_HOST = digitalocean_droplet.app.ipv4_address
    DEPLOY_USER = "deploy"
  }
}

output "vercel_environment" {
  description = "Frontend environment variables to set in Vercel."
  value = {
    EXPO_PUBLIC_VIDEO_PARSER_BASE_URL = local.backend_url
    EXPO_PUBLIC_VIDEO_PARSER_WS_URL   = "wss://${local.backend_host}/ws"
  }
}

output "health_checks" {
  description = "Public health check URLs."
  value = {
    spring = "${local.backend_url}/actuator/health"
    parser = "${local.backend_url}/pose/health"
  }
}
