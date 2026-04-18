# =============================================================================
# Stage 1: Builder – install production deps in isolation
# =============================================================================
FROM node:20-alpine AS builder

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts


# =============================================================================
# Stage 2: Runtime – minimal footprint, non-root user
# =============================================================================
FROM node:20-alpine AS runtime

# tini: correct PID-1 for signal forwarding + zombie reaping
RUN apk add --no-cache tini

# Unprivileged service account
RUN addgroup -S apigroup && adduser -S -G apigroup apiuser

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY src/ ./src/

USER apiuser

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "src/index.js"]
