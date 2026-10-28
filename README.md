# Dekin Infrastructure

Repo d’infrastructure pour Dekin : déploiement sur **Cloudflare via [Alchemy](https://alchemy.run) v2**.

## Architecture

```text
frontend (StaticSite, Workers Assets)  ──HTTPS/WSS──▶  dekin-api-<stage> (Worker)
                                                         │  routes /, /health-check, /ws*, /pose/*
                                                         ▼
                                                   VideoParserContainer (Durable Object)
                                                         │  1 instance, standard-1 (4 GiB)
                                                         ▼
                                                   video-parser (NestJS + Python/MediaPipe)
                                                     ├─▶ Neon Postgres (DATABASE_URL)
                                                     └─▶ R2 bucket dekin-videos-<stage> (API S3)
```

Trois stacks Alchemy, une par repo, qui partagent le même state store Cloudflare et le même nom de stage (`prod`, `staging`) :

| Stack | Repo | Contenu |
|---|---|---|
| `dekin-infrastructure` | `infrastructure/alchemy.run.ts` | bucket R2 + token S3, projet Neon (prod) / branche Neon (autres stages), noms/URLs publics, secrets CI des repos applicatifs (prod uniquement) |
| `dekin-video-parser` | `video-parser/deploy/alchemy.run.ts` | Worker `dekin-api-<stage>` + Container construit depuis `video-parser/Dockerfile` |
| `dekin-frontend` | `frontend/deploy/alchemy.run.ts` | site statique `bunx expo export -p web`, URLs du parser injectées au build |

Chaque stack suit la [convention Alchemy](https://alchemy.run/project-structure/file-layout) : `alchemy.run.ts` ne fait que composer, et `src/` contient un fichier par ressource ou groupe de ressources au même cycle de vie (ex. `src/Videos.ts` = bucket R2 + son token S3, `src/Db.ts` = Neon).

Les stacks applicatives lisent les outputs de la stack partagée (et le frontend ceux du parser) au moment du plan. Ordre de déploiement : **infrastructure → video-parser → frontend** ; destruction dans l’ordre inverse.

Données de prod : le bucket R2 et le projet Neon de `prod` sont en `RemovalPolicy.retain` ; un `destroy` de `staging` ne touche que sa branche Neon et son bucket.

Proposition de stockage des frames de pose (R2 + D1, sans table `Frame`) : [docs/pose-data-flow.md](./docs/pose-data-flow.md).

## Mise en place (une seule fois, par un admin)

1. **Cloudflare** : passer le compte sur Workers Paid (requis pour Containers) et noter le sous-domaine `workers.dev` du compte (Workers & Pages → sous-domaine) → `WORKERS_SUBDOMAIN`.
2. **Token Cloudflare admin** (pour cette stack) avec au minimum : *Account API Tokens Write*, *Workers R2 Storage Write*, *Workers Scripts Write*, *Secrets Store Write*, *Account Settings Read*. La stack mint elle-même des tokens plus restreints (S3 du bucket, CI des repos applicatifs).
3. **Neon** : créer une clé API → `NEON_API_KEY`.
4. **GitHub** : PAT fine-grained avec *Secrets: read & write* sur `Dekin-Ydays/video-parser` et `Dekin-Ydays/frontend` → `GITHUB_ACCESS_TOKEN` en local, `ALCHEMY_GITHUB_TOKEN` en secret CI.
5. **State store** : `bun install && bunx alchemy state bootstrap --backend cloudflare`.
6. Dans ce repo GitHub : secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `NEON_API_KEY`, `ALCHEMY_GITHUB_TOKEN` et variable `WORKERS_SUBDOMAIN`.

Le déploiement `prod` de cette stack écrit `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` dans les repos `video-parser` et `frontend` ; leurs workflows `deploy.yml` déploient ensuite `prod` à chaque push sur `main` (et `staging` via *Run workflow*).

## Commandes

```sh
bun install
bun run typecheck
bunx alchemy plan --stage staging
bunx alchemy deploy --stage staging
```

En local, les identifiants viennent de l’environnement (ou d’un `.env`, jamais commité) : `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `NEON_API_KEY`, `GITHUB_ACCESS_TOKEN`, `WORKERS_SUBDOMAIN`. Le workflow `Deploy` de ce repo est manuel (*Run workflow*).

## Bascule depuis DigitalOcean / Vercel

Le code Terraform a été supprimé ; il reste dans l’historique Git (commit `7bcf153`). Les ressources déjà créées tournent toujours tant qu’elles ne sont pas détruites.

1. Déployer `prod` dans l’ordre ci-dessus et vérifier `https://dekin-api-prod.<WORKERS_SUBDOMAIN>.workers.dev/pose/health` puis le site.
2. Migrer les données existantes si elles doivent être conservées (SQLite `/opt/dekin-hosted-data/parser/prod.db` → Neon, objets MinIO → R2) : rien n’est automatisé.
3. Détruire l’ancienne infra : run *destroy* depuis le workspace HCP `dekin/dekin-hosted` (ou `git checkout 7bcf153 -- terraform && terraform destroy`), ou supprimer à la main dans DigitalOcean le Droplet `dekin-hosted-app`, le volume `dekin-hosted-data` et le firewall `dekin-hosted-firewall`. Supprimer ensuite le workspace HCP.
4. Supprimer les projets Vercel et EAS Hosting du frontend, et retirer du repo `video-parser` les secrets `DEPLOY_SSH_PRIVATE_KEY` / `DIGITALOCEAN_TOKEN` et variables `DEPLOY_*` / `DO_FIREWALL_NAME`.

## Limites connues

- Les requêtes passent par un Worker : corps limité à ~100 MB (plan Free/Pro). Le parser refuse les uploads > 95 MiB (413). Pour des vidéos plus lourdes, passer à un upload direct vers R2 par URL présignée.
- Un seul container : les sessions WebSocket et les extractions en cours vivent dans cette instance. Il s’endort après 30 min sans requête ni WebSocket ouvert ; le premier appel suivant subit un cold start (migrations Prisma + chargement MediaPipe).
- Alchemy v2 est en bêta : versions épinglées exactement (`2.0.0-beta.84`).
