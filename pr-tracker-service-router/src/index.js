require("dotenv").config();

const express = require("express");
const cors = require("cors");
const cookieParser = require("cookie-parser");

const auth = require("./middleware/auth");
const { metricsMiddleware, metricsRoute } = require("./middleware/metrics");
const { generalLimiter, authLimiter, aiLimiter } = require("./middleware/rateLimiter");

const authRoutes = require("./routes/auth.routes");
const coreRoutes = require("./routes/core.routes");
const aiRoutes = require("./routes/ai.routes");
const dbRoutes = require("./routes/db.routes");
const healthRoutes = require("./routes/health.routes");

const app = express();
const PORT = process.env.PORT;

// ── Pre-auth middleware ────────────────────────────────────────────────────
app.use(cookieParser());
app.use(express.json());

app.use(cors({
    origin: process.env.CLIENT_URL,
    credentials: true,
}));

// Prometheus scrape endpoint (no auth, no rate-limit — internal network only)
app.get("/metrics", metricsRoute);

// Collect request metrics for every route
app.use(metricsMiddleware);

// Health / readiness (no auth)
app.use(healthRoutes);

// ── Auth middleware ────────────────────────────────────────────────────────
app.use(auth);

// ── Rate limiters applied per route group ─────────────────────────────────
app.use("/api/auth", authLimiter);
app.use("/api/analyze", aiLimiter);
app.use("/api", generalLimiter);

// ── Business routes ────────────────────────────────────────────────────────
app.use(authRoutes);
app.use(dbRoutes);
app.use(coreRoutes);
app.use(aiRoutes);

// ── Fallthrough handlers ───────────────────────────────────────────────────
app.use("/api/*", (req, res) => {
    res.status(404).json({ error: `Route ${req.method} ${req.originalUrl} not found` });
});

app.use((err, req, res, next) => {
    console.error("[gateway]", err.message);
    res.status(500).json({ error: "Internal server error" });
});

app.listen(PORT, () => {
    console.log(`\n  API Gateway running on http://localhost:${PORT}`);
    console.log(`  Auth Service   → ${process.env.AUTH_SERVICE_URL}`);
    console.log(`  Core Service   → ${process.env.CORE_SERVICE_URL}`);
    console.log(`  AI Service     → ${process.env.AI_SERVICE_URL}`);
    console.log(`  DB Service     → ${process.env.DB_SERVICE_URL}`);
    console.log(`  Metrics        → http://localhost:${PORT}/metrics\n`);
});
