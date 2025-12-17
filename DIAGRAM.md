```mermaidjs
flowchart TB
    subgraph VM1["VM1 - Frontend"]
        front["frontend (Expo)"]
    end

    subgraph VM2["VM2 - Backend"]
        nginx["Nginx (Reverse Proxy)"]
        api["api (Spring Boot REST)"]
        parser["video parser (NestJS WS)"]

        nginx -->|"/api/ → HTTP"| api
        nginx -->|"/ws/ → WebSocket"| parser
    end

    subgraph DB1["DB1 - Database"]
        postgres[(PostgreSQL)]
    end

    subgraph DB2["DB2 - Storage"]
        minio[(MinIO S3 Bucket)]
    end

    front -->|"HTTP /api/*"| nginx
    front -.->|"WS /ws/*"| nginx

    api -->|"TCP:5432"| postgres
    parser -->|"HTTP S3 API"| minio
```
