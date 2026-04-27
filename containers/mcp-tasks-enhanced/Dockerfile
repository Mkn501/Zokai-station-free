FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:20-slim
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules

# Pre-seed sources.json to point to the mounted file (matching bridge path translation)
RUN echo '[{"path":"/app/workspace/antigravity_tasks.md","workspace":"/app/workspace"}]' > sources.json

ENV PORT=8010
ENV TRANSPORT=http
ENV SOURCES_PATH=./sources.json

CMD ["node", "/app/dist/index.js"]
