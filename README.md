# Dekin Infrastructure

Repo d’infrastructure pour Dekin.

## Nouveau mainteneur / passation

👉 Commencer par les notes de passation : [HANDOVER_FR.md](./HANDOVER_FR.md)

Le chemin de déploiement principal est : [terraform/README.md](./terraform/README.md)

Résumé :

1. configurer les variables du workspace HCP Terraform `dekin/dekin-hosted`,
2. appliquer Terraform pour provisionner DigitalOcean,
3. copier les outputs Terraform dans Vercel,
4. configurer les secrets/variables GitHub Actions du repo `video-parser`,
5. vérifier `https://<backend-host>/pose/health`.

## Dossiers

- `terraform/` — déploiement principal DigitalOcean + Caddy + MinIO + video-parser.
- `on-prem/` — alternative Ansible/on-prem.

## Notes

Les anciens documents `ARCHITECTURE.md`, `DIAGRAM.md` et `AWS_COST_ANALYSIS.md` peuvent contenir du contexte historique AWS. Pour la reprise actuelle, suivre en priorité `HANDOVER_FR.md` et `terraform/README.md`.
