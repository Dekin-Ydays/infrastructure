# Flux de données des poses

Statut : **proposition**, liée à la refonte « Worker-first » (un Worker pour le site + l’API, un container réservé à l’extraction MediaPipe). Rien de ce document n’est encore implémenté.

## Contexte

Le modèle MediaPipe côté client (overlay live sur téléphone/navigateur) n’envoie rien au serveur : le chemin WebSocket `/ws` n’est plus appelé par le frontend (`getVideoParserWsUrl` n’a aucun appelant). Tout le volume vient du modèle **heavy** exécuté côté serveur par `video-parser/python/process_video.py` sur une vidéo uploadée.

Ce que produit une extraction (mesuré sur la forme de sortie actuelle) :

- 33 landmarks par frame (`x`, `y`, `z`, `visibility`) → **~3,8 KB** de JSON par frame
- clip de 60 s à 30 fps → ~1 800 frames → **~6,8 MB** brut, **≤ 2,3 MB** gzippé (borne haute, mesurée sur des valeurs aléatoires ; de vraies poses compressent mieux)
- une ligne de progression toutes les 100 frames (`PROGRESS_EVERY_N_FRAMES`)

## Situation actuelle

| Opération | Requêtes |
|---|---|
| Extraction (`POST /pose/video/process`) | 1 `createMany` de ~1 800 lignes `Frame` (une par frame) + 1 upsert `ExtractionJob` par ligne de progression |
| Lecture (`GET /pose/video/:id`) | lecture des ~1 800 lignes de la vidéo |
| Comparaison (`POST /pose/compare`) | lecture de ~3 600 lignes (deux vidéos), recalcul systématique même pour une paire déjà scorée |

Ça tient sur Postgres, mais pas sur D1 :

- limite de 10 GB par base → ~1 500 vidéos ;
- 100 paramètres liés max par requête → l’insert doit être découpé en dizaines de batchs ;
- facturation à la ligne lue/écrite à chaque vue et chaque comparaison.

## Principe

Les frames d’une vidéo sont **écrites une fois et toujours lues en entier** ; on ne requête jamais une frame isolée. Ce sont donc un **blob**, pas des lignes.

## Proposition

### Stockage

- **R2** : un objet par vidéo, `videos/<videoId>/frames.json.gz` (même forme que la sortie Python). Le parser exporte déjà `videos/<id>/video.json` ; cet objet devient la source de vérité.
- **D1** : uniquement des petites lignes.
  - `Video` : métadonnées, `frameCount`, `fps`, dimensions, clé de l’objet frames, clé de la vidéo source.
  - `ComparisonResult` : scores, `frameScores`, `breakdown`, `algorithmVersion` (inchangé).
  - plus de table `Frame` ; `ExtractionJob` remplacé par le Durable Object ci-dessous.

### Écriture (extraction)

1. Le client récupère une URL présignée, envoie la vidéo **directement dans R2** (plus de limite ~100 MB du Worker, plus de buffer mémoire), puis lance le job.
2. Un **Workflow** Cloudflare démarre l’extraction dans le container (Python + MediaPipe seulement).
3. Dans **une seule étape** du Workflow, la sortie du container est streamée directement vers R2 ; l’étape ne renvoie que `{ objectKey, frameCount, fps }`. Les ~6,8 MB de frames ne transitent jamais par l’état du Workflow (limité à ~1 MiB par étape).
4. Une étape finale écrit la ligne `Video` dans D1.

### Progression

- Un **Durable Object par job** garde l’état de progression.
- Les lignes `Processed N frames` du container lui sont transmises, **limitées à ~1 mise à jour par seconde**, au lieu d’un upsert DB par ligne.
- Web : SSE sur `GET /jobs/:id/events`. React Native (pas d’`EventSource`) : polling de `GET /jobs/:id`.
- L’état survit à un redémarrage, contrairement au `Subject` RxJS en mémoire actuel.

### Lecture

- `GET /pose/video/:id` sert l’objet R2 avec `Cache-Control: public, max-age=31536000, immutable` et un `ETag` : les frames ne changent jamais, donc la plupart des lectures sont servies par le cache edge.
- `POST /pose/compare` cherche d’abord un `ComparisonResult` existant pour `(referenceVideoId, comparisonVideoId, algorithmVersion)` (l’index existe déjà) ; sinon il lit les deux objets R2, calcule, et persiste le résultat.

## Bilan par opération

| Opération | Aujourd’hui | Proposé |
|---|---|---|
| Extraction | ~1 800 inserts + 1 upsert / 100 frames | 1 PUT R2 (frames) + 1–2 écritures D1 ; progression dans le DO |
| Lecture d’une vidéo | ~1 800 lignes lues | 1 GET R2, le plus souvent servi par le cache edge |
| Comparaison | ~3 600 lignes lues + calcul | 1 lecture D1 si déjà scorée, sinon 2 GET R2 + calcul + 1 écriture D1 |

Avec ce découpage, la base ne voit ni écritures massives ni lectures volumineuses : **D1 suffit**, sans Neon ni Postgres.

## Points ouverts

- **Format** : JSON gzippé suffit au départ. Un format binaire (protobuf existant ou `Float32Array`) diviserait la taille par ~4 si les vidéos s’allongent.
- **Données existantes** : les vidéos déjà extraites (lignes `Frame`) devront être exportées une fois en objets R2.
- **Rétention** : définir une règle de cycle de vie R2 pour les vidéos sources et les frames abandonnées.
