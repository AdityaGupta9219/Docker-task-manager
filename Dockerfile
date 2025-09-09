# Multi-stage build for Render.com deployment
FROM node:18-alpine AS backend-build

# Build backend
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci --only=production
COPY backend/ ./

# Nginx stage for frontend
FROM nginx:alpine AS frontend-build
WORKDIR /app
COPY frontend/ /usr/share/nginx/html/

# Final production image
FROM node:18-alpine

# Install nginx and supervisor
RUN apk add --no-cache nginx supervisor curl

# Create necessary directories
RUN mkdir -p /app/backend /app/frontend /run/nginx /var/log/supervisor

# Copy built backend
COPY --from=backend-build /app/backend /app/backend

# Copy frontend files
COPY --from=frontend-build /usr/share/nginx/html /app/frontend

# Create nginx config that works with Render
RUN cat > /etc/nginx/nginx.conf << 'EOF'
worker_processes 1;
pid /run/nginx.pid;
daemon off;
error_log stderr;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    access_log /dev/stdout;
    sendfile on;
    keepalive_timeout 65;
    
    server {
        listen ${PORT:-10000};
        server_name _;
        
        # Health check endpoint
        location /health {
            proxy_pass http://localhost:3000/health;
            proxy_set_header Host $host;
        }
        
        # API routes
        location /api/ {
            proxy_pass http://localhost:3000;
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
        
        # Serve frontend for all other routes
        location / {
            root /app/frontend;
            index index.html;
            try_files $uri $uri/ /index.html;
        }
    }
}
EOF

# Create supervisor config
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
environment=PORT=3000

[program:nginx]
command=nginx
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

# Render uses PORT environment variable
EXPOSE ${PORT:-10000}

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${PORT:-10000}/health || exit 1

# Start both services
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]