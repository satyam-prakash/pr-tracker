# ── Stage 1: Install production deps ─────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

# ── Stage 2: Production image ─────────────────────────────────────
FROM node:20-alpine AS production

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --chown=appuser:appgroup . .

USER appuser

# The poller is invoked as a CronJob — it runs, syncs, then exits.
# POLL_INTERVAL_MS=0 ensures a single run and clean exit.
ENV POLL_INTERVAL_MS=0

CMD ["node", "src/index.js"]
