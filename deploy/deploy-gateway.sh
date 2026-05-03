#!/bin/bash
# ============================================================
# deploy-gateway.sh — Independent deployment for API Gateway
# ============================================================
set -e

SERVICE="service-router"
CONTAINER="pr-tracker-gateway"
APP_DIR="/opt/pr-tracker"
HEALTH_URL="http://localhost:5003/health"
MAX_WAIT=60

echo "🚀 [gateway] Starting deployment..."
cd $APP_DIR

PREV_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER 2>/dev/null || echo "none")
echo "📌 Previous image: $PREV_IMAGE"

echo "⬇️  Pulling new image..."
docker compose pull $SERVICE

echo "🔄 Replacing container..."
docker compose up -d --no-deps $SERVICE

echo "⏳ Waiting for health check on $HEALTH_URL..."
ELAPSED=0
until docker exec $CONTAINER wget --spider -q $HEALTH_URL > /dev/null 2>&1 || curl -sf $HEALTH_URL > /dev/null 2>&1; do
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
echo "✅ [gateway] Deployed successfully at $(date)"

