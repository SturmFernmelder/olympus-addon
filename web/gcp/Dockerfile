FROM node:22.13-bookworm-slim

WORKDIR /app/web/gcp
COPY web/gcp/package.json web/gcp/package-lock.json ./
RUN npm ci --omit=dev

WORKDIR /app
COPY web/gcp ./web/gcp
COPY web/worker ./web/worker

ENV NODE_ENV=production
CMD ["node", "web/gcp/server.mjs"]

