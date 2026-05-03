# ── Stage 1: Install production dependencies only ─────────────────
FROM node:20-alpine AS deps

WORKDIR /app

# Separate copy so npm ci is cached unless package-lock.json changes
COPY package*.json ./
RUN npm ci --omit=dev

# ── Stage 2: Production image ─────────────────────────────────────
FROM node:20-alpine AS production

# Security: never run as root inside a container
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Pull only production node_modules from deps stage (no devDeps)
COPY --from=deps /app/node_modules ./node_modules

# Copy source with correct ownership
COPY --chown=appuser:appgroup . .

# Drop privileges to non-root user
USER appuser

EXPOSE 5000

# Use node directly — not npm start — for clean signal handling (SIGTERM)
CMD ["node", "src/index.js"]
