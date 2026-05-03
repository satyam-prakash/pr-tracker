#!/bin/bash
# ============================================================
# deploy-client.sh â€” Independent deployment for React Client
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

echo "ðŸš€ [$SERVICE] Starting deployment â€” image tag: $IMAGE_TAG"
cd $APP_DIR

# â”€â”€ Step 1: Save the current image tag (for rollback) â”€â”€â”€â”€â”€â”€â”€â”€
PREV_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER 2>/dev/null || echo "none")
echo "ðŸ“Œ Previous image: $PREV_IMAGE"

# â”€â”€ Step 2: Pull the new image â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "â¬‡ï¸  Pulling new image..."
docker compose pull $SERVICE

# â”€â”€ Step 3: Start new container (no-deps = only this service) â”€
echo "ðŸ”„ Replacing container..."
docker compose up -d --no-deps $SERVICE

# â”€â”€ Step 4: Health check loop â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
echo "â³ Waiting for health check..."
ELAPSED=0
until docker exec $CONTAINER wget --spider -q $HEALTH_URL > /dev/null 2>&1 || curl -sf $HEALTH_URL > /dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "âŒ Health check failed after ${MAX_WAIT}s â€” rolling back..."
    docker compose stop $SERVICE
    docker tag "$PREV_IMAGE" mernproject-$SERVICE:rollback 2>/dev/null || true
    docker compose up -d --no-deps $SERVICE
    echo "âª Rolled back to: $PREV_IMAGE"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "   ...waiting (${ELAPSED}s)"
done

# â”€â”€ Step 5: Cleanup old images â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
docker image prune -f

echo "âœ… [$SERVICE] Deployed successfully at $(date)"

