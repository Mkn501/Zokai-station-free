FROM node:20-slim

WORKDIR /app

# Install system dependencies
# python3, pip, venv: for python environment
# git: for cloning
# ffmpeg, tesseract-ocr, libmagic1: for markdownify features
# curl, ca-certificates: general utilities
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    ffmpeg \
    tesseract-ocr \
    libmagic1 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install uv (required by markdownify-mcp internally)
RUN pip install uv --break-system-packages

# Create .local/bin directory and symlink uv to where the app expects it
RUN mkdir -p /home/node/.local/bin && \
    ln -s $(which uv) /home/node/.local/bin/uv && \
    chown -R node:node /home/node/.local

# Add local bin to PATH for uv
ENV PATH="/home/node/.local/bin:${PATH}"

# Install pnpm
RUN npm install -g pnpm

# Clone repo
RUN git clone https://github.com/zcaceres/markdownify-mcp.git /app

# Install dependencies (runs preinstall.js -> setup.sh)
RUN pnpm install

# Install markitdown with ALL format support (docx, pptx, xlsx, xls, pdf, outlook)
# Also pre-install magika's heavy deps (numpy, onnxruntime) to avoid
# uv lazy-installing them on first tool call (~15s delay + test failures)
RUN pip install 'markitdown[all]' numpy onnxruntime --break-system-packages

# Add express for SSE server
RUN pnpm add express @types/express

# Copy patches including SSE entrypoint
COPY patches/Markdownify.ts /app/src/Markdownify.ts
COPY patches/tools.ts /app/src/tools.ts
COPY patches/server.ts /app/src/server.ts
COPY patches/index.ts /app/src/index.ts

# Build the TypeScript project
RUN pnpm build

# Use existing 'node' user (UID 1000)
RUN chown -R node:node /app
USER node

# Environment variables
ENV PORT=8012
ENV MCP_TRANSPORT=sse

# Expose port
EXPOSE 8012

# Run the SSE server
ENTRYPOINT ["node", "dist/index.js"]
