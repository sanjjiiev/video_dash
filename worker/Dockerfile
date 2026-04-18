# =============================================================================
# Stage 1: Builder
# Installs Node.js dependencies in a clean, separate stage
# so the final image contains no build tools (npm, git, etc.)
# =============================================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy only package manifests first to leverage Docker layer caching.
# Only re-runs `npm ci` when package-lock.json actually changes.
COPY package.json package-lock.json ./

# --omit=dev: production deps only. --ignore-scripts: prevents malicious
# postinstall scripts from running during the build phase.
RUN npm ci --omit=dev --ignore-scripts


# =============================================================================
# Stage 2: Final Runtime Image
# Minimal Alpine + FFmpeg. No npm, no git, no compilers.
# =============================================================================
FROM node:20-alpine AS runtime

# Install FFmpeg from Alpine's apk repo (statically linked, no extra libs needed)
# tini is a tiny init that correctly forwards signals and reaps zombie processes
RUN apk add --no-cache ffmpeg tini

# Create an unprivileged user and group. The worker process will NEVER run as root.
RUN addgroup -S ffworker && adduser -S -G ffworker ffworker

WORKDIR /app

# Copy production node_modules from the builder stage
COPY --from=builder /app/node_modules ./node_modules

# Copy application source
COPY src/ ./src/

# The scratch directory for temporary transcoding files.
# This entire directory is ephemeral and will be wiped after each job.
RUN mkdir -p /tmp/transcode && chown ffworker:ffworker /tmp/transcode

# Switch to non-root user
USER ffworker

# Use tini as the container's PID 1 for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

CMD ["node", "src/worker.js"]
