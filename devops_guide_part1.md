# PR Tracker — Professional DevOps Guide (Part 1 of 3)
## Project Assessment, Architecture, Docker & Compose

---

## CURRENT PROJECT RATING: **Intermediate**

Your project already demonstrates **real microservices thinking**. You have 5 distinct services:
- `pr-tracker-client` — React/Vite frontend
- `pr-tracker-service-router` — API Gateway (port 5000)
- `pr-tracker-main-backend` — Core business logic (port 5002)
- `pr-tracker-backend` — Auth service (Passport + GitHub OAuth)
- `pr-tracker-ai-agent` — Mistral AI integration
- `pr-tracker-mongodb` — Database layer

**What you already do right:**
- Separated concerns into individual services ✅
- Each service has its own `Dockerfile` ✅
- Using `node:20-alpine` (small base image) ✅
- Using `npm ci --omit=dev` (no dev deps in image) ✅
- `.dockerignore` files present ✅

**What is missing (the gap to Professional level):**
- Single-stage Dockerfiles (no multi-stage builds) ❌
- No `docker-compose.yml` at the root level ❌
- No health checks defined ❌
- No Nginx reverse proxy ❌
- No CI/CD pipeline ❌
- No secrets management ❌
- No monitoring stack ❌
- No Kubernetes manifests ❌
- `nodemon` in production dependencies (auth service) ❌
- `.env` files committed (critical security risk) ❌

---

## 1. PRODUCTION-GRADE ARCHITECTURE DIAGRAM

```
                        ┌─────────────────────────────────────────┐
                        │           INTERNET / CLIENT              │
                        └──────────────┬──────────────────────────┘
                                       │ HTTPS :443
                        ┌─────────────▼──────────────────────────┐
                        │         NGINX REVERSE PROXY             │
                        │   (SSL termination, Rate Limiting,      │
                        │    Static file serving, Load Balancing) │
                        └──────┬──────────┬───────────────────────┘
                               │          │
               ┌───────────────▼──┐   ┌───▼────────────────────┐
               │  React Frontend  │   │   API Gateway           │
               │  (Static Files   │   │   pr-tracker-service-   │
               │   served by Nginx│   │   router :5000          │
               └──────────────────┘   └──┬──────────┬───────────┘
                                         │          │
                    ┌────────────────────▼──┐  ┌────▼──────────────────┐
                    │  Auth Service         │  │  Main Backend          │
                    │  pr-tracker-backend   │  │  pr-tracker-main-      │
                    │  :5001                │  │  backend :5002         │
                    └─────────┬─────────────┘  └────┬──────────────────┘
                              │                     │
                    ┌─────────▼─────────────────────▼──────────┐
                    │              MongoDB                       │
                    │         pr-tracker-mongodb :27017          │
                    │         (Persistent Named Volume)          │
                    └───────────────────────────────────────────┘
                                         │
                    ┌────────────────────▼──────────────────────┐
                    │           AI Agent Service                 │
                    │       pr-tracker-ai-agent :5003            │
                    │       (Mistral API — external call)        │
                    └───────────────────────────────────────────┘

MONITORING STACK (separate compose network):
  ┌─────────────────────────────────────────────┐
  │  Prometheus :9090 → scrapes /metrics        │
  │  Grafana :3000    → dashboards              │
  │  Loki              → log aggregation        │
  └─────────────────────────────────────────────┘
```

---

## 2. PROFESSIONAL FOLDER STRUCTURE

```
mernProject/                          ← Monorepo root
├── .github/
│   └── workflows/
│       ├── ci.yml                    ← PR checks (lint, test, build)
│       └── cd.yml                    ← Deploy on merge to main
├── nginx/
│   ├── nginx.conf                    ← Production Nginx config
│   └── conf.d/
│       └── pr-tracker.conf           ← Virtual host config
├── monitoring/
│   ├── prometheus.yml                ← Scrape config
│   └── grafana/
│       └── dashboards/
│           └── services.json         ← Pre-built dashboard
├── k8s/                              ← Kubernetes manifests
│   ├── namespace.yml
│   ├── configmaps/
│   ├── secrets/
│   ├── deployments/
│   └── services/
├── pr-tracker-client/
│   ├── Dockerfile                    ← Multi-stage build
│   └── ...
├── pr-tracker-service-router/
│   ├── Dockerfile                    ← Multi-stage build
│   └── ...
├── pr-tracker-main-backend/
│   ├── Dockerfile                    ← Multi-stage build
│   └── ...
├── pr-tracker-backend/
│   ├── Dockerfile                    ← Multi-stage build
│   └── ...
├── pr-tracker-ai-agent/
│   ├── Dockerfile                    ← Multi-stage build
│   └── ...
├── docker-compose.yml                ← Full stack (prod)
├── docker-compose.dev.yml            ← Dev overrides (hot reload)
├── docker-compose.monitoring.yml     ← Observability stack
├── .env.example                      ← Template (committed)
├── .gitignore                        ← Ignores all .env files
└── Makefile                          ← Developer shortcuts
```

---

## 3. MULTI-STAGE DOCKERFILES

### Why Multi-Stage Builds Matter
> **Concept**: Build-time dependencies (compilers, test runners, dev tools) never ship in the final image. A React app compiled with Node produces only static HTML/CSS/JS — the final image needs only Nginx.
>
> **Enterprise use**: Google, Netflix ship images under 50MB this way. Your current Node images are ~200MB+.

### 3a. Frontend — React/Vite (Multi-Stage)

```dockerfile
# pr-tracker-client/Dockerfile

# ── Stage 1: Builder ─────────────────────────────────
FROM node:20-alpine AS builder
LABEL stage=builder

WORKDIR /app

# Copy manifests first — Docker cache layer optimization
# If package.json didn't change, npm ci is skipped entirely
COPY package*.json ./
RUN npm ci

# Copy source and build
COPY . .
RUN npm run build
# Output: /app/dist (static files only)

# ── Stage 2: Production ──────────────────────────────
FROM nginx:1.27-alpine AS production

# Remove default nginx page
RUN rm -rf /usr/share/nginx/html/*

# Copy ONLY the compiled static files from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy custom nginx config for SPA routing
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# Use nginx in foreground (required for Docker)
CMD ["nginx", "-g", "daemon off;"]
```

**nginx.conf (inside pr-tracker-client/):**
```nginx
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # SPA fallback — send all routes to index.html
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets aggressively
    location ~* \.(js|css|png|jpg|svg|ico|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

**Result**: Final image is ~25MB (was ~350MB). **14x reduction.**

---

### 3b. Node.js Services — Multi-Stage

```dockerfile
# pr-tracker-main-backend/Dockerfile  (same pattern for all Node services)

# ── Stage 1: Dependencies ────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
# ci = reproducible installs; --omit=dev = no devDeps
RUN npm ci --omit=dev

# ── Stage 2: Production Image ────────────────────────
FROM node:20-alpine AS production

# Security: never run as root in production
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only production node_modules from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY --chown=appuser:appgroup . .

# Drop to non-root user
USER appuser

EXPOSE 5002

# Prefer explicit node over npm start — cleaner signal handling
CMD ["node", "src/index.js"]
```

> **Interview answer**: "I use a non-root user because containers running as root, if exploited, gain root on the host. Every CIS Docker benchmark mandates this. The `--chown` flag ensures file permissions are correct for the new user."

---

## 4. DOCKER COMPOSE — PRODUCTION ARCHITECTURE

```yaml
# docker-compose.yml (root of monorepo)

version: "3.9"

networks:
  # Internal network — services communicate here, never exposed
  app-internal:
    driver: bridge
  # Monitoring network — separate for security isolation
  monitoring:
    driver: bridge

volumes:
  mongo-data:
    driver: local
  mongo-logs:
    driver: local

services:

  # ── NGINX REVERSE PROXY ─────────────────────────────
  nginx:
    image: nginx:1.27-alpine
    container_name: pr-tracker-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    depends_on:
      - client
      - service-router
    networks:
      - app-internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ── REACT FRONTEND ──────────────────────────────────
  client:
    build:
      context: ./pr-tracker-client
      dockerfile: Dockerfile
      target: production          # Multi-stage target
    container_name: pr-tracker-client
    networks:
      - app-internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:80"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ── API GATEWAY ─────────────────────────────────────
  service-router:
    build:
      context: ./pr-tracker-service-router
      dockerfile: Dockerfile
      target: production
    container_name: pr-tracker-gateway
    environment:
      - NODE_ENV=production
      - PORT=5000
      # Use Docker service names as hostnames — internal DNS
      - AUTH_SERVICE_URL=http://auth-service:5001
      - MAIN_SERVICE_URL=http://main-backend:5002
      - AI_SERVICE_URL=http://ai-agent:5003
    networks:
      - app-internal
    depends_on:
      auth-service:
        condition: service_healthy
      main-backend:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5000/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ── AUTH SERVICE ────────────────────────────────────
  auth-service:
    build:
      context: ./pr-tracker-backend
      dockerfile: Dockerfile
      target: production
    container_name: pr-tracker-auth
    environment:
      - NODE_ENV=production
      - PORT=5001
      - MONGO_URI=mongodb://mongodb:27017/pr-tracker
      # Secrets loaded from .env file (never hardcoded)
      - JWT_SECRET=${JWT_SECRET}
      - GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID}
      - GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET}
      - CALLBACK_URL=${CALLBACK_URL}
    networks:
      - app-internal
    depends_on:
      mongodb:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5001/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ── MAIN BACKEND ─────────────────────────────────────
  main-backend:
    build:
      context: ./pr-tracker-main-backend
      dockerfile: Dockerfile
      target: production
    container_name: pr-tracker-main
    environment:
      - NODE_ENV=production
      - PORT=5002
      - MONGO_URI=mongodb://mongodb:27017/pr-tracker
      - JWT_SECRET=${JWT_SECRET}
      - GITHUB_TOKEN=${GITHUB_TOKEN}
    networks:
      - app-internal
    depends_on:
      mongodb:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5002/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ── AI AGENT ─────────────────────────────────────────
  ai-agent:
    build:
      context: ./pr-tracker-ai-agent
      dockerfile: Dockerfile
      target: production
    container_name: pr-tracker-ai
    environment:
      - NODE_ENV=production
      - PORT=5003
      - MISTRAL_API_KEY=${MISTRAL_API_KEY}
    networks:
      - app-internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5003/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # ── MONGODB ───────────────────────────────────────────
  mongodb:
    image: mongo:7.0
    container_name: pr-tracker-mongo
    environment:
      - MONGO_INITDB_ROOT_USERNAME=${MONGO_ROOT_USER}
      - MONGO_INITDB_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}
      - MONGO_INITDB_DATABASE=pr-tracker
    volumes:
      - mongo-data:/data/db
      - mongo-logs:/var/log/mongodb
    networks:
      - app-internal
    # Never expose MongoDB port publicly in production
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 40s
```

> **Key interview point**: "Services communicate using Docker's internal DNS — `mongodb` resolves to the MongoDB container's IP automatically. I never expose MongoDB's port 27017 to the host. The only public-facing ports are 80 and 443 on Nginx."

---

## 5. DOCKER COMPOSE — DEV OVERRIDES

```yaml
# docker-compose.dev.yml
# Usage: docker compose -f docker-compose.yml -f docker-compose.dev.yml up

services:
  client:
    build:
      target: builder        # Use builder stage (has node_modules for Vite HMR)
    volumes:
      - ./pr-tracker-client/src:/app/src   # Hot reload
    ports:
      - "5173:5173"          # Expose Vite dev server directly
    command: npm run dev -- --host

  main-backend:
    volumes:
      - ./pr-tracker-main-backend/src:/app/src
    environment:
      - NODE_ENV=development
    command: npm run dev     # nodemon with hot reload

  auth-service:
    volumes:
      - ./pr-tracker-backend/src:/app/src
    environment:
      - NODE_ENV=development

  mongodb:
    ports:
      - "27017:27017"        # Expose for local MongoDB Compass in dev only
```

---

## 6. NGINX PRODUCTION CONFIG

```nginx
# nginx/nginx.conf

worker_processes auto;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    add_header Content-Security-Policy "default-src 'self';";

    # Rate limiting — prevent brute force / DDoS
    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;

    # Gzip compression
    gzip on;
    gzip_types text/plain application/json application/javascript text/css;

    # Hide Nginx version from attackers
    server_tokens off;

    server {
        listen 443 ssl http2;
        server_name your-domain.com;

        ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;

        # Frontend — serve static files
        location / {
            proxy_pass http://client:80;
        }

        # API Gateway — rate limited
        location /api/ {
            limit_req zone=api burst=10 nodelay;
            proxy_pass http://service-router:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Auth endpoints — stricter rate limit
        location /api/auth/ {
            limit_req zone=auth burst=3 nodelay;
            proxy_pass http://service-router:5000;
        }
    }

    # Redirect HTTP to HTTPS
    server {
        listen 80;
        server_name your-domain.com;
        return 301 https://$host$request_uri;
    }
}
```

> **Why this matters**: Nginx does SSL termination, so your Node services never deal with TLS certificates. Rate limiting prevents credential stuffing attacks on `/api/auth/`. `server_tokens off` hides Nginx version from `curl -I` fingerprinting.
