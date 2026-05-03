#!/bin/bash
# ============================================================
# deploy-client.sh Ã¢â‚¬â€ Independent deployment for React Client
# Usage: bash deploy/deploy-client.sh <image-tag>
# Called by GitHub Actions CD job
# ============================================================
set -e

SERVICE="client"
CONTAINER="pr-tracker-client"
IMAGE_TAG="${1:-latest}"
APP_DIR="/opt/pr-tracker"
HEALTH_URL="http://127.0.0.1:80"
MAX_WAIT=60   # seconds to wait for health

echo "Ã°Å¸Å¡â‚¬ [$SERVICE] Starting deployment Ã¢â‚¬â€ image tag: $IMAGE_TAG"
cd $APP_DIR

# Ã¢â€â‚¬Ã¢â€â‚¬ Step 1: Save the current image tag (for rollback) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
PREV_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER 2>/dev/null || echo "none")
echo "Ã°Å¸â€œÅ’ Previous image: $PREV_IMAGE"

# Ã¢â€â‚¬Ã¢â€â‚¬ Step 2: Pull the new image Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
echo "Ã¢Â¬â€¡Ã¯Â¸Â  Pulling new image..."
docker compose pull $SERVICE

# Ã¢â€â‚¬Ã¢â€â‚¬ Step 3: Start new container (no-deps = only this service) Ã¢â€â‚¬
echo "Ã°Å¸â€â€ž Replacing container..."
docker compose up -d --no-deps $SERVICE

# Ã¢â€â‚¬Ã¢â€â‚¬ Step 4: Health check loop Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
echo "Ã¢ÂÂ³ Waiting for health check..."
ELAPSED=0
until docker exec $CONTAINER wget --spider -q $HEALTH_URL > /dev/null 2>&1 || curl -sf $HEALTH_URL > /dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "Ã¢ÂÅ’ Health check failed after ${MAX_WAIT}s Ã¢â‚¬â€ rolling back..."
    docker compose stop $SERVICE
    docker tag "$PREV_IMAGE" mernproject-$SERVICE:rollback 2>/dev/null || true
    docker compose up -d --no-deps $SERVICE
    echo "Ã¢ÂÂª Rolled back to: $PREV_IMAGE"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "   ...waiting (${ELAPSED}s)"
done

# Ã¢â€â‚¬Ã¢â€â‚¬ Step 5: Cleanup old images Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

echo "Ã¢Å“â€¦ [$SERVICE] Deployed successfully at $(date)"

