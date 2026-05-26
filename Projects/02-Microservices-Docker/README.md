# Project 2: Microservices on Docker Compose

## Overview
Build a 5-service microservices system using Docker Compose with proper networking, health checks, secrets, volumes, and an NGINX reverse proxy.

**Services**: Frontend (React/Nginx), API Gateway (Node.js), Auth Service (Python), Orders Service (Go), PostgreSQL, Redis

**Skills**: Docker Compose v3, multi-network isolation, healthchecks, secrets, volumes, NGINX reverse proxy, service discovery

---

## Architecture
```
                    NGINX (port 80/443)
                    ┌───────┴───────┐
               /api/*          /auth/*
                ↓                  ↓
          API Gateway         Auth Service
               ↓                  ↓
        Orders Service         Redis (session cache)
               ↓
          PostgreSQL (orders DB)
          
Networks:
  frontend-net: nginx ↔ api-gateway ↔ auth-service
  backend-net:  api-gateway ↔ orders-service ↔ postgres ↔ redis
  (postgres/redis NOT reachable from nginx — isolated)
```

---

## Project Structure
```
02-Microservices-Docker/
├── docker-compose.yml
├── docker-compose.override.yml   (dev overrides)
├── docker-compose.prod.yml       (production overrides)
├── .env.example
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf
├── api-gateway/
│   ├── Dockerfile
│   ├── src/
│   └── package.json
├── auth-service/
│   ├── Dockerfile
│   └── app/
├── orders-service/
│   ├── Dockerfile
│   └── main.go
├── postgres/
│   └── init.sql
└── scripts/
    ├── start.sh
    └── healthcheck.sh
```

---

## Core Docker Compose File

**docker-compose.yml** — production-ready structure with comments explaining every decision.

```yaml
version: "3.9"

# --- Reusable snippets via YAML anchors ---
x-logging: &default-logging
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"

x-healthcheck-defaults: &hc-defaults
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s

x-security-defaults: &security-defaults
  security_opt:
    - no-new-privileges:true
  read_only: true

services:

  # ── Reverse Proxy ────────────────────────────────────────────────
  nginx:
    image: nginx:1.26-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro
      - nginx-cache:/var/cache/nginx
    depends_on:
      api-gateway:
        condition: service_healthy
      auth-service:
        condition: service_healthy
    networks:
      - frontend-net
    healthcheck:
      <<: *hc-defaults
      test: ["CMD", "nginx", "-t"]
    logging: *default-logging

  # ── API Gateway ──────────────────────────────────────────────────
  api-gateway:
    build:
      context: ./api-gateway
      target: production
    restart: unless-stopped
    environment:
      NODE_ENV: production
      AUTH_SERVICE_URL: http://auth-service:3001
      ORDERS_SERVICE_URL: http://orders-service:8080
      LOG_LEVEL: info
    env_file:
      - .env
    networks:
      - frontend-net
      - backend-net
    healthcheck:
      <<: *hc-defaults
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))"]
    depends_on:
      orders-service:
        condition: service_healthy
      auth-service:
        condition: service_healthy
    <<: *security-defaults
    tmpfs:
      - /tmp
    logging: *default-logging
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M

  # ── Auth Service ─────────────────────────────────────────────────
  auth-service:
    build:
      context: ./auth-service
      target: production
    restart: unless-stopped
    environment:
      REDIS_URL: redis://redis:6379/0
      JWT_SECRET_FILE: /run/secrets/jwt_secret
    secrets:
      - jwt_secret
    networks:
      - frontend-net
      - backend-net
    healthcheck:
      <<: *hc-defaults
      test: ["CMD", "python", "-c",
             "import urllib.request; urllib.request.urlopen('http://localhost:3001/health')"]
    depends_on:
      redis:
        condition: service_healthy
    <<: *security-defaults
    tmpfs:
      - /tmp
    logging: *default-logging

  # ── Orders Service ───────────────────────────────────────────────
  orders-service:
    build:
      context: ./orders-service
      target: production
    restart: unless-stopped
    environment:
      DB_HOST: postgres
      DB_PORT: "5432"
      DB_NAME: orders
      DB_USER: orders_app
    secrets:
      - db_password
    networks:
      - backend-net
    healthcheck:
      <<: *hc-defaults
      test: ["CMD", "/bin/orders-service", "-healthcheck"]
    depends_on:
      postgres:
        condition: service_healthy
    <<: *security-defaults
    tmpfs:
      - /tmp
    logging: *default-logging

  # ── PostgreSQL ───────────────────────────────────────────────────
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: orders_app
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./postgres/init.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    networks:
      - backend-net
    healthcheck:
      <<: *hc-defaults
      test: ["CMD-SHELL", "pg_isready -U orders_app -d orders"]
      start_period: 20s
    logging: *default-logging
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M

  # ── Redis ────────────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: >
      redis-server
      --maxmemory 128mb
      --maxmemory-policy allkeys-lru
      --requirepass-file /run/secrets/redis_password
    secrets:
      - redis_password
    networks:
      - backend-net
    healthcheck:
      <<: *hc-defaults
      test: ["CMD", "redis-cli", "ping"]
    logging: *default-logging

# ── Secrets (file-based; in production use Docker Swarm secrets or Vault) ──
secrets:
  jwt_secret:
    file: ./secrets/jwt_secret.txt
  db_password:
    file: ./secrets/db_password.txt
  redis_password:
    file: ./secrets/redis_password.txt

# ── Volumes ──────────────────────────────────────────────────────────
volumes:
  postgres-data:
    driver: local
  nginx-cache:
    driver: local

# ── Networks ─────────────────────────────────────────────────────────
networks:
  frontend-net:
    driver: bridge
  backend-net:
    driver: bridge
    internal: true    # no direct internet access for backend services
```

---

## NGINX Reverse Proxy Config

**nginx/nginx.conf** — key concepts explained
```nginx
events {
    worker_connections 1024;
}

http {
    upstream api_gateway {
        server api-gateway:3000;
        keepalive 32;
    }

    upstream auth_service {
        server auth-service:3001;
        keepalive 16;
    }

    # Rate limiting zones
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/m;
    limit_req_zone $binary_remote_addr zone=auth_limit:10m rate=10r/m;

    server {
        listen 80;
        server_name _;
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name api.example.com;

        ssl_certificate     /etc/nginx/certs/fullchain.pem;
        ssl_certificate_key /etc/nginx/certs/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;

        # Security headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy strict-origin-when-cross-origin always;

        location /auth/ {
            limit_req zone=auth_limit burst=5 nodelay;
            proxy_pass http://auth_service/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /api/ {
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://api_gateway/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 60s;
            proxy_connect_timeout 5s;
        }
    }
}
```

---

## Dev vs Production Override

**docker-compose.override.yml** (auto-loaded in dev)
```yaml
services:
  api-gateway:
    build:
      target: development
    environment:
      LOG_LEVEL: debug
    volumes:
      - ./api-gateway/src:/app/src   # live reload
    ports:
      - "3000:3000"   # expose directly for debugging

  postgres:
    ports:
      - "5432:5432"   # expose for local DB tools (DBeaver, etc)
```

**docker-compose.prod.yml** (explicit in production)
```yaml
services:
  api-gateway:
    image: ghcr.io/myorg/api-gateway:${IMAGE_TAG}
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
```

---

## Start Script

**scripts/start.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"
echo "Starting services in $ENV mode..."

mkdir -p secrets
if [[ ! -f secrets/jwt_secret.txt ]]; then
    openssl rand -hex 32 > secrets/jwt_secret.txt
    echo "Generated JWT secret"
fi
if [[ ! -f secrets/db_password.txt ]]; then
    openssl rand -hex 16 > secrets/db_password.txt
    echo "Generated DB password"
fi
if [[ ! -f secrets/redis_password.txt ]]; then
    openssl rand -hex 16 > secrets/redis_password.txt
    echo "Generated Redis password"
fi

if [[ "$ENV" == "prod" ]]; then
    docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
else
    docker compose up -d --build
fi

echo "Waiting for services to be healthy..."
timeout 120 bash -c 'until docker compose ps | grep -v "healthy\|Exit 0" | grep -v "^NAME" | wc -l | grep -q "^0$"; do sleep 3; done'

docker compose ps
echo "All services running!"
```

---

## Key Learning Points

### Networking Isolation
The `backend-net` is marked `internal: true` — backend services cannot initiate outbound internet connections. This is important: if a backend service is compromised, it cannot call out to attacker-controlled infrastructure.

### Secret Management
Secrets are mounted as files (`/run/secrets/name`) and read by services at runtime. They are NOT visible in environment variables, process listings, or `docker inspect` output (unlike `environment:` vars).

### Health Check Cascade
`depends_on` with `condition: service_healthy` ensures services start in dependency order and only after dependencies are truly ready — not just "running".

### YAML Anchors (`&anchor` / `*anchor`)
Reusable configuration blocks reduce duplication. The `x-` prefix is the Docker Compose convention for extension fields.

---

## Learning Outcomes
- [ ] Understand multi-network isolation and the `internal: true` flag
- [ ] Use Docker Compose secrets for sensitive values
- [ ] Chain health check dependencies correctly
- [ ] Write YAML anchors for reusable config
- [ ] Configure NGINX as a reverse proxy with upstream keepalive
- [ ] Separate dev and prod with override files
- [ ] Apply resource limits per service

## Interview Talking Points
> "I built a multi-service Docker Compose setup with proper network isolation — backend services can't reach the internet directly using `internal: true` networks. All secrets are injected as files, not environment variables, to avoid leaking in process listings. Health checks use `condition: service_healthy` to enforce startup order. NGINX handles SSL termination, rate limiting, and routes traffic to the correct upstream services."
