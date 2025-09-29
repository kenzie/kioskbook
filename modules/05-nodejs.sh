#!/bin/bash
#
# KioskBook Module: Node.js Installation
#
# Installs Node.js and npm for Vue.js application development.
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

log_info() {
    echo -e "${GREEN}[NODEJS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[NODEJS]${NC} $1"
}

log_error() {
    echo -e "${RED}[NODEJS]${NC} $1"
    exit 1
}

# Check if Node.js is already installed
check_existing() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        NODE_VERSION=$(node --version)
        NPM_VERSION=$(npm --version)
        log_info "Node.js already installed: $NODE_VERSION"
        log_info "npm already installed: $NPM_VERSION"
        return 0
    fi
    return 1
}

# Install Node.js using NodeSource repository
install_nodejs() {
    log_info "Installing Node.js and npm..."
    
    # Add NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    
    # Install Node.js (includes npm)
    apt-get install -y nodejs
    
    # Verify installation
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    
    log_info "Node.js installed: $NODE_VERSION"
    log_info "npm installed: $NPM_VERSION"
}

# Install global npm packages
install_global_packages() {
    log_info "Installing global npm packages..."
    
    # Install useful global packages
    npm install -g \
        http-server \
        pm2 \
        nodemon \
        typescript \
        @vue/cli
    
    log_info "Global npm packages installed"
}

# Configure npm
configure_npm() {
    log_info "Configuring npm..."
    
    # Set npm cache directory
    npm config set cache /var/cache/npm --global
    
    # Set npm prefix
    npm config set prefix /usr/local --global
    
    # Disable npm update notifications
    npm config set update-notifier false --global
    
    log_info "npm configured"
}

# Main function
main() {
    echo -e "${CYAN}=== Node.js Module ===${NC}"
    
    # Skip if already installed
    if check_existing; then
        log_info "Node.js already installed, checking configuration..."
        configure_npm
        return 0
    fi
    
    install_nodejs
    install_global_packages
    configure_npm
    
    log_info "Node.js installation complete"
}

main "$@"
