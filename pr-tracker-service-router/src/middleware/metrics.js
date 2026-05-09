/**
 * metrics.js — Prometheus instrumentation middleware for the API Gateway.
 *
 * Exposes the following metrics on GET /metrics:
 *   http_requests_total          — labelled by method, route, status
 *   http_request_duration_seconds — labelled by method, route
 *   github_rate_limit_remaining  — gauge updated by upstream responses
 */

const client = require("prom-client");

// ── Registry ───────────────────────────────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: "gateway_" });

// ── Custom metrics ─────────────────────────────────────────────────────────
const httpRequestsTotal = new client.Counter({
    name: "http_requests_total",
    help: "Total number of HTTP requests",
    labelNames: ["method", "route", "status"],
    registers: [register],
});

const httpRequestDuration = new client.Histogram({
    name: "http_request_duration_seconds",
    help: "HTTP request duration in seconds",
    labelNames: ["method", "route"],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
    registers: [register],
});

const githubRateLimitRemaining = new client.Gauge({
    name: "github_rate_limit_remaining",
    help: "GitHub API rate limit calls remaining (from upstream X-RateLimit-Remaining header)",
    registers: [register],
});

// ── Helper: normalise dynamic path segments ────────────────────────────────
// e.g.  /api/repos/my-repo/prs/123  →  /api/repos/:id/prs/:id
function normalisePath(url) {
    return url
        .split("?")[0]                            // strip query string
        .replace(/\/[0-9a-f]{24}/g, "/:id")      // MongoDB ObjectIds
        .replace(/\/\d+/g, "/:id")               // numeric IDs
        .replace(/\/[^/]{20,}/g, "/:token");     // long tokens / slugs
}

// ── Request-counting middleware ────────────────────────────────────────────
function metricsMiddleware(req, res, next) {
    const start = process.hrtime.bigint();
    const route = normalisePath(req.originalUrl);

    res.on("finish", () => {
        const durationMs = Number(process.hrtime.bigint() - start) / 1e9;
        const labels = { method: req.method, route, status: res.statusCode };

        httpRequestsTotal.inc(labels);
        httpRequestDuration.observe({ method: req.method, route }, durationMs);

        // Capture GitHub rate limit from upstream response headers if present
        const remaining = res.getHeader("x-ratelimit-remaining");
        if (remaining !== undefined) {
            githubRateLimitRemaining.set(Number(remaining));
        }
    });

    next();
}

// ── /metrics route handler ─────────────────────────────────────────────────
async function metricsRoute(req, res) {
    res.set("Content-Type", register.contentType);
    res.end(await register.metrics());
}

module.exports = { metricsMiddleware, metricsRoute, githubRateLimitRemaining };
