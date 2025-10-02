#!/bin/bash
#
# KioskBook Installation Script
#
# Transforms a minimal Debian installation into a bulletproof kiosk system.
# Run this after installing Debian 13.1.0 netinst with SSH server only.
#
# Usage: sudo ./install.sh [github_repo] [tailscale_key]
#
# Arguments:
#   github_repo  - GitHub repository URL for the kiosk application (optional)
#                  Default: https://github.com/kenzie/lobby-display
#   tailscale_key - Tailscale auth key for VPN access (optional)
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions
source "$SCRIPT_DIR/lib/common.sh"

# Error handler
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Installation failed at line $1. Check logs in $LOG_DIR"
    fi
}
trap 'cleanup $LINENO' ERR

# Get configuration from arguments or prompts
get_configuration() {
    log "Configuration"

    # GitHub repository
    if [[ -n "${1:-}" ]]; then
        GITHUB_REPO="$1"
    else
        echo -n "GitHub repository (default: $DEFAULT_GITHUB_REPO): "
        read -r GITHUB_REPO
        GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_GITHUB_REPO}"
    fi
    export GITHUB_REPO
    log "Using repository: $GITHUB_REPO"

    # Tailscale key (optional)
    if [[ -n "${2:-}" ]]; then
        TAILSCALE_KEY="$2"
    else
        echo -n "Tailscale auth key (optional, press Enter to skip): "
        read -rs TAILSCALE_KEY
        echo
    fi
    export TAILSCALE_KEY

    if [[ -n "$TAILSCALE_KEY" ]]; then
        log "Tailscale VPN will be configured"
    else
        log "Skipping Tailscale VPN setup"
    fi
}

# Show completion summary
show_completion() {
    local version="unknown"
    if [[ -f /etc/kioskbook/version ]]; then
        version=$(cat /etc/kioskbook/version)
    fi

    echo -e "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     KioskBook Installation Complete!${NC}"
    echo -e "${GREEN}     Version: $version${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"

    echo -e "\n${CYAN}System Status:${NC}"
    if systemctl is-active --quiet kioskbook-app; then
        echo -e "  ✅ Application service running"
    else
        echo -e "  ⚠️  Application service needs attention"
    fi

    echo -e "\n${CYAN}Next Steps:${NC}"
    echo -e "1. Reboot system: ${YELLOW}sudo reboot${NC}"
    echo -e "2. System will auto-login and start kiosk display"
    echo -e "3. Check health: ${YELLOW}sudo kioskbook-health${NC}"

    echo -e "\n${CYAN}The system now has:${NC}"
    echo -e "  ✅ Debian base system optimized for kiosk"
    echo -e "  ✅ X11 + OpenBox minimal window manager"
    echo -e "  ✅ Chromium browser in kiosk mode"
    echo -e "  ✅ Auto-login configured"
    echo -e "  ✅ Vue.js application running"
    echo -e "  ✅ Silent boot configured"
    echo -e "  ✅ Monitoring and automatic recovery"
    if [[ -n "${TAILSCALE_KEY:-}" ]]; then
        echo -e "  ✅ Tailscale VPN enabled"
    fi

    echo -e "\n${CYAN}Management Commands:${NC}"
    echo -e "  Status: ${YELLOW}kiosk status${NC}"
    echo -e "  Health: ${YELLOW}kiosk health${NC}"
    echo -e "  Logs: ${YELLOW}kiosk logs${NC}"
    echo -e "  Update module: ${YELLOW}kiosk update <module-name>${NC}"

    echo -e "\n${CYAN}Module Updates (for development):${NC}"
    echo -e "  List modules: ${YELLOW}kiosk modules${NC}"
    echo -e "  Update specific: ${YELLOW}kiosk update 30-display${NC}"
    echo -e "  Update all: ${YELLOW}kiosk update all${NC}"
}

# Main installation
main() {
    show_banner "KioskBook Installation"

    # Prerequisites
    require_root
    require_debian
    require_network
    ensure_log_dir

    # Get configuration
    get_configuration "$@"

    # Find and run all modules
    log "Starting modular installation..."

    for module in $(get_modules "$SCRIPT_DIR/modules"); do
        run_module "$module"
    done

    log_success "All modules completed successfully"

    # Install kiosk CLI
    log "Installing kiosk management CLI..."
    cp "$SCRIPT_DIR/bin/kiosk" /usr/local/bin/kiosk
    chmod +x /usr/local/bin/kiosk
    log_success "Kiosk CLI installed"

    # Save version
    log "Saving version information..."
    mkdir -p /etc/kioskbook
    if [[ -f "$SCRIPT_DIR/VERSION" ]]; then
        cp "$SCRIPT_DIR/VERSION" /etc/kioskbook/version
        log "Installed version: $(cat /etc/kioskbook/version)"
    fi

    # Copy repository to system location for module updates
    log "Installing repository to $REPO_DIR for module updates..."
    if [[ -d "$REPO_DIR" ]]; then
        rm -rf "$REPO_DIR"
    fi
    cp -r "$SCRIPT_DIR" "$REPO_DIR"
    log_success "Repository installed"

    # Show completion
    show_completion
}

# Run main
main "$@"
