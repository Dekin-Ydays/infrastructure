# Notes de passation — Dekin

Ce document sert de point d’entrée pour reprendre le projet sans dépendre de l’ancien mainteneur.

> Note GitHub : ce fichier vit dans le repo `Dekin-Ydays/infrastructure` et sert de passation canonique pour l’ensemble des repos `frontend`, `video-parser`, `server` et `infrastructure`. Les chemins relatifs supposent que les quatre repos sont clonés côte à côte dans un même dossier de travail.

## 1. Vue d’ensemble

**Dekin** est une plateforme d’analyse de mouvements : l’utilisateur enregistre une pose via MediaPipe, envoie les landmarks au backend temps réel, puis compare deux vidéos/essais pour obtenir un score.

Architecture actuelle :

```text
frontend/ Expo React Native + Web
    -> video-parser/ NestJS + WebSocket + SQLite/Prisma + MinIO
    -> server/ API Spring Boot événements/auth (projet fil rouge)

infrastructure/
    -> terraform/ hébergement DigitalOcean + Caddy + MinIO + parser
    -> on-prem/ déploiement Ansible sur VMs gérées
```

Services principaux :

| Dossier | Rôle | Port local |
|---|---|---:|
| `frontend/` | App Expo/React Native/Web, capture caméra + MediaPipe | 8081/19006 selon Expo |
| `video-parser/` | Backend NestJS, WebSocket `/ws`, scoring de poses, stockage frames/objets | 3000 |
| `server/apifilrouge/` | API REST Spring Boot pour auth/événements (JWT/OAuth2/PostgreSQL) | 8090 |
| `infrastructure/terraform/` | Déploiement DigitalOcean du parser + MinIO + Caddy | 80/443 |

## 2. Prérequis développeur

- Node.js 20 LTS
- npm pour le frontend
- pnpm 10.x pour `video-parser`
- Java 21+ recommandé (le `pom.xml` cible Java 21 ; certains README mentionnent Java 23)
- Docker + Docker Compose pour lancer la stack locale complète
- PostgreSQL si vous lancez `server` hors Docker
- Terraform pour l’infra cloud
- Compte DigitalOcean + token API pour provisionner
- Compte Vercel pour le frontend web déployé
- Accès GitHub/GHCR pour l’image Docker du parser

## 3. Démarrage local rapide

Depuis la racine du repo :

```bash
docker compose up -d --build
```

Cela lance :

- PostgreSQL (`localhost:5432`, DB `jwt_security`, user `postgres`, password `admin`)
- MinIO (`localhost:9000`, console `localhost:9001`, user/pass `minioadmin`)
- `video-parser` (`localhost:3000`)
- `server` Spring (`localhost:8090`)

Le frontend se lance séparément :

```bash
cd frontend
npm install
npx expo start --clear
```

Pour le web, appuyer sur `w` dans Expo. Pour iOS avec caméra/native modules, ne pas utiliser Expo Go : faire une development build (`npx expo run:ios`, puis `npx expo start --dev-client`).

## 4. Setup par composant

### Frontend (`frontend/`)

Stack : Expo SDK 54, React 19, React Native 0.81, Expo Router, MediaPipe Tasks Vision, Vision Camera, Skia, NativeWind/Tailwind.

Commandes :

```bash
cd frontend
npm install
npx expo start --clear
npm run lint
npm run test
npm run build:web
```

Variables utiles :

| Variable | Usage | Source |
|---|---|---|
| `EXPO_PUBLIC_VIDEO_PARSER_BASE_URL` | URL HTTPS du parser, ex. `https://<host>` | sortie Terraform `vercel_environment` |
| `EXPO_PUBLIC_VIDEO_PARSER_WS_URL` | URL WebSocket, ex. `wss://<host>/ws` | sortie Terraform `vercel_environment` |
| `EXPO_PUBLIC_VIDEO_PARSER_HOST` / `PORT` / schemes | fallback local si base URL non fournie | local dev uniquement |

En prod Vercel, renseigner au minimum les deux variables `EXPO_PUBLIC_VIDEO_PARSER_*_URL`.

### Video parser (`video-parser/`)

Stack : NestJS 10, WebSocket (`ws`), Prisma 7 + SQLite, MinIO/S3, protobuf, Python/MediaPipe pour extraction.

Commandes :

```bash
cd video-parser
pnpm install
pnpm exec prisma generate
pnpm exec prisma migrate deploy
pnpm run start:dev
pnpm run test
pnpm run build
```

Variables d’environnement :

| Variable | Exemple local | À obtenir depuis |
|---|---|---|
| `PORT` | `3000` | config runtime |
| `DATABASE_URL` | `file:./dev.db` ou `file:/app/data/prod.db` | local/volume persistant DO |
| `MINIO_ENDPOINT` | `http://localhost:9000` local, `http://minio:9000` Docker | service MinIO |
| `MINIO_ACCESS_KEY` | `minioadmin` local | HCP Terraform variable `minio_access_key` ou défaut |
| `MINIO_SECRET_KEY` | dev uniquement `minioadmin` | HCP Terraform `minio_secret_key` ou généré par Terraform |
| `MINIO_BUCKET` | `videos` | HCP Terraform `minio_bucket` ou défaut |
| `MINIO_REGION` | `us-east-1` | constante pour MinIO |
| `CORS_ORIGINS` | origines séparées par virgules | origines Vercel exactes + localhost |
| `PYTHON_BIN`, `POSE_WORKER_SCRIPT`, `MEDIAPIPE_POSE_MODEL` | optionnel | seulement si chemins custom |

Endpoints importants :

- WebSocket : `ws://localhost:3000/ws`
- Santé : `GET /pose/health`
- Clients : `GET /pose/clients`
- Vidéos : `GET /pose/videos`, `GET /pose/video/:id`
- Comparaison : `POST /pose/compare` avec `{ referenceVideoId, comparisonVideoId, config? }`

### API Spring (`server/apifilrouge/`)

Stack : Spring Boot 3.4, Spring Security, JWT, OAuth2 Google/GitHub, Spring Data JPA, PostgreSQL, SpringDoc OpenAPI.

Commandes :

```bash
cd server/apifilrouge
./mvnw clean compile
./mvnw spring-boot:run
./mvnw test
./mvnw clean package -DskipTests
```

Variables prod :

| Variable | Usage | À obtenir depuis |
|---|---|---|
| `PORT` | port Spring, défaut 8090 | config déploiement |
| `DB_URL` | JDBC PostgreSQL | instance PostgreSQL |
| `DB_USERNAME` | user PostgreSQL | admin DB |
| `DB_PASSWORD` | mot de passe PostgreSQL | secret DB |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | OAuth Google | Google Cloud Console |
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | OAuth GitHub | GitHub OAuth App |
| `JWT_SECRET` | signature JWT si externalisé | générer un secret long |

Swagger local : `http://localhost:8090/swagger-ui/`.

## 5. Infra DigitalOcean + HCP Terraform

Le chemin de déploiement principal est `infrastructure/terraform/` :

- crée un Droplet Ubuntu DigitalOcean
- attache un volume persistant
- installe Docker/Caddy via cloud-init
- lance MinIO + `video-parser`
- expose le backend en HTTPS via Caddy (`sslip.io` par défaut si pas de domaine)
- ne crée pas Vercel ni DNS externe

### Variables à mettre dans HCP Terraform

Créer/configurer le workspace HCP Terraform suivant :

- Organization : `dekin`
- Workspace : `dekin-hosted`
- Working directory VCS : `infrastructure/terraform` si le repo est connecté en mode VCS

Renseigner les variables Terraform suivantes dans l’onglet **Variables** du workspace.

**Sensibles (cocher Sensitive) :**

| Nom HCP Terraform | Description | Où l’obtenir |
|---|---|---|
| `do_token` | Token API DigitalOcean | DigitalOcean → API → Tokens → Generate New Token, droits read/write |
| `minio_secret_key` | Secret MinIO prod | générer un mot de passe fort, ou laisser vide pour génération Terraform |
| `minio_access_key` | Access key MinIO | optionnel, peut rester `minioadmin` mais mieux de mettre une valeur prod |

**Non sensibles :**

| Nom | Exemple | Note |
|---|---|---|
| `project` | `dekin-hosted` | préfixe des ressources |
| `digitalocean_project_name` | `dekin` | projet DO existant, Terraform ne le crée pas |
| `region` | `fra1` | région DO |
| `droplet_size` | `s-2vcpu-4gb` | 4 Go RAM minimum conseillé (MediaPipe/Python) |
| `digitalocean_ssh_key_name` | `dekin` | clé SSH déjà présente dans le compte DO |
| `deploy_ssh_public_key` | `ssh-ed25519 ...` | moitié publique de la clé CI deploy |
| `ssh_allowed_cidrs` | `["x.x.x.x/32"]` | IPs autorisées en SSH ; éviter `0.0.0.0/0` |
| `backend_hostname` | `api.example.com` ou vide | vide = `https://<droplet-ip>.sslip.io` |
| `acme_email` | `team@example.com` | email Let’s Encrypt |
| `parser_image` | `ghcr.io/<org>/<image>:latest` | image initiale du parser |
| `frontend_origin_patterns` | liste d’origines exactes Vercel + localhost | utilisé par `CORS_ORIGINS` |
| `data_volume_size_gb` | `10` | volume MinIO/SQLite |
| `swap_size_mb` | `2048` | swap du Droplet |

**Important :** ne pas stocker de secrets dans `terraform.tfvars` commité. Les fichiers `terraform.tfstate`, `terraform.tfvars` et plans locaux peuvent contenir des secrets ; les garder privés et idéalement hors Git.

### Après apply Terraform

Récupérer les outputs :

```bash
terraform output backend_url
terraform output vercel_environment
terraform output deploy
terraform output health_checks
```

À mettre dans Vercel (projet frontend) :

```text
EXPO_PUBLIC_VIDEO_PARSER_BASE_URL=https://<backend-host>
EXPO_PUBLIC_VIDEO_PARSER_WS_URL=wss://<backend-host>/ws
```

À mettre dans GitHub Actions du repo/app qui construit `video-parser` :

| Type | Nom | Valeur |
|---|---|---|
| Secret | `DEPLOY_SSH_PRIVATE_KEY` | moitié privée correspondant à `deploy_ssh_public_key` |
| Secret | `DIGITALOCEAN_TOKEN` | token API DigitalOcean ; utilisé par le workflow pour ouvrir temporairement le firewall au runner GitHub |
| Variable | `DEPLOY_HOST` | output Terraform `deploy.DEPLOY_HOST` |
| Variable | `DEPLOY_USER` | `deploy` |
| Variable | `DO_FIREWALL_NAME` | `dekin-hosted-firewall` si `project = "dekin-hosted"` |

Le workflow `video-parser` pousse une image GHCR puis SSH sur le Droplet pour lancer :

```bash
sudo /usr/local/bin/dekin-deploy parser <image>
```

Attention : l’infra Terraform actuelle provisionne uniquement le déploiement du `video-parser` + MinIO + Caddy. Le workflow `server` peut construire/pousser une image GHCR, mais son déploiement SSH `dekin-deploy server` n’est pas supporté par le helper Terraform actuel. Ne pas activer le deploy automatique du `server` tant que l’infra correspondante n’est pas ajoutée.

### Ops production

SSH :

```bash
ssh root@<droplet-ip>
```

Logs et état :

```bash
cd /opt/dekin-hosted
docker compose --env-file .env --env-file deploy.env -f compose.yml ps
docker compose --env-file .env --env-file deploy.env -f compose.yml logs -f
journalctl -u cloud-init -f
```

Health check :

```bash
curl https://<backend-host>/pose/health
```

## 6. Infra on-prem / Ansible

Alternative dans `infrastructure/on-prem/` pour des VMs gérées :

```bash
cd infrastructure/on-prem
make start
make healthcheck
```

Les inventaires et variables sont dans :

- `infrastructure/on-prem/ansible/inventory/hosts.yml`
- `infrastructure/on-prem/ansible/inventory/group_vars/*.yml`

Les secrets on-prem doivent être placés dans un mécanisme de vault/secret manager (Ansible Vault, HCP Vault, 1Password, etc.), pas en clair dans Git.

## 7. Points d’attention avant passation

- Vérifier que les secrets historiques (tfstate/tfvars/.env) ne sont pas publiés.
- Pour la prod, utiliser des clés MinIO et DB fortes, pas les valeurs dev (`admin`, `minioadmin`).
- Les CORS du parser sont exacts : ajouter chaque domaine Vercel preview/prod dans `frontend_origin_patterns`.
- `frontend_origin_patterns` est injecté dans le cloud-init de premier boot ; comme le Droplet ignore les changements de `user_data`, modifier cette variable après coup nécessite soit d’éditer `/opt/dekin-hosted/.env` puis redémarrer, soit de recréer le Droplet.
- Le volume DigitalOcean protège les données contre un remplacement du Droplet, pas contre `terraform destroy` ni contre corruption applicative.
- Si un domaine custom est utilisé, créer le DNS manuellement puis renseigner `backend_hostname`.
- Le frontend caméra doit être testé sur appareil physique pour iOS ; le simulateur ne donne pas une validation complète.
