# PR Tracker — Professional DevOps Guide (Part 2 of 3)
## CI/CD, Security, Secrets, Monitoring & Kubernetes

---

## 7. CI/CD WITH GITHUB ACTIONS

### Why CI/CD Matters
> **Concept**: Continuous Integration catches bugs before they reach production. Continuous Deployment ensures every green commit to `main` reaches users automatically, with zero manual steps.
>
> **Enterprise reality**: Teams at Stripe, Shopify merge 50+ times/day using this pattern. Each merge triggers automated builds, tests, security scans, and deployments.

### 7a. CI Pipeline — `.github/workflows/ci.yml`

```yaml
name: CI — Lint, Test & Build Check

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [develop]

jobs:
  # ── JOB 1: Lint & Type-check ─────────────────────
  lint:
    name: Lint All Services
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service:
          - pr-tracker-client
          - pr-tracker-service-router
          - pr-tracker-main-backend
          - pr-tracker-backend
          - pr-tracker-ai-agent
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
          cache-dependency-path: ${{ matrix.service }}/package-lock.json

      - name: Install dependencies
        working-directory: ${{ matrix.service }}
        run: npm ci

      - name: Run ESLint
        working-directory: ${{ matrix.service }}
        run: npm run lint --if-present

  # ── JOB 2: Docker Build Validation ───────────────
  docker-build:
    name: Validate Docker Builds
    runs-on: ubuntu-latest
    needs: lint
    strategy:
      matrix:
        service:
          - pr-tracker-client
          - pr-tracker-service-router
          - pr-tracker-main-backend
          - pr-tracker-backend
          - pr-tracker-ai-agent
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Docker image (no push)
        uses: docker/build-push-action@v5
        with:
          context: ./${{ matrix.service }}
          push: false
          cache-from: type=gha
          cache-to: type=gha,mode=max
          tags: pr-tracker/${{ matrix.service }}:ci-test

  # ── JOB 3: Security Scan ─────────────────────────
  security-scan:
    name: Trivy Security Scan
    runs-on: ubuntu-latest
    needs: docker-build
    steps:
      - uses: actions/checkout@v4

      - name: Build image for scanning
        run: docker build -t scan-target ./pr-tracker-main-backend

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: "scan-target"
          format: "table"
          exit-code: "1"          # Fail CI on HIGH/CRITICAL CVEs
          severity: "HIGH,CRITICAL"
```

### 7b. CD Pipeline — `.github/workflows/cd.yml`

```yaml
name: CD — Build, Push & Deploy

on:
  push:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_PREFIX: ghcr.io/${{ github.repository_owner }}/pr-tracker

jobs:
  build-and-push:
    name: Build & Push Images
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    strategy:
      matrix:
        include:
          - service: pr-tracker-client
            tag: client
          - service: pr-tracker-service-router
            tag: gateway
          - service: pr-tracker-main-backend
            tag: main-backend
          - service: pr-tracker-backend
            tag: auth
          - service: pr-tracker-ai-agent
            tag: ai-agent

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags, labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.IMAGE_PREFIX }}-${{ matrix.tag }}
          tags: |
            type=sha,prefix={{branch}}-
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./${{ matrix.service }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy:
    name: Deploy to Production VPS
    runs-on: ubuntu-latest
    needs: build-and-push
    environment: production   # Requires manual approval gate in GitHub UI

    steps:
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd /opt/pr-tracker
            # Pull latest images
            docker compose pull
            # Zero-downtime rolling restart
            docker compose up -d --no-deps --build
            # Remove old dangling images
            docker image prune -f
```

> **Interview insight**: "I tag images with the Git SHA (`main-abc1234`) so every running container is traceable to an exact commit. `latest` is also applied but I never rely on it in Kubernetes — always use the SHA tag for deterministic deployments."

---

## 8. SECURITY HARDENING

### 8a. Secrets Management

**WRONG (beginner):**
```yaml
# docker-compose.yml ❌
environment:
  - JWT_SECRET=mySuperSecret123
```

**RIGHT (professional):**
```bash
# 1. Never commit .env — add to .gitignore
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore

# 2. Provide .env.example (committed — shows structure, no values)
# .env.example
JWT_SECRET=
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
MISTRAL_API_KEY=
MONGO_ROOT_USER=
MONGO_ROOT_PASSWORD=
GITHUB_TOKEN=
CALLBACK_URL=
```

**For GitHub Actions (CI/CD secrets):**
- Store all secrets in `Settings → Secrets and variables → Actions`
- Reference as `${{ secrets.JWT_SECRET }}`
- Use `environment: production` for deployment secrets with manual approval

**For Enterprise (AWS Secrets Manager pattern):**
```bash
# Pull secrets at container startup, not baked in image
aws secretsmanager get-secret-value \
  --secret-id pr-tracker/production \
  --query SecretString \
  --output text | jq -r 'to_entries|.[]|"\(.key)=\(.value)"' > /tmp/.env

export $(cat /tmp/.env)
```

### 8b. Add `/health` Endpoint to Every Service

Every Node.js service needs this — Docker Compose and Kubernetes both depend on it:

```javascript
// Add to every Express service (src/index.js or server.js)
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    service: process.env.npm_package_name,
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  });
});
```

### 8c. Fix Auth Service — Remove nodemon from Production

```json
// pr-tracker-backend/package.json  — CURRENT (wrong)
"scripts": {
  "start": "nodemon server.js"   // ❌ nodemon in production!
}

// FIXED
"scripts": {
  "start": "node server.js",     // ✅ plain node for production
  "dev": "nodemon server.js"     // ✅ nodemon only for dev
},
"dependencies": {
  // remove nodemon from here
},
"devDependencies": {
  "nodemon": "^3.1.14"           // ✅ dev only
}
```

---

## 9. MONITORING STACK

### `docker-compose.monitoring.yml`

```yaml
# Usage: docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up

services:
  prometheus:
    image: prom/prometheus:v2.51.0
    container_name: pr-tracker-prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.retention.time=15d"
    ports:
      - "9090:9090"
    networks:
      - app-internal
      - monitoring
    restart: unless-stopped

  grafana:
    image: grafana/grafana:10.4.0
    container_name: pr-tracker-grafana
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ./monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
    ports:
      - "3001:3000"
    networks:
      - monitoring
    depends_on:
      - prometheus
    restart: unless-stopped

  loki:
    image: grafana/loki:2.9.0
    container_name: pr-tracker-loki
    volumes:
      - loki-data:/loki
    networks:
      - monitoring
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
  loki-data:

networks:
  monitoring:
    driver: bridge
```

### `monitoring/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "gateway"
    static_configs:
      - targets: ["service-router:5000"]
    metrics_path: /metrics

  - job_name: "main-backend"
    static_configs:
      - targets: ["main-backend:5002"]
    metrics_path: /metrics

  - job_name: "auth-service"
    static_configs:
      - targets: ["auth-service:5001"]
    metrics_path: /metrics

  - job_name: "ai-agent"
    static_configs:
      - targets: ["ai-agent:5003"]
    metrics_path: /metrics

  - job_name: "mongodb"
    static_configs:
      - targets: ["mongodb-exporter:9216"]
```

### Add Prometheus Metrics to Node Services

```bash
npm install prom-client
```

```javascript
// Add to each Express service
import client from 'prom-client';

const register = new client.Registry();
client.collectDefaultMetrics({ register });

// Custom metric: track AI analysis requests
const aiRequestDuration = new client.Histogram({
  name: 'ai_request_duration_seconds',
  help: 'Duration of AI analysis requests',
  labelNames: ['status'],
  registers: [register],
});

// Expose metrics endpoint (Prometheus scrapes this)
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.send(await register.metrics());
});
```

---

## 10. KUBERNETES DEPLOYMENT

> **Concept**: Docker Compose is great for single-server deployments. Kubernetes (K8s) is used when you need auto-scaling, self-healing, rolling deployments, and multi-node high availability. Used by Airbnb, Uber, Spotify in production.

### `k8s/namespace.yml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: pr-tracker
  labels:
    environment: production
```

### `k8s/secrets/app-secrets.yml`
```yaml
# In real enterprise: use Sealed Secrets or HashiCorp Vault
# Never store plaintext secrets in git
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: pr-tracker
type: Opaque
stringData:
  JWT_SECRET: "replace-at-deploy-time"
  GITHUB_CLIENT_ID: "replace-at-deploy-time"
  MISTRAL_API_KEY: "replace-at-deploy-time"
```

### `k8s/deployments/main-backend.yml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: main-backend
  namespace: pr-tracker
  labels:
    app: main-backend
spec:
  replicas: 2                  # 2 pods = high availability
  selector:
    matchLabels:
      app: main-backend
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1              # Bring up 1 new pod before killing old
      maxUnavailable: 0        # Never kill pod before new one is ready
  template:
    metadata:
      labels:
        app: main-backend
    spec:
      containers:
        - name: main-backend
          image: ghcr.io/yourname/pr-tracker-main-backend:main-abc1234
          ports:
            - containerPort: 5002
          env:
            - name: NODE_ENV
              value: production
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: JWT_SECRET
          # Resource limits — prevent one pod starving others
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "500m"
          # Kubernetes uses these to manage traffic
          readinessProbe:
            httpGet:
              path: /health
              port: 5002
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 5002
            initialDelaySeconds: 30
            periodSeconds: 15
            failureThreshold: 3   # Restart pod after 3 consecutive failures
```

### `k8s/deployments/hpa.yml` — Horizontal Pod Autoscaler
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: main-backend-hpa
  namespace: pr-tracker
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: main-backend
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70   # Scale up when CPU > 70%
```

> **Interview answer**: "The HPA watches CPU metrics from the metrics-server and automatically adds pods when load spikes. For the AI agent specifically, I'd configure it to scale based on custom queue-depth metrics since LLM calls are slow and expensive — each pod processes one request at a time."

### `k8s/services/main-backend-svc.yml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: main-backend-svc
  namespace: pr-tracker
spec:
  selector:
    app: main-backend
  ports:
    - port: 5002
      targetPort: 5002
  type: ClusterIP      # Internal only — Nginx ingress routes to this
```

### `k8s/ingress.yml`
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pr-tracker-ingress
  namespace: pr-tracker
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "30"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - pr-tracker.yourdomain.com
      secretName: pr-tracker-tls
  rules:
    - host: pr-tracker.yourdomain.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: gateway-svc
                port:
                  number: 5000
          - path: /
            pathType: Prefix
            backend:
              service:
                name: client-svc
                port:
                  number: 80
```
