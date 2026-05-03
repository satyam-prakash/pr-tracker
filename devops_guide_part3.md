# PR Tracker — Professional DevOps Guide (Part 3 of 3)
## Environments, Makefile, Mistakes, Resume Items & Rating

---

## 11. ENVIRONMENT STRATEGY

> **Concept**: Professional teams maintain separate, isolated environments. Code promotes through them: Dev → Staging → Production. Never test on production.

```
Dev (local)          Staging (cloud VM)       Production (cloud VM / K8s)
─────────────        ──────────────────       ────────────────────────────
docker-compose       docker-compose           Kubernetes / docker-compose
.env.local           .env.staging             Secrets Manager
Hot reload ON        Real data subset         Full monitoring
Debug logs           Smoke tests run          Alerts configured
MongoDB exposed      MongoDB internal only    MongoDB internal only
No rate limiting     Rate limiting ON         Rate limiting + WAF
```

**Implementation:**
```bash
# Run dev
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Run staging simulation
docker compose --env-file .env.staging up -d

# Run production
docker compose --env-file .env.production up -d
```

---

## 12. DEVELOPER MAKEFILE

> **Why**: A `Makefile` at the project root gives every developer (and your CI) a single interface to all commands. No one needs to remember long docker compose chains.

```makefile
# Makefile — place at d:\mernProject\Makefile

.PHONY: up down dev build push clean logs ps health

# ── Local Development ──────────────────────────────
dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

up:
	docker compose up -d

down:
	docker compose down

# ── Build all images ───────────────────────────────
build:
	docker compose build --parallel

# ── Push to registry ───────────────────────────────
push: build
	docker compose push

# ── Observability ──────────────────────────────────
monitor:
	docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

health:
	@for svc in gateway auth main-backend ai-agent; do \
		echo "--- $$svc ---"; \
		docker inspect --format='{{.State.Health.Status}}' pr-tracker-$$svc 2>/dev/null || echo "not running"; \
	done

# ── Cleanup ────────────────────────────────────────
clean:
	docker compose down -v --rmi local
	docker system prune -f

# ── Database ───────────────────────────────────────
mongo-shell:
	docker exec -it pr-tracker-mongo mongosh -u $${MONGO_ROOT_USER} -p $${MONGO_ROOT_PASSWORD}

backup:
	docker exec pr-tracker-mongo mongodump \
		--out /data/backup/$(shell date +%Y%m%d_%H%M%S) \
		--authenticationDatabase admin
```

**Usage:**
```bash
make dev          # Start everything with hot reload
make logs         # Tail all service logs
make health       # Check health of all containers
make mongo-shell  # Drop into MongoDB shell
make backup       # Take a database backup
```

---

## 13. COMMON BEGINNER MISTAKES (And How Professionals Fix Them)

### ❌ Mistake 1: Running as Root in Containers
**Beginner**: No USER directive in Dockerfile → runs as root
**Professional fix**:
```dockerfile
RUN addgroup -S app && adduser -S app -G app
USER app
```
**Why it matters**: CIS Benchmark control 4.1. If container is exploited, attacker gets root on host.

---

### ❌ Mistake 2: Storing Secrets in Environment Variables Directly
**Beginner**: `JWT_SECRET=abc123` hardcoded in docker-compose or pushed to git
**Professional fix**: `.env.example` committed, `.env` in `.gitignore`, secrets in GitHub Actions secrets or AWS Secrets Manager

---

### ❌ Mistake 3: No Health Checks
**Beginner**: `depends_on: mongodb` doesn't wait for MongoDB to be *ready*, just for the container to *start*
**Professional fix**: `condition: service_healthy` + `healthcheck` using `mongosh --eval "db.adminCommand('ping')"`

---

### ❌ Mistake 4: Exposing Internal Ports Publicly
**Beginner**: Mapping `27017:27017` for MongoDB in production
**Professional fix**: Only Nginx gets host ports (80, 443). All other services communicate on internal Docker network only.

---

### ❌ Mistake 5: Single-Stage Dockerfiles for Frontend
**Beginner**: 350MB Node.js image serving React HTML files
**Professional fix**: Multi-stage build → 25MB Nginx image. Node.js is only used to compile, never ships.

---

### ❌ Mistake 6: `latest` Tag in Kubernetes
**Beginner**: `image: my-service:latest` in K8s manifests
**Professional fix**: Always use SHA tags (`image: my-service:main-a3f9c21`) for deterministic, rollback-able deployments.

---

### ❌ Mistake 7: No Resource Limits in Kubernetes
**Beginner**: Pod can consume unlimited CPU/RAM and starve other pods
**Professional fix**: Always set `resources.requests` and `resources.limits` for every container.

---

### ❌ Mistake 8: nodemon in Production
**Beginner**: `"start": "nodemon server.js"` in production scripts
**Professional fix**: `"start": "node server.js"` in production. nodemon watches files, restarts on change — wasteful and risky in containers.

---

### ❌ Mistake 9: No `.dockerignore`
**Beginner**: `node_modules`, `.env`, `.git` all get sent to Docker build context
**Professional fix**:
```
# .dockerignore (every service)
node_modules
.env
.env.*
.git
*.log
coverage/
.nyc_output
README.md
```

---

### ❌ Mistake 10: Using HTTP in Production
**Beginner**: Deploying on port 80 with no SSL
**Professional fix**: Nginx with Let's Encrypt (certbot). All HTTP redirects to HTTPS. TLS 1.2+ only.

---

## 14. RESUME-WORTHY FEATURES TO IMPLEMENT

Listed in priority order for maximum recruiter impact:

| Priority | Feature | Skill Demonstrated |
|---|---|---|
| 🔴 1 | Multi-stage Dockerfiles for all services | Docker optimization |
| 🔴 2 | Root-level `docker-compose.yml` | Microservices orchestration |
| 🔴 3 | GitHub Actions CI pipeline | CI/CD automation |
| 🔴 4 | Nginx reverse proxy with SSL | Production networking |
| 🟡 5 | Health check endpoints on all services | Reliability engineering |
| 🟡 6 | GitHub Actions CD pipeline | GitOps workflow |
| 🟡 7 | Prometheus + Grafana monitoring stack | Observability |
| 🟡 8 | `.env.example` + secrets in GitHub Actions | Security practices |
| 🟢 9 | Kubernetes deployment manifests (YAML) | Container orchestration |
| 🟢 10 | HorizontalPodAutoscaler | Auto-scaling |
| 🟢 11 | `docker-compose.dev.yml` with volume mounts | Dev/prod parity |
| 🟢 12 | Makefile for developer experience | DevOps culture |
| ⚪ 13 | Terraform for VPS provisioning | Infrastructure as Code |
| ⚪ 14 | ELK stack (Elasticsearch + Logstash + Kibana) | Enterprise logging |

---

## 15. INTERVIEW-LEVEL EXPLANATIONS

**Q: Why do you have 5 separate backend services instead of one?**
> "This is the microservices pattern. Each service owns one domain — auth, data, AI, routing — and can be scaled, deployed, and updated independently. If the AI agent has an outage, auth and data still work. In a monolith, one crash takes everything down. The tradeoff is operational complexity, which we manage with Docker Compose and Kubernetes."

**Q: Why use an API Gateway instead of the frontend calling services directly?**
> "The gateway (`service-router`) is the single entry point. It handles cross-cutting concerns: authentication validation, request routing, rate limiting policy, and logging. Without it, I'd duplicate auth middleware in every service. It also means I can change internal service topology without updating the frontend."

**Q: How do your containers communicate with each other?**
> "Docker Compose creates a private bridge network. Each service is reachable by its service name as a hostname — `mongodb`, `auth-service`, etc. Docker's embedded DNS resolves these. No ports are exposed to the internet except 80 and 443 on Nginx."

**Q: How would you handle a zero-downtime deployment?**
> "In Docker Compose: `docker compose up -d --no-deps service-name` updates one service without touching others. In Kubernetes: the `RollingUpdate` strategy with `maxUnavailable: 0` ensures new pods pass their readiness probe before old pods are terminated."

**Q: What is the difference between liveness and readiness probes?**
> "A readiness probe says 'I'm ready to receive traffic.' A liveness probe says 'I'm alive — don't restart me.' If readiness fails, K8s removes the pod from the load balancer but doesn't restart it. If liveness fails 3 times, K8s restarts the container. My Node services might be alive but not ready if the database connection hasn't been established yet — that's when readiness probe saves you from 502 errors."

---

## 16. FINAL RATING & UPGRADE ROADMAP

### Current Level: **Intermediate** ⭐⭐⭐☆☆

**Evidence for Intermediate**:
- Real microservices separation (5 services) ✅
- Individual Dockerfiles per service ✅
- `node:20-alpine` base image ✅
- `npm ci --omit=dev` ✅
- `.dockerignore` per service ✅

---

### To reach **Advanced** ⭐⭐⭐⭐☆ — Do these in order:

```
Week 1:
  ✅ Fix auth service nodemon in production
  ✅ Add /health endpoint to every service
  ✅ Convert all Dockerfiles to multi-stage builds
  ✅ Create root docker-compose.yml with all services
  ✅ Create docker-compose.dev.yml with volume mounts
  ✅ Add .env.example, remove .env from git

Week 2:
  ✅ Add Nginx reverse proxy container
  ✅ Configure Nginx for routing + rate limiting
  ✅ Set up GitHub Actions CI pipeline
  ✅ Add Trivy security scanning to CI
  ✅ Add Makefile

Week 3:
  ✅ GitHub Actions CD pipeline (push to GHCR)
  ✅ Deploy to a VPS (DigitalOcean $6/mo Droplet)
  ✅ Add Let's Encrypt SSL via certbot
  ✅ Add Prometheus + Grafana monitoring
```

---

### To reach **Professional Production-Level** ⭐⭐⭐⭐⭐ — Add these:

```
Month 2:
  ✅ Kubernetes manifests for all services
  ✅ HorizontalPodAutoscaler for main-backend and ai-agent
  ✅ GitHub Actions CD deploys to K8s cluster (kubectl apply)
  ✅ Sealed Secrets or HashiCorp Vault for secrets
  ✅ Terraform to provision VPS / K8s cluster

Month 3:
  ✅ ELK or Loki for centralized log aggregation
  ✅ Grafana alerting (Slack/email on error spike)
  ✅ MongoDB replica set (not single node)
  ✅ Automated database backup with retention policy
  ✅ Disaster recovery runbook (written documentation)
```

---

## 17. THE ONE-LINE RESUME DESCRIPTION

Once you implement the Week 1-3 items, you can honestly write:

> *"Built and deployed a microservices PR tracking system (5 Node.js services + React frontend) using Docker multi-stage builds, Nginx reverse proxy with SSL, GitHub Actions CI/CD pipeline with Trivy security scanning, and Prometheus/Grafana observability stack."*

That sentence alone will get you past 90% of DevOps screening calls.
