#!/bin/bash

# =============================================================================
# BASH SCRIPT TRIỂN KHAI MERN E-COMMERCE
# =============================================================================

set -e

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Script cần chạy với quyền root (sudo)"
        exit 1
    fi
}

# Update system
update_system() {
    apt-get update && apt-get upgrade -y
    apt-get install -y curl wget git unzip
}

# Install Nginx (Web Server)
install_nginx() {
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    
    # Allow HTTP/HTTPS through firewall
    ufw allow 'Nginx Full' 2>/dev/null || true
}

# Install Node.js (Runtime Environment)
install_nodejs() {
    # Install Node.js 18.x
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
}

# Deploy Application
deploy_application() {
    local app_dir="/var/www/mern-ecommerce"
    
    # Create application directory
    mkdir -p "$app_dir"
    
    # Clone repository from GitHub
    git clone https://github.com/Buddini96/Mern-Ecommerce.git "$app_dir"
    cd "$app_dir"

    # Install frontend dependencies
    cd frontend
    npm install
    npm audit fix --force 2>/dev/null || true
    npm run dev &

    # Install backend dependencies
    cd ../backend
    npm install
    npm audit fix --force 2>/dev/null || true
    node index.js &



    
}

# Configure Nginx
configure_nginx() {
    cat > /etc/nginx/sites-available/mern-ecommerce << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    # Proxy frontend (Vite dev server on port 5173)
    location / {
        proxy_pass http://localhost:5173;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
    
    # Proxy API requests to backend
    location /api/ {
        proxy_pass http://localhost:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
    
    # Handle image uploads
    location /images/ {
        proxy_pass http://localhost:4000;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
    
    # Remove default site and enable our site
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/mern-ecommerce /etc/nginx/sites-enabled/
    
    # Test and reload Nginx
    nginx -t && systemctl reload nginx
}

# Set proper permissions
set_permissions() {
    chown -R www-data:www-data /var/www/mern-ecommerce
    chmod -R 755 /var/www/mern-ecommerce
}

# Main deployment function
main() {
    echo "=========================================="
    echo "  MERN E-COMMERCE DEPLOYMENT SCRIPT"
    echo "=========================================="
    
    check_root
    
    # Install system components
    update_system
    install_nginx
    install_nodejs
    
    # Deploy application
    deploy_application
    configure_nginx
    set_permissions
    
    echo "=========================================="
    echo "        TRIỂN KHAI HOÀN TẤT!"
    echo "=========================================="
    
    echo "Thông tin hệ thống:"
    echo "• Website: http://$(hostname -I | awk '{print $1}')"
    echo "• Backend API: http://$(hostname -I | awk '{print $1}')/api"
    echo ""
    echo "Services:"
    echo "• Nginx: systemctl status nginx"
    echo ""
    echo "Development servers:"
    echo "• Frontend (Vite): localhost:5173"
    echo "• Backend (Node): localhost:4000"
}

# Run main function
main "$@"
