# VS Code Container for Fully Containerized Workstation
# New strategy: Start with a clean Python base image and install code-server manually.

FROM python:3.11-slim-bookworm

# Build arguments for user permissions and architecture
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG TARGETARCH

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production
ENV CODER_VERSION=4.104.3

# Install system dependencies, Node.js, and code-server
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Basic utilities
    curl \
    wget \
    git \
    vim \
    nano \
    htop \
    tree \
    unzip \
    zip \
    # Build tools
    build-essential \
    # Network tools
    netcat-openbsd \
    socat \
    iputils-ping \
    net-tools \
    # For Node.js installation
    ca-certificates \
    gnupg \
    # For Docker client
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    # For sudo
    sudo \
    # For Scheduling
    cron \
    procps \
    dos2unix \
    # For Browse Lite embedded browser + Office Viewer PDF export (H38)
    chromium \
    fonts-noto-cjk \
    fonts-liberation \
    && \
    # Install Node.js LTS
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    NODE_MAJOR=20 && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    # Install Docker client
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    # Download and install code-server
    # TARGETARCH is automatically provided by Docker buildx. It will be \'amd64\' or \'arm64\'.
    curl -fOL "https://github.com/coder/code-server/releases/download/v${CODER_VERSION}/code-server_${CODER_VERSION}_${TARGETARCH}.deb" && \
    dpkg -i "code-server_${CODER_VERSION}_${TARGETARCH}.deb" && \
    # Clean up
    rm "code-server_${CODER_VERSION}_${TARGETARCH}.deb" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Pillow system-wide (root) so start-vscode.sh's favicon replacement (sudo python3) can use PIL
RUN pip3 install --no-cache-dir Pillow --break-system-packages

# Create user with matching host UID/GID as per architecture
RUN if ! getent group $HOST_GID >/dev/null; then \
    groupadd -g $HOST_GID workspace-user; \
    else \
    groupadd workspace-user; \
    fi && \
    useradd -m -u $HOST_UID -g $HOST_GID -s /bin/bash workspace-user 2>/dev/null || \
    useradd -m -u $HOST_UID -g workspace-user -s /bin/bash workspace-user && \
    # Add user to docker group
    groupadd -f docker && \
    usermod -aG docker workspace-user && \
    # Explicitly add the user to the root group (GID 0) for Docker socket access
    usermod -aG root workspace-user && \
    # Configure passwordless sudo for workspace-user
    echo 'workspace-user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set up user environment
USER workspace-user
WORKDIR /home/workspace-user

# Install Python packages as the new user
RUN python3 -m pip install --user --no-cache-dir \
    jupyter \
    pandas \
    numpy \
    matplotlib \
    requests \
    beautifulsoup4 \
    lxml \
    mcp

# Switch back to root to install Node.js tools globally
USER root

# Install Node.js tools globally
RUN npm install -g \
    typescript \
    ts-node \
    @types/node \
    yarn

# Switch back to workspace-user
USER workspace-user

# Copy user scripts
COPY start-vscode.sh /home/workspace-user/start-vscode.sh
COPY health-check.sh /home/workspace-user/health-check.sh
COPY init-workspace.sh /home/workspace-user/init-workspace.sh

# Embed Zokai Notes seed workspace for auto-initialization
COPY zokai-notes-seed /home/workspace-user/zokai-notes-seed

# Embed Zokai station docs (capabilities, guides) — lives in .zokai/, overwritten on updates
# Cache-buster: Docker caches COPY layers aggressively. If the seed directory changed
# between installs, stale cache serves old content. This ARG forces invalidation.
ARG DOCS_HASH=default
COPY zokai-docs-seed /home/workspace-user/zokai-docs-seed

# Embed Zokai blue logo for favicon branding (used by start-vscode.sh at startup)
COPY Zokai_tree_logo.png /home/workspace-user/Zokai_tree_logo.png


# Switch back to root to set proper permissions
USER root
RUN dos2unix /home/workspace-user/*.sh && \
    chmod +x /home/workspace-user/*.sh

# Switch back to workspace-user
USER workspace-user

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD /home/workspace-user/health-check.sh

# Initialize workspace on first run
# Note: This runs as the user, which is correct.
RUN /home/workspace-user/init-workspace.sh

# Switch back to workspace-user
USER workspace-user

# Start VS Code Server
CMD ["/home/workspace-user/start-vscode.sh"]
