#!/bin/bash
# ============================================================
# deploy-mongodb-service.sh â€” Independent deployment for MongoDB Service
# ============================================================
set -e

SERVICE="mongodb-service"
CONTAINER="pr-tracker-mongodb"
APP_DIR="/opt/pr-tracker"
HEALTH_URL="http://127.0.0.1:5004/health"
MAX_WAIT=90   # DB service needs time to connect to Atlas

echo "ðŸš€ [mongodb-service] Starting deployment..."
cd $APP_DIR

PREV_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER 2>/dev/null || echo "none")
echo "ðŸ“Œ Previous image: $PREV_IMAGE"

echo "â¬‡ï¸  Pulling new image..."
docker compose pull $SERVICE

echo "ðŸ”„ Replacing container..."
docker compose up -d --no-deps $SERVICE

echo "â³ Waiting for health check on $HEALTH_URL..."
ELAPSED=0
until docker exec $CONTAINER wget --spider -q $HEALTH_URL > /dev/null 2>&1 || curl -sf $HEALTH_URL > /dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "âŒ Health check failed â€” rolling back..."
    docker compose stop $SERVICE
    docker compose up -d --no-deps $SERVICE
    echo "âª Rolled back to: $PREV_IMAGE"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "   ...waiting (${ELAPSED}s)"
done

docker image prune -f
echo "âœ… [mongodb-service] Deployed successfully at $(date)"

