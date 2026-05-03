# ── Stage 1: Install production dependencies only ─────────────────
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

EXPOSE 5004

CMD ["node", "src/index.js"]
