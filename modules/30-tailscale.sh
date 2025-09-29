#!/bin/bash
#
# KioskBook Module: Tailscale VPN Installation
#
# Installs and configures Tailscale for remote access.
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
    echo -e "${GREEN}[TAILSCALE]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[TAILSCALE]${NC} $1"
}

log_error() {
    echo -e "${RED}[TAILSCALE]${NC} $1"
    exit 1
}

# Check if Tailscale is already installed and configured
check_existing() {
    if command -v tailscale >/dev/null 2>&1; then
        if tailscale status >/dev/null 2>&1; then
            log_info "Tailscale already installed and configured"
            tailscale status
            return 0
        else
            log_info "Tailscale installed but not configured"
            return 1
        fi
    fi
    return 1
}

# Install Tailscale
install_tailscale() {
    log_info "Installing Tailscale..."
    
    # Add Tailscale repository
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
    
    # Install Tailscale
    apt-get update
    apt-get install -y tailscale
    
    log_info "Tailscale installed"
}

# Configure Tailscale
configure_tailscale() {
    local auth_key="$1"
    
    if [ -z "$auth_key" ]; then
        log_error "Tailscale auth key is required"
    fi
    
    log_info "Configuring Tailscale with auth key..."
    
    # Authenticate Tailscale
    tailscale up --authkey="$auth_key" --accept-routes --ssh
    
    log_info "Tailscale configured and connected"
    
    # Show status
    tailscale status
}

# Main function
main() {
    echo -e "${CYAN}=== Tailscale Module ===${NC}"
    
    local auth_key="$1"
    
    # Skip if already configured
    if check_existing; then
        log_info "Tailscale already configured, skipping installation"
        return 0
    fi
    
    # Check if auth key is provided for new installation
    if [ -z "$auth_key" ]; then
        log_error "Usage: $0 <tailscale_auth_key> (required for new installation)"
    fi
    
    install_tailscale
    configure_tailscale "$auth_key"
    
    log_info "Tailscale installation complete"
}

main "$@"
