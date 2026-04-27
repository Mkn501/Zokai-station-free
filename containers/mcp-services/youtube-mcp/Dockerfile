# YouTube MCP Service Container
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8002

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create non-root user matching workspace-user UID/GID (1000:1000)
# This ensures files written to shared workspace volume are readable by vs-code
RUN groupadd -g 1000 mcp && \
    useradd --create-home --shell /bin/bash -u 1000 -g 1000 mcp && \
    chown -R mcp:mcp /app
USER mcp

# Expose port
EXPOSE 8002

# Start the entrypoint script
ENTRYPOINT ["/entrypoint.sh"]
