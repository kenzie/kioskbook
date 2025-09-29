#!/bin/bash
#
# KioskBook Module: Vue.js Application Installation
#
# Clones and installs the Vue.js application from GitHub.
# This module is idempotent - safe to re-run.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
APP_DIR="/opt/kiosk-app"

log_info() {
    echo -e "${GREEN}[VUE-APP]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[VUE-APP]${NC} $1"
}

log_error() {
    echo -e "${RED}[VUE-APP]${NC} $1"
    exit 1
}

# Check if app is already installed
check_existing() {
    if [ -d "$APP_DIR" ] && [ -f "$APP_DIR/package.json" ]; then
        log_info "Vue.js application already installed at $APP_DIR"
        return 0
    fi
    return 1
}

# Clone and install application
install_application() {
    local github_repo="$1"
    
    if [ -z "$github_repo" ]; then
        log_error "Usage: $0 <github_repo_url>"
    fi
    
    log_info "Installing Vue.js application from $github_repo..."
    
    # Remove existing app directory
    if [ -d "$APP_DIR" ]; then
        log_warn "Removing existing app directory..."
        rm -rf "$APP_DIR"
    fi
    
    # Clone repository
    git clone "$github_repo" "$APP_DIR"
    cd "$APP_DIR"
    
    # Install dependencies
    log_info "Installing npm dependencies..."
    npm install
    
    # Build application
    log_info "Building production bundle..."
    if npm run build 2>/dev/null; then
        log_info "Build successful"
        USE_DIST=true
    else
        log_warn "Build failed or no build script, will serve in dev mode"
        USE_DIST=false
    fi
    
    log_info "Vue.js application installed"
}

# Create systemd service for app
create_app_service() {
    log_info "Creating kiosk-app systemd service..."
    
    if [ "$USE_DIST" = true ]; then
        # Serve built files with http-server
        npm install -g http-server
        HTTP_SERVER_PATH=$(which http-server)
        
        cat > /etc/systemd/system/kiosk-app.service << EOF
[Unit]
Description=Kiosk Vue.js Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR/dist
ExecStart=$HTTP_SERVER_PATH -p 3000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    else
        # Serve in dev mode
        cat > /etc/systemd/system/kiosk-app.service << EOF
[Unit]
Description=Kiosk Vue.js Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=10
Environment="HOST=0.0.0.0"
Environment="PORT=3000"

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable kiosk-app.service
    systemctl start kiosk-app.service
    
    log_info "Kiosk-app service created and started"
}

# Main function
main() {
    echo -e "${CYAN}=== Vue.js Application Module ===${NC}"
    
    local github_repo="$1"
    
    if [ -z "$github_repo" ]; then
        log_error "Usage: $0 <github_repo_url>"
    fi
    
    # Check if already installed
    if check_existing; then
        log_info "Application already installed, updating service configuration..."
        create_app_service
        return 0
    fi
    
    install_application "$github_repo"
    create_app_service
    
    log_info "Vue.js application installation complete"
}

main "$@"
