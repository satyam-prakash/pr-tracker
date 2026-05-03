#!/bin/bash
# ============================================================
# deploy-ai-agent.sh Ã¢â‚¬â€ Independent deployment for AI Agent
# ============================================================
set -e

SERVICE="ai-agent"
CONTAINER="pr-tracker-ai"
APP_DIR="/opt/pr-tracker"
HEALTH_URL="http://127.0.0.1:5001/health"
MAX_WAIT=90   # AI services may take longer to initialize

echo "Ã°Å¸Å¡â‚¬ [ai-agent] Starting deployment..."
cd $APP_DIR

PREV_IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER 2>/dev/null || echo "none")
echo "Ã°Å¸â€œÅ’ Previous image: $PREV_IMAGE"

echo "Ã¢Â¬â€¡Ã¯Â¸Â  Pulling new image..."
docker compose pull $SERVICE

echo "Ã°Å¸â€â€ž Replacing container..."
docker compose up -d --no-deps $SERVICE

echo "Ã¢ÂÂ³ Waiting for health check on $HEALTH_URL (90s max for AI init)..."
ELAPSED=0
until docker exec $CONTAINER wget --spider -q $HEALTH_URL > /dev/null 2>&1 || curl -sf $HEALTH_URL > /dev/null 2>&1; do
  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "Ã¢ÂÅ’ Health check failed Ã¢â‚¬â€ rolling back..."
    docker compose stop $SERVICE
    docker compose up -d --no-deps $SERVICE
    echo "Ã¢ÂÂª Rolled back to: $PREV_IMAGE"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "   ...waiting (${ELAPSED}s)"
done

echo "Ã¢Å“â€¦ [ai-agent] Deployed successfully at $(date)"

