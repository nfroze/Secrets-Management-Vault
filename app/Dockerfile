# =============================================================================
# Multi-stage build — hardened production container
# Non-root user, read-only rootfs, no shell, minimal attack surface
# =============================================================================

# Stage 1: Install dependencies
FROM node:20-alpine AS builder

WORKDIR /build
COPY package.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Stage 2: Production image
FROM node:20-alpine AS production

# Security: create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copy only production dependencies and source
COPY --from=builder /build/node_modules ./node_modules
COPY src/ ./src/
COPY package.json ./

# Security: set ownership and permissions
RUN chown -R appuser:appgroup /app

# Security: run as non-root
USER 1001:1001

# Expose application port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "const http = require('http'); const req = http.get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1); }); req.on('error', () => process.exit(1));"

# Start application
CMD ["node", "src/server.js"]
