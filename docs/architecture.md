# PR Tracker — Architecture

## Overview

PR Tracker is a full-stack GitHub pull request management platform built with a microservices architecture. It tracks PRs across multiple repositories, provides AI-powered analysis, and exposes an observability stack for operational visibility.

---

## System Architecture

```
USER ─ HTTPS ──► Route53
                    │
              CloudFront (CDN)
              ├── /assets/* → S3 (Vite build output)
              └── /* → ALB

              ALB + WAF (SSL termination, DDoS protection)
                    │
              Traefik (Reverse Proxy)
              ├── prtracker.dev      → frontend:80
              ├── api.prtracker.dev  → api-gateway:5003
              └── monitor.prtracker.dev → grafana:3000
                    │
        ┌───────────┴───────────┐
     frontend              api-gateway (port 5003)
     (Nginx, React)        JWT cookie validation
                           Rate limiting (3 tiers)
                           Prometheus metrics
                                │
              ┌────────┬────────┼────────┐
         github-svc  pr-svc  analytics  ai-agent
          :5001      :5002    :5004      :5001
              │
         Data Layer
         ├── MongoDB Atlas (replica set)
         └── Redis (session + OAuth state)

         Poller Worker (CronJob, every 1h)
         └── Syncs all tracked repos → core backend
```

---

## Services

| Service | Port | Image | Purpose |
|---|---|---|---|
| `nginx` | 80 | nginx:1.27-alpine | Entry-point reverse proxy |
| `client` | 80 | pr-tracker-client | React 19 + Vite SPA (Nginx) |
| `service-router` | 5003 | pr-tracker-gateway | API Gateway — auth, rate-limit, routing |
| `auth-service` | 5005 | pr-tracker-auth | GitHub OAuth, JWT issuance |
| `main-backend` | 5002 | pr-tracker-main-backend | Core — repos, PRs, webhooks |
| `ai-agent` | 5001 | pr-tracker-ai-agent | LLM-powered PR analysis (Mistral) |
| `mongodb-service` | 5004 | pr-tracker-mongodb-service | Data access layer |
| `poller` | — | pr-tracker-poller | CronJob — hourly repo sync |

---

## Key Architectural Decisions

| # | Decision | ADR |
|---|---|---|
| 1 | Polling moved server-side | [ADR 001](ADR/001-server-side-polling.md) |

---

## Data Flow

### PR Sync (server-side)
1. Kubernetes CronJob fires `pr-poller` every hour.
2. Poller calls `GET /api/repos/all` on `main-backend`.
3. For each repo, poller calls `POST /api/prs/sync`.
4. `main-backend` fetches PRs from GitHub API and upserts into MongoDB.

### PR View (user request)
1. User opens React app → fetches `GET /api/repos` via `api-gateway`.
2. Gateway validates JWT cookie → forwards to `main-backend`.
3. `main-backend` reads from MongoDB → returns PR list.
4. User clicks "Analyze" → gateway applies AI rate limit → forwards to `ai-agent`.

---

## Observability

| Tool | Purpose | URL (local) |
|---|---|---|
| Prometheus | Metrics scraping + alerting | http://localhost:9090 |
| Grafana | Dashboards | http://localhost:3001 |

### Key metrics
- `http_requests_total` — labelled by method, route, status
- `http_request_duration_seconds` — p50/p95/p99 latency
- `github_rate_limit_remaining` — GitHub API headroom

---

## Local development

```bash
cp .env.example .env
# Fill in MONGO_URI, GITHUB_CLIENT_ID, GITHUB_CLIENT_SECRET, JWT_SECRET, MISTRAL_API_KEY

make up          # Start all 8 services
make monitor     # Add Prometheus + Grafana
make health      # Check container health statuses
make logs        # Tail all logs
make poller-run  # Trigger an immediate one-off poll
```

---

## CI/CD

Three GitHub Actions workflows:
- **`ci-cd.yml`** — Lint + test on PRs; build + push + deploy on main.
- **`dependency-audit.yml`** — Weekly npm audit auto-PRs.
- **`cleanup-images.yml`** — Weekly GHCR image pruning (keeps 5 most recent).
