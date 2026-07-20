# ── Stage 1: install dependencies ──────────────────────────────
FROM node:20.15-alpine AS deps

# Update Alpine packages to fix CVEs
RUN apk update && apk upgrade --no-cache

WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev

# ── Stage 2: final runtime image ───────────────────────────────
FROM node:20.15-alpine AS runtime

# Update Alpine packages to fix CVEs
RUN apk update && apk upgrade --no-cache

ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package*.json ./
COPY src ./src

USER node

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --start-period=15s --retries=5 \
    CMD node -e "require('http').get('http://127.0.0.1:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "src/server.js"]
