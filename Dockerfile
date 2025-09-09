# Railway Dockerfile - Single container with backend + frontend
FROM node:18-alpine AS backend-builder

# Build backend
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci --only=production
COPY backend/ ./

# Frontend stage  
FROM nginx:alpine AS frontend-files
COPY frontend/ /usr/share/nginx/html/

# Final stage - runs both backend and frontend
FROM node:18-alpine

# Install nginx and supervisor
RUN apk add --no-cache nginx supervisor curl

# Create directories
RUN mkdir -p /app/backend /app/frontend /run/nginx /var/log/supervisor

# Copy backend from builder
COPY --from=backend-builder /app/backend /app/backend

# Copy frontend files
COPY --from=frontend-files /usr/share/nginx/html /app/frontend

# Create nginx configuration for Railway
RUN <<'EOF' cat > /etc/nginx/nginx.conf
worker_processes 1;
pid /run/nginx.pid;
daemon off;
error_log stderr warn;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /dev/stdout;
    
    upstream backend {
        server localhost:3000;
    }
    
    server {
        listen ${PORT};
        server_name _;
        root /app/frontend;
        index index.html;
        
        # API proxy
        location /api/ {
            proxy_pass http://backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 86400;
        }
        
        # Health check
        location /health {
            proxy_pass http://backend/health;
        }
        
        # Serve frontend
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
EOF

# Create supervisor config for Railway
RUN cat > /etc/supervisor/conf.d/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/dev/stdout
logfile_maxbytes=0
loglevel=info
pidfile=/tmp/supervisord.pid

[program:backend]
command=node server.js
directory=/app/backend
autostart=true
autorestart=true
user=root
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
environment=NODE_ENV=production

[program:nginx]
command=sh -c 'exec nginx'
autostart=true
autorestart=true
user=root
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Set working directory
WORKDIR /app

# Railway uses PORT environment variable (default 8080 for testing)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Start supervisor (runs both nginx and node)
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]