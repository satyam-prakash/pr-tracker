/**
 * PR Tracker — Server-Side Poller Worker
 *
 * Replaces the browser setInterval pattern.
 * Runs on a schedule (every hour in production via Kubernetes CronJob).
 * In local/dev mode it polls once immediately.
 *
 * Flow:
 *   1. Fetch all tracked repos from the core backend (/api/repos/all)
 *   2. For each repo, call /api/prs/sync to pull latest PRs from GitHub
 *   3. Log summary — the backend emits events (webhooks / queues) downstream
 *
 * Environment variables:
 *   CORE_SERVICE_URL   — e.g. http://main-backend:5002
 *   POLLER_SECRET      — shared secret so the backend trusts this service
 *   POLL_INTERVAL_MS   — default 3600000 (1 h); set to 0 to run once and exit
 */

require("dotenv").config();

const axios = require("axios");

const CORE_URL = process.env.CORE_SERVICE_URL || "http://localhost:5002";
const SECRET = process.env.POLLER_SECRET || "";
const INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS ?? "3600000", 10);

const http = axios.create({
    baseURL: CORE_URL,
    headers: { "x-poller-secret": SECRET },
    timeout: 30_000,
});

// ── Main poll cycle ────────────────────────────────────────────────────────
async function poll() {
    const start = Date.now();
    console.log(`[poller] ${new Date().toISOString()} — starting poll cycle`);

    let repos;
    try {
        const { data } = await http.get("/api/repos/all");
        repos = data.repos ?? [];
    } catch (err) {
        console.error("[poller] Failed to fetch repo list:", err.message);
        return;
    }

    console.log(`[poller] Found ${repos.length} tracked repos`);

    const results = await Promise.allSettled(
        repos.map(async (repo) => {
            try {
                await http.post(`/api/prs/sync`, { repoId: repo._id });
                console.log(`[poller]   ✓ synced ${repo.fullName}`);
            } catch (err) {
                console.error(`[poller]   ✗ failed ${repo.fullName}: ${err.message}`);
                throw err;
            }
        })
    );

    const succeeded = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.filter((r) => r.status === "rejected").length;
    const elapsed = ((Date.now() - start) / 1000).toFixed(1);

    console.log(
        `[poller] Cycle complete in ${elapsed}s — ${succeeded} synced, ${failed} failed`
    );
}

// ── Entry point ────────────────────────────────────────────────────────────
(async () => {
    await poll();

    if (INTERVAL_MS > 0) {
        console.log(`[poller] Scheduling next poll in ${INTERVAL_MS / 60_000} min`);
        setInterval(poll, INTERVAL_MS);
    } else {
        console.log("[poller] POLL_INTERVAL_MS=0 — single run, exiting");
        process.exit(0);
    }
})();
