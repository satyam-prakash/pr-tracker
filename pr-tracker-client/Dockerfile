# ── Stage 1: Builder ─────────────────────────────────────────────
FROM node:20-alpine AS builder
LABEL stage=builder

# Accept VITE_SERVER_ENDPOINT as a build arg so Docker Compose can pass it in.
# Vite reads from process.env at build time — this is the correct injection point.
ARG VITE_SERVER_ENDPOINT=http://localhost
ENV VITE_SERVER_ENDPOINT=${VITE_SERVER_ENDPOINT}

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build
# Output: /app/dist — static HTML/CSS/JS with VITE_SERVER_ENDPOINT baked in

# ── Stage 2: Production ───────────────────────────────────────────
FROM nginx:1.27-alpine AS production

RUN rm -rf /usr/share/nginx/html/*

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
