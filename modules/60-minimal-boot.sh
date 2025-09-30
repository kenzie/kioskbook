#!/bin/bash
#
# KioskBook Module: Boot Splash Screen
#
# Implements Route 19 boot logo and splash screen functionality.
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
KIOSKBOOK_DIR="/opt/kioskbook"
SPLASH_DIR="/usr/share/kioskbook"

log_info() {
    echo -e "${GREEN}[SPLASH]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[SPLASH]${NC} $1"
}

log_error() {
    echo -e "${RED}[SPLASH]${NC} $1"
    exit 1
}

# Create splash directory and copy assets
setup_splash_assets() {
    log_info "Setting up splash screen assets..."
    
    # Create splash directory
    mkdir -p "$SPLASH_DIR"
    
    # Copy Route 19 logo if it exists
    if [ -f "$KIOSKBOOK_DIR/route19-logo.png" ]; then
        cp "$KIOSKBOOK_DIR/route19-logo.png" "$SPLASH_DIR/"
        log_info "Route 19 logo copied to $SPLASH_DIR"
    else
        log_warn "Route 19 logo not found, creating placeholder"
        # Create a simple text-based logo as fallback
        cat > "$SPLASH_DIR/route19-logo.txt" << 'EOF'
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║                     ROUTE 19                          ║
║                                                       ║
║                  KIOSKBOOK                            ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
    fi
    
    log_info "Splash assets setup complete"
}

# Create minimal splash directory (no custom script needed)
create_boot_splash_script() {
    log_info "Creating minimal splash directory..."
    
    # Just ensure the directory exists for any future needs
    mkdir -p "$SPLASH_DIR"
    
    log_info "Splash directory ready"
}

# Create startup service
create_startup_service() {
    log_info "Creating Route 19 startup service..."
    
    # Copy the startup script from config
    if [ -f "$KIOSKBOOK_DIR/config/route19-startup.start" ]; then
        cp "$KIOSKBOOK_DIR/config/route19-startup.start" "$SPLASH_DIR/"
        chmod +x "$SPLASH_DIR/route19-startup.start"
    fi
    
    # Skip custom startup service - focus on Plymouth only
    log_info "Skipping custom startup service - using Plymouth only"
}

# Configure Plymouth for minimal boot
configure_plymouth() {
    log_info "Configuring Plymouth for minimal boot..."
    
    # Install Plymouth if not present
    if ! command -v plymouth >/dev/null 2>&1; then
        log_info "Installing Plymouth..."
        apt-get install -y plymouth plymouth-themes
    fi
    
    # Use the simplest available theme (text or spinner)
    log_info "Setting Plymouth to minimal theme..."
    
    # Update Plymouth configuration for minimal display
    mkdir -p /etc/plymouth/
    cat > /etc/plymouth/plymouthd.conf << 'EOF'
[Daemon]
Theme=spinner
ShowDelay=0
EOF
    
    # Update initramfs
    update-initramfs -u
    
    log_info "Plymouth configured for minimal boot"
}

# Main function
main() {
    echo -e "${CYAN}=== Minimal Boot Configuration ===${NC}"
    
    setup_splash_assets
    create_boot_splash_script
    create_startup_service
    configure_plymouth
    
    log_info "Minimal boot configuration complete"
    log_info "Fast, clean boot with minimal text output"
}

main "$@"
