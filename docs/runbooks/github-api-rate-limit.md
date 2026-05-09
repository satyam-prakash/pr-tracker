# Runbook — GitHub API Rate Limit Exhaustion

**Severity:** High  
**Alert:** `GitHubRateLimitLow` (warning < 100) / `GitHubRateLimitCritical` (critical < 10)  
**Dashboard:** Grafana → PR Tracker Overview → "GitHub Rate Limit Remaining"

---

## Symptoms

- `GitHubRateLimitLow` / `GitHubRateLimitCritical` Prometheus alert fires.
- Users see "GitHub API error" or stale PR data.
- Poller logs show `403 rate limit exceeded` errors.

---

## Immediate actions

### 1. Check current rate limit usage

```bash
# From any container with network access to the gateway
curl -s https://api.github.com/rate_limit \
  -H "Authorization: Bearer $GITHUB_TOKEN" | jq '.rate'
```

Expected output:
```json
{ "limit": 5000, "remaining": 12, "reset": 1715340000 }
```

### 2. Calculate when limit resets

```bash
date -d @$(curl -s https://api.github.com/rate_limit \
  -H "Authorization: Bearer $GITHUB_TOKEN" | jq '.rate.reset')
```

### 3. Temporarily disable the poller (buys time until reset)

**Docker Compose (EC2):**
```bash
docker compose stop poller
```

**Kubernetes:**
```bash
kubectl patch cronjob pr-poller -n pr-tracker \
  -p '{"spec": {"suspend": true}}'
```

### 4. After rate limit resets, re-enable

```bash
# Docker Compose
docker compose start poller

# Kubernetes
kubectl patch cronjob pr-poller -n pr-tracker \
  -p '{"spec": {"suspend": false}}'
```

---

## Root cause investigation

| Possible cause | Check |
|---|---|
| Too many tracked repos | `db.repositories.count()` in Mongo |
| Poller running more often than intended | `kubectl get jobs -n pr-tracker` |
| Multiple poller instances | `docker compose ps poller` |
| Unauthenticated API calls (1,000 limit) | Check `GITHUB_TOKEN` is set and valid |

---

## Long-term mitigations

1. **GitHub App** — Apps get 15,000 req/hr per installation vs. 5,000 for OAuth Apps.
2. **Conditional requests** — Use `If-None-Match` with GitHub ETags to skip unchanged PRs.
3. **Webhook-driven sync** — React to `pull_request` events instead of polling.
4. **Per-user token rotation** — Use each user's personal token for their repos.

---

## Escalation

If the rate limit does not recover after reset (token may be revoked):
1. Generate a new GitHub token in Settings → Developer settings → Personal access tokens.
2. Update `GITHUB_TOKEN` in `.env` (EC2) or Kubernetes Secret.
3. Restart affected services.
