# Tavily MCP Server - Dual transport (stdio + SSE)
FROM node:22-alpine

WORKDIR /app

# Install dependencies
RUN npm install @mcptools/mcp-tavily @modelcontextprotocol/sdk express

# Create non-root user (use gid 1001 to avoid conflicts)
RUN addgroup -g 1001 mcp || true && \
    adduser -u 1001 -G mcp -s /bin/sh -D mcp || true

# Copy the SSE wrapper server
COPY server.js .

# Expose SSE port
EXPOSE 8000

# Set defaults
ENV MCP_TRANSPORT=sse
ENV PORT=8000

USER mcp

# Default: run the wrapper server (handles both stdio and SSE)
# Can be overridden by docker-compose command for sleeper pattern
CMD ["node", "server.js"]