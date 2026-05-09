# Runbook — AI Service Degradation

**Severity:** Medium (PRs still load; analysis unavailable)  
**Alert:** `AIServiceDown` / `AIServiceHighErrorRate` / `AIServiceHighLatency`  
**Dashboard:** Grafana → PR Tracker Overview → Error Rate panel

---

## Design intent (graceful degradation)

The AI analysis feature is **non-critical**. PRs, repositories, and the dashboard
**must continue to function** even when the AI service is completely down.
The frontend should show "Analysis unavailable" rather than an error page.

---

## Symptoms

- AI analysis endpoint returns 500 / 503 / timeout.
- `AIServiceDown` alert fires in Grafana.
- Users see "Analysis failed" badge on PR cards.

---

## Immediate diagnosis

### 1. Check container health

```bash
# Docker Compose
docker compose ps ai-agent
docker compose logs ai-agent --tail 50

# Kubernetes
kubectl get pods -n pr-tracker -l app=ai-agent
kubectl logs -n pr-tracker -l app=ai-agent --tail 50
```

### 2. Test the health endpoint directly

```bash
# From within the Docker network
docker exec pr-tracker-gateway \
  wget -qO- http://ai-agent:5001/health

# Expected: {"status":"ok"}
```

### 3. Check Mistral API key validity

```bash
curl -s https://api.mistral.ai/v1/models \
  -H "Authorization: Bearer $MISTRAL_API_KEY" | jq '.object'
# Expected: "list"
```

---

## Common causes and fixes

| Symptom | Cause | Fix |
|---|---|---|
| Container OOM killed | LLM response too large | Increase memory limit in docker-compose / k8s |
| `401 Unauthorized` from Mistral | Expired / invalid API key | Rotate `MISTRAL_API_KEY` |
| `429 Too Many Requests` | Mistral rate limit | Add retry with exponential backoff |
| Container crash loop | App bug | Check logs, roll back image |

---

## Restart the service

```bash
# Docker Compose
docker compose restart ai-agent

# Kubernetes
kubectl rollout restart deployment/ai-agent -n pr-tracker
```

## Roll back to last known-good image

```bash
# Kubernetes
kubectl set image deployment/ai-agent \
  ai-agent=ghcr.io/satyam-prakash/pr-tracker-ai-agent:main-<previous-sha> \
  -n pr-tracker

kubectl rollout status deployment/ai-agent -n pr-tracker
```

---

## Chaos test verification

Kill the AI service and confirm PRs still load:

```bash
# Kill the container
docker compose stop ai-agent   # or: kubectl scale deploy/ai-agent --replicas=0

# Verify PRs still accessible via the frontend
curl -s http://localhost/api/repos | jq '.repos | length'
# Should return a number > 0

# Restore
docker compose start ai-agent  # or: kubectl scale deploy/ai-agent --replicas=1
```

---

## Escalation

If the Mistral API is experiencing a widespread outage:
1. Check https://status.mistral.ai
2. Consider switching to a fallback model provider (OpenAI, Anthropic) by updating `MISTRAL_API_KEY` and the AI service model endpoint.
3. Notify users via a status page banner.
