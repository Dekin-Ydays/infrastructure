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
