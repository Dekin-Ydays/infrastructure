# On-Prem Deployment Option

> Alternative de déploiement. Le chemin principal actuel est DigitalOcean + HCP Terraform : voir [`../HANDOVER_FR.md`](../HANDOVER_FR.md) et [`../terraform/README.md`](../terraform/README.md).

This folder contains the Ansible-based deployment path for running Dekin on managed VMs or an on-prem environment.

The hosted DigitalOcean + Vercel path is the default deployment and lives in `../terraform`.

## Run

```sh
make start
```

Health check:

```sh
make healthcheck
```

The Ansible config uses `on-prem/ansible/inventory/hosts.yml` and roles under `on-prem/ansible/roles`.
