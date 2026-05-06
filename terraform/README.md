# DigitalOcean Hosted Backend + Vercel Frontend

Production-shaped Dekin hosting without DNS automation:

- Vercel serves the Expo web frontend.
- DigitalOcean runs Spring Boot, the NestJS video parser, PostgreSQL, MinIO, and Caddy.
- CI builds Docker images and the Droplet pulls them from GHCR.
- A DigitalOcean volume stores Postgres, MinIO, and parser SQLite data.

This intentionally does not create Cloudflare records or Vercel resources.

## First Apply

```sh
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

- set `deploy_ssh_public_key`
- set `ssh_allowed_cidrs`
- set `server_image` and `parser_image`
- leave `backend_hostname = ""` for `https://<droplet-ip>.sslip.io`

Then apply:

```sh
export DIGITALOCEAN_TOKEN="dop_v1_..."
terraform init
terraform apply
```

Terraform prints `vercel_environment`. Add those values to the Vercel frontend project:

```sh
EXPO_PUBLIC_VIDEO_PARSER_BASE_URL=https://<backend-host>
EXPO_PUBLIC_VIDEO_PARSER_WS_URL=wss://<backend-host>/ws
```

The frontend repo includes `vercel.json`; Vercel should build with `npx expo export -p web` and publish `dist`.

## GitHub Actions Deploy

Set these in the `server` and `video-parser` GitHub repositories:

- secret `DEPLOY_SSH_PRIVATE_KEY`: private half of `deploy_ssh_public_key`
- variable `DEPLOY_HOST`: Terraform output `deploy.DEPLOY_HOST`
- variable `DEPLOY_USER`: `deploy`

On `main`, each app repo builds and pushes a GHCR image. If the deploy secret/vars are present, the workflow SSHes to the Droplet and runs:

```sh
sudo /usr/local/bin/dekin-deploy server <image>
sudo /usr/local/bin/dekin-deploy parser <image>
```

The deploy helper authenticates to GHCR per deploy using the workflow's short-lived `GITHUB_TOKEN`.

## Operations

SSH:

```sh
terraform output -raw public_ip | xargs -I{} ssh root@{}
```

Logs:

```sh
ssh root@<droplet-ip>
journalctl -u cloud-init -f
cd /opt/dekin-hosted
docker compose --env-file .env --env-file deploy.env -f compose.yml ps
docker compose --env-file .env --env-file deploy.env -f compose.yml logs -f
```

Health checks:

```sh
curl https://<backend-host>/actuator/health
curl https://<backend-host>/pose/health
```

## Notes

- The default `frontend_origin_patterns` includes `https://*.vercel.app` for generated Vercel domains.
- Terraform state contains generated database and MinIO secrets. Keep state private.
- The persistent volume protects data across Droplet replacement, but not against `terraform destroy` or application-level data corruption.
- Custom domains are manual: create DNS outside this repo, set `backend_hostname`, and apply again.
