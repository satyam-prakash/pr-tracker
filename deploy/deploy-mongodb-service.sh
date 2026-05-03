#!/bin/bash
# ============================================================
# deploy-mongodb-service.sh — Independent deployment for MongoDB Service
# ============================================================
set -e

SERVICE="mongodb-service"
CONTAINER="pr-tracker-mongodb"
APP_DIR="/opt/pr-tracker"
HEALTH_URL="http://localhost:5004/health"
MAX_WAIT=90   # DB service needs time to connect to Atlas

echo "🚀 [mongodb-service] Starting deployment..."
cd $APP_DIR

PREV_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER 2>/dev/null || echo "none")
echo "📌 Previous image: $PREV_IMAGE"

echo "⬇️  Pulling new image..."
docker compose pull $SERVICE

echo "🔄 Replacing container..."
docker compose up -d --no-deps $SERVICE

echo "⏳ Waiting for health check on $HEALTH_URL..."
ELAPSED=0
until curl -sf $HEALTH_URL > /dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ Health check failed — rolling back..."
    docker compose stop $SERVICE
    docker compose up -d --no-deps $SERVICE
    echo "⏪ Rolled back to: $PREV_IMAGE"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "   ...waiting (${ELAPSED}s)"
done

docker image prune -f
echo "✅ [mongodb-service] Deployed successfully at $(date)"
