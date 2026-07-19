# ── Stage 1: install dependencies ───────────────────────────────
FROM node:20.15-alpine AS deps

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

# ── Stage 2: final runtime image ────────────────────────────────
FROM node:20.15-alpine AS runtime

ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package*.json ./
COPY src ./src

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "src/server.js"]
