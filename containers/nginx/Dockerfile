# NGINX Proxy for Fully Containerized Workstation
FROM nginx:1.25-alpine

# Remove default NGINX configuration
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/
COPY manifest.json /etc/nginx/manifest.json

# Create log directory
RUN mkdir -p /var/log/nginx

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD nginx -t

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]