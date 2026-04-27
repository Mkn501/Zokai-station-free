FROM qdrant/qdrant:latest

# Install curl for container healthcheck (keeps image mostly unchanged)
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Revert to default user if present (qdrant image uses 'qdrant' user)
USER qdrant