.PHONY: up down dev build logs ps health clean mongo-shell monitor

# ── Production ────────────────────────────────────────────────────
up:
	docker compose up -d

down:
	docker compose down

build:
	docker compose build --parallel

# ── Development (hot reload) ──────────────────────────────────────
dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

# ── Monitoring stack ──────────────────────────────────────────────
monitor:
	docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# ── Observability ─────────────────────────────────────────────────
logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

health:
	@echo "--- gateway ---"    && docker inspect --format="{{.State.Health.Status}}" pr-tracker-gateway    2>/dev/null || echo "not running"
	@echo "--- auth ---"       && docker inspect --format="{{.State.Health.Status}}" pr-tracker-auth       2>/dev/null || echo "not running"
	@echo "--- main ---"       && docker inspect --format="{{.State.Health.Status}}" pr-tracker-main       2>/dev/null || echo "not running"
	@echo "--- ai-agent ---"   && docker inspect --format="{{.State.Health.Status}}" pr-tracker-ai         2>/dev/null || echo "not running"
	@echo "--- client ---"     && docker inspect --format="{{.State.Health.Status}}" pr-tracker-client     2>/dev/null || echo "not running"
	@echo "--- nginx ---"      && docker inspect --format="{{.State.Health.Status}}" pr-tracker-nginx      2>/dev/null || echo "not running"

# ── Database ──────────────────────────────────────────────────────
mongo-shell:
	docker exec -it pr-tracker-auth mongosh "$(MONGO_URI)"

# ── Cleanup ───────────────────────────────────────────────────────
clean:
	docker compose down --rmi local
	docker image prune -f
