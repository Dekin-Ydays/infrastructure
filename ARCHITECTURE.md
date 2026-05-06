# Architecture Infrastructure — Projet Dekin

**Date de mise à jour :** 15 avril 2026  
**Sources :** `terraform/*.tf` et `AWS_COST_ANALYSIS.md`

---

## 1) Résumé

Le repo contient actuellement :

- une **infra AWS provisionnée par Terraform** (état réel),
- une **base Ansible historique 4 VMs** (frontend/backend/database/storage),
- une **analyse de coûts AWS** avec une cible optimisée.

L’état Terraform correspond à une architecture **EC2 + RDS + ECR** (sans ALB, sans CloudFront/S3 frontend).

---

## 2) Architecture AWS actuelle (Terraform)

### Réseau

- Région par défaut : `eu-west-3`
- VPC : `10.0.0.0/16` (configurable)
- 1 subnet publique (EC2)
- 2 subnets privées (RDS subnet group)
- Internet Gateway + route table publique
- Pas de NAT Gateway (subnets privées sans sortie Internet dédiée)

### Compute

- 1 instance EC2 (`aws_instance.app`) en subnet publique
  - Ubuntu 24.04
  - type par défaut : `t3.micro`
  - Elastic IP
  - Docker + Docker Compose + AWS CLI + ECR credential helper installés en `user_data`

### Base de données

- 1 RDS PostgreSQL 16 (`aws_db_instance.main`)
  - classe par défaut : `db.t4g.micro`
  - stockage : `20 Go` gp2 chiffré
  - non publique (`publicly_accessible = false`)
  - accès uniquement depuis le Security Group applicatif

- Credentials DB publiés en **SSM Parameter Store** (SecureString JSON)

### Registre d’images

- ECR repos :
  - `dekin/server`
  - `dekin/video-parser`
  - `dekin/frontend`

### IAM

- Rôle EC2 + instance profile
- Permissions : pull ECR + lecture du paramètre SSM des credentials DB

### Security Groups

- SG App (EC2) : ports entrants `22`, `80`, `443`, `8090`, `3000`
- SG DB (RDS) : `5432` autorisé seulement depuis SG App

---

## 3) Flux applicatifs

- Entrée HTTP/HTTPS sur EC2 (Nginx)
- Routage attendu :
  - `/api/` → Spring Boot (`8090`)
  - `/ws/` → NestJS parser (`3000`)
- Persistance des données applicatives et landmarks dans PostgreSQL RDS

---

## 4) Alignement avec AWS_COST_ANALYSIS

`AWS_COST_ANALYSIS.md` recommande en cible :

- Frontend statique : **S3 + CloudFront**
- Routage API/WS : **ALB**
- Compute backend : **EC2 t3.small**
- DB landmarks + applicative : **RDS db.t4g.small** (~100 Go)

### Écarts avec Terraform actuel

1. **EC2** : Terraform `t3.micro` vs recommandation `t3.small`
2. **RDS** : Terraform `db.t4g.micro`/20 Go vs recommandation `db.t4g.small`/100 Go
3. **Frontend edge** : pas de S3/CloudFront provisionnés
4. **Routage managé** : pas d’ALB provisionné

### Positionnement conseillé

- **Court terme** : rester sur l’architecture actuelle (Option B “budget”), mais monter les tailles si charge réelle.
- **Moyen terme** : ajouter ALB + CloudFront/S3 pour converger vers Option A.

---

## 5) Variables Terraform importantes

Dans `terraform/variables.tf` :

- `aws_profile`
- `region`
- `project`
- `instance_type`
- `ssh_public_key`
- `ssh_allowed_cidr`
- `db_instance_class`
- `db_allocated_storage`

Sorties utiles (`terraform/outputs.tf`) :

- `app_public_ip`
- `app_ssh_command`
- `db_endpoint`
- `db_credentials_parameter`
- `ecr_repository_urls`

---

## 6) Connecter ton tenant AWS au projet

### 6.1 Pré-requis

- AWS CLI v2
- Terraform >= 1.5
- Droits IAM sur VPC/EC2/ECR/RDS/SSM/IAM

### 6.2 Configurer un profil AWS

Option SSO (recommandée) :

```bash
aws configure sso --profile dekin-sso
aws sso login --profile dekin-sso
```

Option Access Keys :

```bash
aws configure --profile dekin-prod
```

### 6.3 Vérifier le bon compte/tenant

```bash
aws sts get-caller-identity --profile dekin-prod
## VM Specifications

Assume the following hostnames/IPs will be provided via inventory:

- `vm1_frontend` - Frontend server
- `vm2_backend` - Backend services server
- `vm3_database` - PostgreSQL server
- `vm4_storage` - MinIO object storage server

Base OS: Ubuntu 22.04 LTS (or Debian 12)

## Requirements by VM

### VM1 - Frontend Server

1. **Docker environment**
   - Install Docker CE from official repository
   - Install Docker Compose plugin
   - Create dedicated `docker` group and add deploy user

2. **Expo deployment (Dockerized)**
   - Clone the frontend repository (parameterized via variable `frontend_repo_url`)
   - Repository must contain a `Dockerfile` with multi-stage build:
     - Stage 1: Node 20 Alpine, install pnpm, build Expo web export
     - Stage 2: Nginx Alpine, copy built assets, serve static files
   - Use Docker Compose for orchestration
   - Container exposes port 80

3. **Docker Compose configuration**

   ```yaml
   services:
     frontend:
       build: .
       restart: unless-stopped
       ports:
         - '80:80'
   ```

4. **Expected Dockerfile structure in repo**

   ```dockerfile
   # Build stage
   FROM node:20-alpine AS builder
   RUN corepack enable && corepack prepare pnpm@latest --activate
   WORKDIR /app
   COPY package.json pnpm-lock.yaml ./
   RUN pnpm install --frozen-lockfile
   COPY . .
   RUN pnpm expo export:web

   # Production stage
   FROM nginx:alpine
   COPY --from=builder /app/dist /usr/share/nginx/html
   COPY nginx.conf /etc/nginx/conf.d/default.conf
   EXPOSE 80
   ```

### VM2 - Backend Server

1. **Docker environment**
   - Install Docker CE from official repository
   - Install Docker Compose plugin
   - Create dedicated `docker` group and add deploy user

2. **Spring Boot API (Dockerized)**
   - Clone the API repository (parameterized via `api_repo_url`)
   - Repository must contain a `Dockerfile` with multi-stage build
   - Container runs on port 8080 (internal network only)

3. **NestJS Video Parser (Dockerized)**
   - Clone the parser repository (parameterized via `parser_repo_url`)
   - Repository must contain a `Dockerfile` with multi-stage build
   - Container runs on port 3000 (internal network only)

4. **Docker Compose configuration**

   ```yaml
   services:
     api:
       build: ./api
       restart: unless-stopped
       environment:
         DATABASE_URL: jdbc:postgresql://${DB_HOST}:5432/${DB_NAME}
         DATABASE_USER: ${DB_USER}
         DATABASE_PASSWORD: ${DB_PASSWORD}
       networks:
         - backend
       expose:
         - '8080'

     parser:
       build: ./parser
       restart: unless-stopped
       environment:
         MINIO_ENDPOINT: http://${MINIO_HOST}:9000
         MINIO_ACCESS_KEY: ${MINIO_ACCESS_KEY}
         MINIO_SECRET_KEY: ${MINIO_SECRET_KEY}
         MINIO_BUCKET: ${MINIO_BUCKET}
       networks:
         - backend
       expose:
         - '3000'

     nginx:
       image: nginx:alpine
       restart: unless-stopped
       ports:
         - '80:80'
         - '443:443'
       volumes:
         - ./nginx/backend.conf:/etc/nginx/conf.d/default.conf:ro
         - ./nginx/certs:/etc/nginx/certs:ro # Optional TLS
       networks:
         - backend
       depends_on:
         - api
         - parser

   networks:
     backend:
       driver: bridge
   ```

5. **Nginx reverse proxy configuration**
   Template `nginx/backend.conf`:

   ```nginx
   upstream api {
       server api:8080;
   }

   upstream parser {
       server parser:3000;
   }

   server {
       listen 80;
       server_name _;

       location /api/ {
           proxy_pass http://api/;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }

       location /ws/ {
           proxy_pass http://parser/;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_read_timeout 86400;
       }
   }
   ```

6. **Expected Dockerfile for Spring Boot (in api repo)**

   ```dockerfile
   # Build stage
   FROM eclipse-temurin:21-jdk-alpine AS builder
   WORKDIR /app
   COPY . .
   RUN ./mvnw clean package -DskipTests
   # Or for Gradle: RUN ./gradlew build -x test

   # Production stage
   FROM eclipse-temurin:21-jre-alpine
   WORKDIR /app
   COPY --from=builder /app/target/*.jar app.jar
   EXPOSE 8080
   ENTRYPOINT ["java", "-jar", "app.jar"]
   ```

7. **Expected Dockerfile for NestJS (in parser repo)**

   ```dockerfile
   # Build stage
   FROM node:20-alpine AS builder
   RUN corepack enable && corepack prepare pnpm@latest --activate
   WORKDIR /app
   COPY package.json pnpm-lock.yaml ./
   RUN pnpm install --frozen-lockfile
   COPY . .
   RUN pnpm build

   # Production stage
   FROM node:20-alpine
   RUN corepack enable && corepack prepare pnpm@latest --activate
   WORKDIR /app
   COPY --from=builder /app/dist ./dist
   COPY --from=builder /app/node_modules ./node_modules
   COPY --from=builder /app/package.json ./
   EXPOSE 3000
   CMD ["node", "dist/main.js"]
   ```

### VM3 - PostgreSQL Database

1. **PostgreSQL 16**
   - Install from official PostgreSQL APT repository
   - Create database: `{{ db_name }}`
   - Create user: `{{ db_user }}` with password `{{ db_password }}`
   - Grant all privileges on database to user

2. **Network configuration**
   - Configure `postgresql.conf`: `listen_addresses = '*'`
   - Configure `pg_hba.conf`: Allow connections from VM2 backend IP
     ```
     host    {{ db_name }}    {{ db_user }}    {{ vm2_backend_ip }}/32    scram-sha-256
     ```

3. **Security hardening**
   - Disable remote root login
   - Configure UFW: Allow port 5432 only from VM2

### VM4 - MinIO Object Storage

1. **MinIO server**
   - Download and install MinIO binary
   - Create dedicated `minio` user
   - Create data directory `/data/minio`
   - Create systemd service `minio.service`
   - Configure environment:
     - `MINIO_ROOT_USER={{ minio_access_key }}`
     - `MINIO_ROOT_PASSWORD={{ minio_secret_key }}`
   - Run on port 9000 (API) and 9001 (Console)

2. **Initial setup**
   - Install MinIO client (mc)
   - Create bucket: `{{ minio_bucket_name }}`
   - Set bucket policy as needed (private by default)

3. **Network configuration**
   - Configure UFW: Allow port 9000 only from VM2

## On-Prem Ansible Project Structure

```

Contrôler que `Account` est bien celui de ton tenant AWS.

### 6.4 Brancher Terraform sur ce profil

Créer `terraform/terraform.tfvars` à partir de `terraform/terraform.tfvars.example`, puis ajuster :

```hcl
aws_profile          = "dekin-prod"
region               = "eu-west-3"
project              = "dekin"
instance_type        = "t3.small"
db_instance_class    = "db.t4g.small"
db_allocated_storage = 100
ssh_public_key       = "ssh-ed25519 AAAA..."
ssh_allowed_cidr     = "<TON_IP>/32"
on-prem/
├── Makefile
├── README.md
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   │       ├── all.yml          # Common variables
│   │       ├── frontend.yml
│   │       ├── backend.yml
│   │       ├── database.yml
│   │       └── storage.yml
│   ├── playbooks/
│   │   ├── site.yml             # Main playbook (imports all)
│   │   ├── frontend.yml
│   │   ├── backend.yml
│   │   ├── database.yml
│   │   └── storage.yml
│   ├── roles/
│   │   ├── common/
│   │   ├── docker/
│   │   ├── frontend/
│   │   ├── backend/
│   │   ├── postgresql/
│   │   └── minio/
│   └── files/
│       └── .dockerignore
└── inventory/               # Legacy root-level inventory, kept with on-prem option
```

### 6.5 Provisionner

```bash
cd terraform
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

### 6.6 Récupérer les outputs

```bash
terraform output
```

Utiliser ensuite :

- `app_public_ip` pour SSH/Ansible
- `db_credentials_parameter` pour récupération des secrets DB côté instance/app
- `ecr_repository_urls` pour push des images CI/CD

### 6.7 Connecter Ansible à l’hôte AWS

Mettre `app_public_ip` dans l’inventaire Ansible (hôte backend cible), avec la clé privée SSH correspondant à `ssh_public_key`.

---

## 7) Points de vigilance

- `ssh_allowed_cidr = 0.0.0.0/0` est à éviter en production.
- Exposer `8090` et `3000` publiquement augmente la surface d’attaque ; idéalement n’exposer que `80/443`.
- `skip_final_snapshot = true` sur RDS n’est pas adapté à un environnement critique.
- Le dossier Ansible reste orienté 4 VMs et doit être réaligné si la cible AWS finale est mono-EC2 + services managés.
