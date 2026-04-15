# Analyse des Coûts AWS — Plateforme Dekin

**Date :** Mars 2026
**Scénario :** 100 utilisateurs, 1 heure/jour chacun
**Région :** eu-west-3 (Paris)

---

## Architecture Actuelle → Équivalence AWS

| Actuel (4 VMs) | Équivalent AWS | Justification |
|---|---|---|
| VM1 — Nginx servant le build statique Expo | **S3 + CloudFront** | Site statique — pas besoin d'une VM |
| VM2 — Spring Boot + NestJS + Nginx proxy | **EC2 t3.small + ALB** | Calcul pour JVM + Node.js, ALB gère le routage + WebSocket |
| VM3 — PostgreSQL 16 (bare metal) | **RDS PostgreSQL (db.t4g.micro)** | BDD managée, sauvegardes automatiques |
| VM4 — MinIO (stockage compatible S3) | **S3** | MinIO est un clone de S3 — autant utiliser l'original |
| UFW pare-feu | **Security Groups + VPC** | Isolation réseau native AWS |
| Nginx reverse proxy (VM2) | **Application Load Balancer** | Route `/api/` → Spring Boot, `/ws/` → WebSocket NestJS |

---

## Schéma d'Architecture AWS

```
                    ┌──────────────┐
                    │   Route 53   │  DNS
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │  CloudFront  │  CDN (frontend statique)
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──┐  ┌──────▼──────┐    │
       │   S3    │  │     ALB     │    │
       │ (site   │  │ /api/ → EC2 │    │
       │ statiq.)│  │ /ws/  → EC2 │    │
       └─────────┘  └──────┬──────┘    │
                           │            │
                    ┌──────▼───────┐    │
                    │  EC2 t3.small │    │
                    │  ┌─────────┐ │    │
                    │  │ Spring  │ │    │
                    │  │ Boot    │ │    │
                    │  │ :8080   │ │    │
                    │  ├─────────┤ │    │
                    │  │ NestJS  │ │    │
                    │  │ :3000   │ │    │
                    │  └─────────┘ │    │
                    └───┬──────┬───┘    │
                        │      │        │
              ┌─────────▼──┐  ┌▼────────▼──┐
              │ RDS        │  │     S3      │
              │ PostgreSQL │  │  (vidéos +  │
              │ t4g.micro  │  │  landmarks) │
              └────────────┘  └────────────┘
```

---

## Flux de Données — Le Point Critique

### Comment ça marche actuellement

```
Téléphone (MediaPipe)        NestJS (video-parser)           Base de données
      │                            │                              │
      │  Landmarks JSON via WS     │                              │
      │  (toutes les 3 frames)     │                              │
      ├──────────────────────────► │                              │
      │                            │  INSERT frame (1 par paquet) │
      │                            ├─────────────────────────────►│
      │           ACK              │                              │
      │◄────────────────────────── │                              │
      │                            │                              │
      │  ... ×10 par seconde ...   │                              │
```

**Chaque frame MediaPipe contient :**
- 33 landmarks × (x, y, z, visibility) = ~2,5 Ko de JSON par frame
- Envoi : toutes les 3 frames à 30fps = **10 paquets/seconde par utilisateur**
- Le backend fait **un INSERT en base par paquet reçu** (`pose-video.repository.ts:createFrame`)

### Volume d'Écritures

| Métrique | Calcul | Résultat |
|---|---|---|
| Écritures/sec par utilisateur | 30fps ÷ 3 = 10 frames/sec | **10 writes/sec** |
| Écritures/sec (100 utilisateurs simultanés) | 100 × 10 | **1 000 writes/sec** |
| Écritures par session (1h) | 10 × 3 600 | **36 000 writes** |
| Écritures par jour (100 utilisateurs) | 36 000 × 100 | **3 600 000 writes/jour** |
| **Écritures par mois** | 3 600 000 × 30 | **108 000 000 writes/mois** |
| Données par session | 36 000 frames × 2,5 Ko | **90 Mo/session** |
| Données par jour | 90 Mo × 100 | **9 Go/jour** |
| **Données par mois** | 9 Go × 30 | **270 Go/mois** |

> **Note :** Ce calcul suppose 1h d'enregistrement actif continu. Si les utilisateurs enregistrent activement ~15 min/heure (le reste étant navigation, comparaisons, etc.), diviser par 4 : ~27M writes/mois et ~68 Go/mois.

---

## Pourquoi NE PAS écrire chaque frame dans S3

Le code actuel fait un INSERT par frame. Si on transpose naïvement vers S3 :

| Approche | Coût S3 PUT | Coût Stockage (1er mois) | Total Mois 1 |
|---|---|---|---|
| **1 PUT par frame (naïf)** | 108M × $0,005/1000 = **$540** | 270 Go × $0,023 = $6,21 | **$546/mois** |
| **1 PUT par session** | 3 000 × $0,005/1000 = **$0,015** | 270 Go × $0,023 = $6,21 | **$6,22/mois** |

**$540/mois juste en requêtes PUT** — c'est 7× le coût de toute l'infrastructure restante. L'écriture individuelle par frame dans S3 est économiquement absurde.

---

## Solutions de Stockage pour les Landmarks

### Option 1 : RDS PostgreSQL (utiliser la BDD existante) — RECOMMANDÉ

Stocker les frames de landmarks dans la même instance RDS que le reste de l'application.

| Avantage | Détail |
|---|---|
| Pas de coût supplémentaire | Déjà provisionné pour Spring Boot |
| Supporte 1 000 writes/sec | PostgreSQL gère facilement ce débit |
| Requêtes SQL | Permet des analyses, agrégations, indexations |
| Transactions | Intégrité garantie |

**Coût additionnel :** Passage de `db.t4g.micro` (1 Go) à `db.t4g.small` (2 Go) pour absorber la charge.

| Élément | Coût |
|---|---|
| db.t4g.small (2 vCPU, 2 Go RAM) | $23,36/mois |
| Stockage gp3 100 Go (pour 3-4 mois de données) | $11,50/mois |
| IOPS provisionnées gp3 (3 000 inclus, suffisant) | $0,00 |
| **Sous-total RDS** | **$34,86/mois** |

### Option 2 : S3 avec Batch (buffering côté serveur)

Accumuler les frames en mémoire dans NestJS, écrire un seul objet S3 par session d'enregistrement.

```
WS frames (×36 000) → Buffer mémoire NestJS → 1 objet S3 (90 Mo JSON/session)
```

| Élément | Calcul | Coût |
|---|---|---|
| PUT requests | 3 000 sessions × $0,005/1000 | $0,015 |
| Stockage S3 Standard | 270 Go/mois × $0,023/Go | $6,21 |
| GET requests (comparaisons) | 50 000 × $0,0004/1000 | $0,02 |
| **Sous-total S3** | | **$6,24/mois** |

**Avantage :** Très bon marché. **Inconvénient :** Si le serveur crash pendant une session, les données en mémoire sont perdues. Nécessite de modifier le code actuel (actuellement chaque frame est persistée immédiatement).

### Option 3 : DynamoDB (écritures haute fréquence)

| Mode | Calcul | Coût |
|---|---|---|
| On-Demand (108M writes × 3 WCU chacun) | 324M WRU × $1,25/M | **$405/mois** |
| Provisioned (900 WCU pour pic 30 utilisateurs) | 900 × $0,000469/WCU-hr × 730 | **$308/mois** |
| Stockage | 270 Go × $0,25/Go | $67,50/mois |
| **Total DynamoDB** | | **$375–473/mois** |

> DynamoDB est excessif pour ce cas d'usage. Les données sont séquentielles par vidéo, pas un accès clé-valeur aléatoire.

### Comparatif des Options de Stockage Landmarks

| | RDS PostgreSQL | S3 Batch | DynamoDB | S3 Naïf (1 PUT/frame) |
|---|---|---|---|---|
| **Coût/mois** | **~$35** | **~$6** | **~$400** | **~$546** |
| Modification du code | Aucune (Prisma → pg) | Importante (bufferisation) | Importante | Aucune |
| Perte de données si crash | Aucune | Session en cours perdue | Aucune | Aucune |
| Performance requête | Excellent (SQL) | Lent (lire 90 Mo par vidéo) | Bon | Très lent (36K GET) |
| Complexité | Faible | Moyenne | Moyenne | Faible |

**Recommandation : Option 1 (RDS)** pour la simplicité et la fiabilité, ou **Option 2 (S3 Batch)** si le coût est la priorité absolue et qu'on accepte de modifier le code.

---

## Hypothèses d'Utilisation Révisées

| Métrique | Scénario Actif Complet (1h) | Scénario Réaliste (~15 min actif) |
|---|---|---|
| Frames WS par session | 36 000 | 9 000 |
| Écritures BDD par mois | 108 000 000 | 27 000 000 |
| Données landmarks par mois | 270 Go | 68 Go |
| Appels API REST par session | ~100 | ~100 |
| Requêtes API mensuelles | 300 000 | 300 000 |
| Données sortantes mensuelles | ~80 Go | ~30 Go |

> Pour la suite, on utilise le **scénario réaliste** (15 min d'enregistrement actif par heure de session).

---

## Coûts Mensuels Détaillés

### 1. Frontend — S3 + CloudFront

| Élément | Calcul | Coût |
|---|---|---|
| Stockage S3 (bundle statique) | ~10 Mo | $0,01 |
| Transfert CloudFront | 6 Go × $0,085/Go | $0,51 |
| Requêtes CloudFront | 150 000 × $0,012/10 000 | $0,18 |
| **Sous-total** | | **$0,70** |

### 2. Backend — EC2

| Élément | Calcul | Coût |
|---|---|---|
| EC2 t3.small (2 vCPU, 2 Go RAM) | $0,0228/h × 730h | $16,64 |
| EBS gp3 20 Go (OS + app) | 20 Go × $0,088/Go | $1,76 |
| Snapshot EBS | 20 Go × $0,05/Go | $1,00 |
| **Sous-total** | | **$19,40** |

### 3. Application Load Balancer

| Élément | Calcul | Coût |
|---|---|---|
| ALB fixe | $0,0225/h × 730h | $16,43 |
| LCU (trafic WebSocket soutenu) | ~1 LCU moy. × $0,008/LCU-h × 730 | $5,84 |
| **Sous-total** | | **$22,27** |

> Le coût LCU est plus élevé que l'estimation initiale à cause des connexions WebSocket persistantes (100 connexions actives, 10 messages/sec).

### 4. Base de Données — RDS PostgreSQL (landmarks + API)

| Élément | Calcul | Coût |
|---|---|---|
| db.t4g.small (2 vCPU, 2 Go RAM) Single-AZ | $0,032/h × 730h | $23,36 |
| Stockage gp3 100 Go | 100 Go × $0,115/Go | $11,50 |
| Sauvegardes automatiques | Inclus (100 Go) | $0,00 |
| **Sous-total** | | **$34,86** |

> Taille augmentée à `db.t4g.small` et 100 Go de stockage pour absorber 27M writes/mois de landmarks. Le stockage gp3 inclut 3 000 IOPS de base, suffisant pour le pic de ~300 writes/sec (30 utilisateurs simultanés × 10 writes/sec).

### 5. Stockage Objet — S3 (vidéos comparées, exports)

| Élément | Calcul | Coût |
|---|---|---|
| Stockage S3 Standard | ~20 Go/mois (exports, médias) | $0,46 |
| Requêtes PUT/GET | Négligeable à ce volume | $0,10 |
| **Sous-total** | | **$0,56** |

> Avec les landmarks dans RDS, S3 ne sert qu'aux exports et médias optionnels. Volume bien moindre.

### 6. Transfert de Données (sortant)

| Élément | Calcul | Coût |
|---|---|---|
| Premiers 10 Go/mois | Gratuit | $0,00 |
| 20 Go suivants (API + WS ACK + comparaisons) | 20 Go × $0,09/Go | $1,80 |
| **Sous-total** | | **$1,80** |

### 7. Services Annexes

| Élément | Coût |
|---|---|
| Route 53 (DNS) | $0,70 |
| ACM (SSL/TLS) | Gratuit |
| CloudWatch (basic) | Gratuit |
| VPC, Security Groups | Gratuit |
| **Sous-total** | **$0,70** |

---

## Coût Mensuel Total

### Option A : Recommandée (RDS pour landmarks + ALB)

| Service | Coût/mois |
|---|---|
| S3 + CloudFront (frontend) | $0,70 |
| EC2 t3.small (backend) | $19,40 |
| ALB (routage + WebSocket) | $22,27 |
| RDS PostgreSQL t4g.small (landmarks + API) | $34,86 |
| S3 (stockage objet) | $0,56 |
| Transfert de données | $1,80 |
| Route 53 + ACM | $0,70 |
| **Total Mensuel** | **~$80/mois** |
| **Total Annuel** | **~$960** |

### Option B : Budget (Nginx sur EC2, pas d'ALB)

| Service | Coût/mois |
|---|---|
| S3 + CloudFront (frontend) | $0,70 |
| EC2 t3.small (backend + nginx) | $19,40 |
| RDS PostgreSQL t4g.small | $34,86 |
| S3 (stockage objet) | $0,56 |
| Transfert de données | $1,80 |
| Route 53 + ACM | $0,70 |
| **Total Mensuel** | **~$58/mois** |
| **Total Annuel** | **~$696** |

### Option C : Ultra-Budget (S3 Batch, pas d'ALB)

Nécessite de modifier le code pour bufferiser les frames et écrire en batch dans S3.

| Service | Coût/mois |
|---|---|
| S3 + CloudFront (frontend) | $0,70 |
| EC2 t3.small (backend + nginx) | $19,40 |
| RDS PostgreSQL t4g.micro (API seulement) | $15,44 |
| S3 (landmarks batchés + stockage) | $6,24 |
| Transfert de données | $1,80 |
| Route 53 + ACM | $0,70 |
| **Total Mensuel** | **~$44/mois** |
| **Total Annuel** | **~$528** |

### Option D : Avec Instances Réservées (1 an, Option A)

| Service | On-Demand | Réservé (1 an) |
|---|---|---|
| EC2 t3.small | $16,64 | $10,51 |
| RDS t4g.small | $23,36 | $14,76 |
| Autres services | $40,29 | $40,29 |
| **Total Mensuel** | **~$80** | **~$66** |
| **Total Annuel** | **~$960** | **~$786** |

---

## Évolution du Stockage sur 12 Mois

Les données de landmarks croissent en continu. Avec le scénario réaliste (15 min actif/session) :

| Mois | Données Cumulées (RDS) | Coût Stockage RDS gp3 | Commentaire |
|---|---|---|---|
| 1 | 68 Go | $11,50 (100 Go provisionné) | Espace libre |
| 3 | 204 Go | $23,00 (200 Go) | Extension nécessaire |
| 6 | 408 Go | $46,00 (400 Go) | Envisager purge ou archivage |
| 12 | 816 Go | $92,00 (800 Go) | Archiver les anciennes données dans S3 |

**Stratégie de rétention recommandée :**
- Garder 90 jours de landmarks dans RDS (accès rapide pour comparaisons)
- Exporter les données plus anciennes vers S3 Glacier ($0,004/Go)
- Avec purge à 90 jours : stockage RDS stable autour de ~200 Go = $23/mois

---

## Pistes d'Optimisation

| Stratégie | Économie | Effort |
|---|---|---|
| **Supprimer l'ALB → Nginx sur EC2** | -$22/mois | Faible (comme la config actuelle) |
| **Instances Réservées (1 an)** | -$15/mois | Nul (engagement) |
| **Purge landmarks > 90j vers S3 Glacier** | Empêche la croissance du stockage RDS | Moyen (cron job + script) |
| **Batching S3 au lieu de RDS** | -$28/mois (Option C) | Élevé (refactoring du code) |
| **Réduire la fréquence d'envoi** (toutes les 5 frames au lieu de 3) | -40% d'écritures et stockage | Faible (changement frontend) |
| **Compresser les landmarks** (binaire au lieu de JSON) | -60% de stockage | Moyen |
| **EC2 Spot Instance** | -40-60% sur le compute | Faible (si tolérance aux interruptions) |

---

## Offre Gratuite AWS (nouveau compte < 12 mois)

| Service | Offre Gratuite | Valeur |
|---|---|---|
| EC2 t3.micro | 750 h/mois | ~$7,60/mois |
| RDS db.t4g.micro | 750 h/mois | ~$13/mois |
| S3 | 5 Go + 20K GET + 2K PUT | ~$1/mois |
| CloudFront | 1 To + 10M requêtes | ~$2/mois |
| ALB | 750 h + 15 LCU | ~$22/mois |
| **Économies offre gratuite** | | **~$46/mois** |

> Avec l'offre gratuite : **Option A ≈ $34/mois**, **Option B ≈ $12/mois** la première année.

---

## Résumé

| Scénario | Mensuel | Annuel |
|---|---|---|
| **Ultra-Budget (S3 batch, sans ALB)** | **~$44** | **~$528** |
| **Budget (RDS, sans ALB)** | **~$58** | **~$696** |
| **Recommandé (RDS + ALB)** | **~$80** | **~$960** |
| **Optimisé (Instances Réservées)** | **~$66** | **~$786** |
| Budget + offre gratuite (année 1) | ~$12 | ~$144 |
| Recommandé + offre gratuite (année 1) | ~$34 | ~$408 |

### Point Clé

Le coût dominant n'est **pas** le compute ni le CDN — c'est le **stockage des landmarks**. À 10 frames/sec par utilisateur, les données s'accumulent à ~68 Go/mois. Le choix critique est :

1. **Ne jamais écrire les frames individuellement dans S3** — les requêtes PUT coûteraient $540/mois
2. **Utiliser RDS PostgreSQL** comme stockage de frames (simple, fiable, ~$35/mois)
3. **Mettre en place une purge/archivage** après 90 jours pour maîtriser la croissance du stockage
4. **Optionnel :** Réduire la fréquence d'envoi (toutes les 5 frames = -40% de données) ou compresser les landmarks en binaire (-60%)
