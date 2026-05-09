# ADR 001 — Server-Side Polling

**Status:** Accepted  
**Date:** 2026-05-10  
**Deciders:** Satyam Prakash

---

## Context

The original PR Tracker frontend used `setInterval` in React to poll GitHub every N minutes while a user had the browser tab open. This had three critical problems:

1. **Fragility** — polling stopped the moment the user closed the tab.
2. **Duplicated API calls** — every active browser session issued independent GitHub API calls, burning through the 5,000 req/hr OAuth rate limit rapidly.
3. **Coupling** — business logic (sync schedule) lived inside the UI layer, making it impossible to test independently.

## Decision

Move the polling responsibility entirely to a dedicated **`pr-tracker-poller`** Node.js service that:

- Runs as a **Kubernetes CronJob** (`schedule: "0 * * * *"`) in production.
- Runs as a **long-lived container** (`POLL_INTERVAL_MS=3600000`) in Docker Compose / EC2.
- Calls `POST /api/prs/sync` on the core backend for each tracked repo.
- Uses a shared `POLLER_SECRET` header so the backend can differentiate internal sync calls from user-triggered calls.

## Consequences

| Aspect | Before | After |
|--------|--------|-------|
| Polling trigger | Browser tab open | Server CronJob — always runs |
| GitHub API calls | N × (users online) per cycle | 1 per repo per cycle |
| Deployability | N/A (browser) | Independent Docker image + k8s manifest |
| Observability | None | Logs emit per-repo success/failure |

## Rejected alternatives

- **GitHub Webhooks** — ideal but requires a public HTTPS endpoint and webhook registration per repo. Deferred to Phase 2.
- **Keeping browser polling + throttling** — doesn't solve the rate limit exhaustion problem.
