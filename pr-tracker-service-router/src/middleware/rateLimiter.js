/**
 * rateLimiter.js — Express rate-limiting middleware for the API Gateway.
 *
 * Strategy:
 *   - General API calls:  100 req / 15 min per IP
 *   - Auth endpoints:      10 req / 15 min per IP (brute-force protection)
 *   - AI endpoints:         5 req / 1  min per IP (expensive LLM calls)
 *
 * Uses express-rate-limit (in-memory store — replace with RedisStore when
 * Redis is available to handle multi-replica deployments).
 */

const rateLimit = require("express-rate-limit");

// ── Shared window helper ───────────────────────────────────────────────────
const makeHandler = (max, windowMs, message) =>
    rateLimit({
        windowMs,
        max,
        standardHeaders: true,   // Return rate limit info in the `RateLimit-*` headers
        legacyHeaders: false,    // Disable the `X-RateLimit-*` headers
        message: { error: message },
        skipSuccessfulRequests: false,
    });

// ── Rate limiters ──────────────────────────────────────────────────────────

/** General API limiter — applied to all routes */
const generalLimiter = makeHandler(
    100,
    15 * 60 * 1000,
    "Too many requests — please try again in 15 minutes"
);

/** Auth endpoints (login, callback) — tighter window */
const authLimiter = makeHandler(
    10,
    15 * 60 * 1000,
    "Too many authentication attempts — please try again in 15 minutes"
);

/** AI analysis endpoints — expensive, slow window */
const aiLimiter = makeHandler(
    5,
    60 * 1000,
    "AI analysis rate limit reached — please wait a minute before retrying"
);

module.exports = { generalLimiter, authLimiter, aiLimiter };
