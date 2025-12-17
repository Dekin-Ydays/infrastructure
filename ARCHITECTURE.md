# Ansible Infrastructure Setup - Video Parser Application

## Overview

Implement an Ansible playbook to provision and configure a 4-VM infrastructure for a video parsing application with the following architecture:

```
┌─────────────────┐
│   VM1: Frontend │
│     (Expo)      │
└────────┬────────┘
         │ HTTP + WebSocket
         ▼
┌─────────────────────────────────┐
│         VM2: Backend            │
│  ┌───────────────────────────┐  │
│  │    Nginx (Reverse Proxy)  │  │
│  └─────────┬─────────────────┘  │
│            │                    │
│  ┌─────────▼───┐  ┌──────────┐  │
│  │ Spring Boot │  │  NestJS  │  │
│  │  REST API   │  │ WS Parser│  │
│  └─────────────┘  └──────────┘  │
└────────┬──────────────┬─────────┘
         │              │
         ▼              ▼
┌─────────────┐  ┌─────────────┐
│ VM3: DB1    │  │ VM4: DB2    │
│ PostgreSQL  │  │   MinIO     │
└─────────────┘  └─────────────┘
```

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

## Ansible Project Structure

```
ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml          # Common variables
│       ├── frontend.yml
│       ├── backend.yml
│       ├── database.yml
│       └── storage.yml
├── playbooks/
│   ├── site.yml             # Main playbook (imports all)
│   ├── frontend.yml
│   ├── backend.yml
│   ├── database.yml
│   └── storage.yml
├── roles/
│   ├── common/              # Base setup for all VMs
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   └── handlers/
│   │       └── main.yml
│   ├── docker/              # Docker CE installation
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   └── handlers/
│   │       └── main.yml
│   ├── frontend/            # Expo frontend deployment
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── templates/
│   │   │   └── docker-compose.yml.j2
│   │   └── files/
│   │       └── nginx.conf
│   ├── backend/             # API + Parser + Nginx deployment
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── templates/
│   │   │   ├── docker-compose.yml.j2
│   │   │   ├── .env.j2
│   │   │   └── backend.conf.j2
│   │   └── handlers/
│   │       └── main.yml
│   ├── postgresql/
│   │   ├── tasks/
│   │   │   └── main.yml
│   │   ├── templates/
│   │   │   ├── pg_hba.conf.j2
│   │   │   └── postgresql.conf.j2
│   │   └── handlers/
│   │       └── main.yml
│   └── minio/
│       ├── tasks/
│       │   └── main.yml
│       ├── templates/
│       │   └── minio.service.j2
│       └── handlers/
│           └── main.yml
└── files/
    └── .dockerignore        # Shared dockerignore if needed
```

## Variables to Define

### Required Variables (must be provided)

```yaml
# Git repositories
frontend_repo_url: ''
api_repo_url: ''
parser_repo_url: ''

# Database
db_name: 'videoparser'
db_user: 'videoparser'
db_password: '' # Use ansible-vault

# MinIO
minio_access_key: '' # Use ansible-vault
minio_secret_key: '' # Use ansible-vault
minio_bucket_name: 'videos'

# Network (auto-populated from inventory ideally)
vm2_backend_ip: ''
vm3_database_ip: ''
vm4_storage_ip: ''
```

### Optional Variables

```yaml
# TLS Configuration
enable_tls: false
tls_cert_path: ''
tls_key_path: ''

# Docker configuration
docker_compose_version: '2.24' # Installed via plugin, this is informational

# PostgreSQL version
postgresql_version: '16'

# Git branch/tag for each repo (defaults to main)
frontend_repo_branch: 'main'
api_repo_branch: 'main'
parser_repo_branch: 'main'

# Application ports (defaults, exposed via Docker)
springboot_port: 8080
nestjs_port: 3000
minio_api_port: 9000
minio_console_port: 9001
```

## Common Role Tasks

The `common` role should:

1. Update apt cache
2. Install base packages: `curl`, `wget`, `git`, `ufw`, `htop`, `vim`
3. Configure UFW with default deny incoming, allow SSH
4. Set timezone
5. Configure NTP
6. Create swap file if needed (parameterized)

## Docker Role Tasks

The `docker` role should:

1. Install required packages: `ca-certificates`, `curl`, `gnupg`
2. Add Docker's official GPG key
3. Add Docker APT repository
4. Install `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`
5. Enable and start Docker service
6. Add deploy user to `docker` group

## Execution Order

The playbooks should be executable in this order due to dependencies:

1. `database.yml` - PostgreSQL must be ready first
2. `storage.yml` - MinIO must be ready for parser
3. `backend.yml` - Depends on DB and storage being available
4. `frontend.yml` - Can technically run in parallel but logically last

The `site.yml` should orchestrate this order.

## Handlers

Implement handlers for:

- `restart docker`
- `restart frontend containers` (docker compose down/up in frontend dir)
- `restart backend containers` (docker compose down/up in backend dir)
- `restart postgresql`
- `restart minio`
- `reload systemd`

## Idempotency Requirements

All tasks must be idempotent. Specifically:

- Use `creates` argument for download tasks
- Use `state: present` appropriately
- Check if services exist before creating
- Use `--check` mode compatible tasks

## Security Considerations

1. Use `ansible-vault` for all sensitive variables (passwords, keys)
2. Set appropriate file permissions (0600 for secrets, 0644 for configs)
3. Run services as non-root dedicated users
4. Firewall rules should be restrictive (only allow required ports from required IPs)
5. Disable password authentication for SSH (assume key-based)

## Testing

Include a simple health check playbook `playbooks/healthcheck.yml` that:

1. Checks if all services are running
2. Tests HTTP connectivity to frontend
3. Tests API endpoint via backend
4. Tests WebSocket connectivity
5. Tests database connectivity
6. Tests MinIO connectivity

## Deliverables

1. Complete Ansible project with all files listed in structure
2. Sample inventory file with placeholder IPs
3. Sample `group_vars/all.yml` with all variables documented
4. README.md with:
   - Prerequisites
   - How to configure inventory
   - How to set up vault
   - How to run playbooks
   - Troubleshooting common issues
