#!/bin/bash
# ============================================================
# deploy-client.sh — Independent deployment for React Client
# Usage: bash deploy/deploy-client.sh <image-tag>
# Called by GitHub Actions CD job
# ============================================================
set -e

SERVICE="client"
CONTAINER="pr-tracker-client"
IMAGE_TAG="${1:-latest}"
APP_DIR="/opt/pr-tracker"
HEALTH_URL="http://localhost:80"
MAX_WAIT=60   # seconds to wait for health

echo "🚀 [$SERVICE] Starting deployment — image tag: $IMAGE_TAG"
cd $APP_DIR

# ── Step 1: Save the current image tag (for rollback) ────────
PREV_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER 2>/dev/null || echo "none")
echo "📌 Previous image: $PREV_IMAGE"

# ── Step 2: Pull the new image ────────────────────────────────
echo "⬇️  Pulling new image..."
docker compose pull $SERVICE

# ── Step 3: Start new container (no-deps = only this service) ─
echo "🔄 Replacing container..."
docker compose up -d --no-deps $SERVICE

# ── Step 4: Health check loop ─────────────────────────────────
echo "⏳ Waiting for health check..."
ELAPSED=0
until docker exec $CONTAINER wget --spider -q $HEALTH_URL > /dev/null 2>&1 || curl -sf $HEALTH_URL > /dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ Health check failed after ${MAX_WAIT}s — rolling back..."
    docker compose stop $SERVICE
    docker tag "$PREV_IMAGE" mernproject-$SERVICE:rollback 2>/dev/null || true
    docker compose up -d --no-deps $SERVICE
    echo "⏪ Rolled back to: $PREV_IMAGE"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "   ...waiting (${ELAPSED}s)"
done

# ── Step 5: Cleanup old images ────────────────────────────────
docker image prune -f

echo "✅ [$SERVICE] Deployed successfully at $(date)"

