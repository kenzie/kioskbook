#!/bin/ash
#
# KioskBook Alpine Linux Bootstrap Script
# 
# This script runs on minimal Alpine Linux and prepares the system for the main installer.
# Uses POSIX sh for maximum compatibility with Alpine's busybox environment.
#
# Usage: ./bootstrap.sh
#
# Requirements:
# - Alpine Linux Live USB or minimal installation
# - Root access
# - Internet connectivity (will be configured if needed)
#

set -e

# Color codes for output (POSIX compatible)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/kenzie/kioskbook.git"
REPO_BRANCH="main"
WORK_DIR="/tmp/kioskbook-install"

# Logging function
log() {
    echo "${BLUE}[BOOTSTRAP]${NC} $1"
}

log_success() {
    echo "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error_exit "This script must be run as root. Use 'su -' to become root."
    fi
}

# Check if command exists (POSIX compatible)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Setup networking if needed
setup_networking() {
    log "Setting up networking..."
    
    # Check if already connected
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_success "Network connectivity verified"
        return 0
    fi
    
    # Start networking service if not running
    if ! rc-status | grep -q "networking.*started"; then
        log "Starting networking service..."
        rc-service networking start || {
            log_warning "Failed to start networking service, trying manual setup..."
        }
    fi
    
    # Try DHCP on available interfaces
    for iface in $(ls /sys/class/net/ | grep -v lo); do
        if [ -d "/sys/class/net/$iface" ]; then
            log "Attempting DHCP on interface $iface..."
            udhcpc -i "$iface" -t 3 -T 10 >/dev/null 2>&1 && break
        fi
    done
    
    # Verify connectivity again
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_success "Network connectivity established"
    else
        error_exit "Failed to establish network connectivity. Please check ethernet connection."
    fi
}

# Configure Alpine package repositories
configure_repositories() {
    log "Configuring Alpine package repositories..."
    
    # Check if repositories are properly configured (not pointing to CD-ROM)
    if grep -q "/media/cdrom" /etc/apk/repositories 2>/dev/null; then
        log "CD-ROM repositories detected, configuring online repositories..."
        
        # Backup existing repositories
        cp /etc/apk/repositories /etc/apk/repositories.backup 2>/dev/null || true
        
        # Configure proper online repositories
        cat > /etc/apk/repositories << 'EOF'
http://dl-cdn.alpinelinux.org/alpine/v3.19/main
http://dl-cdn.alpinelinux.org/alpine/v3.19/community
EOF
        log_success "Repositories configured to use online mirrors"
        
    elif ! grep -q "community" /etc/apk/repositories 2>/dev/null; then
        log "Community repository not enabled, adding..."
        echo "http://dl-cdn.alpinelinux.org/alpine/v3.19/community" >> /etc/apk/repositories
        log_success "Community repository enabled"
        
    else
        log "Repositories already properly configured"
    fi
}

# Update package repositories
update_repositories() {
    log "Updating Alpine package repositories..."
    
    # Check if already updated recently (idempotent)
    if [ -f "/var/cache/apk/APKINDEX.tar.gz" ]; then
        # Check if index is less than 1 hour old
        if [ $(find /var/cache/apk/APKINDEX.tar.gz -mmin -60 2>/dev/null | wc -l) -gt 0 ]; then
            log "Package repositories recently updated, skipping..."
            return 0
        fi
    fi
    
    # Try to update repositories, with fallback to alternative mirrors
    if ! apk update; then
        log_warning "Failed to update with primary mirrors, trying alternatives..."
        
        # Try alternative mirrors
        cat > /etc/apk/repositories << 'EOF'
http://mirror.leaseweb.com/alpine/v3.19/main
http://mirror.leaseweb.com/alpine/v3.19/community
EOF
        
        if apk update; then
            log_success "Package repositories updated using alternative mirrors"
        else
            # Try HTTPS mirrors as last resort
            cat > /etc/apk/repositories << 'EOF'
https://alpine.global.ssl.fastly.net/alpine/v3.19/main
https://alpine.global.ssl.fastly.net/alpine/v3.19/community
EOF
            apk update || error_exit "Failed to update package repositories with all available mirrors"
            log_success "Package repositories updated using HTTPS mirrors"
        fi
    else
        log_success "Package repositories updated"
    fi
}

# Install required packages
install_packages() {
    log "Installing required packages..."
    
    # List of required packages
    packages="bash git curl parted"
    
    # Check if packages are already installed (idempotent)
    all_installed=true
    for pkg in $packages; do
        if ! apk info -e "$pkg" >/dev/null 2>&1; then
            all_installed=false
            break
        fi
    done
    
    if [ "$all_installed" = "true" ]; then
        log "All required packages already installed"
        return 0
    fi
    
    # Install packages
    apk add $packages || error_exit "Failed to install required packages"
    log_success "Required packages installed: $packages"
}

# Clone repository
clone_repository() {
    log "Cloning KioskBook repository..."
    
    # Remove existing directory if present (idempotent)
    if [ -d "$WORK_DIR" ]; then
        log "Removing existing installation directory..."
        rm -rf "$WORK_DIR"
    fi
    
    # Create work directory
    mkdir -p "$(dirname "$WORK_DIR")"
    
    # Clone repository
    git clone -b "$REPO_BRANCH" "$REPO_URL" "$WORK_DIR" || {
        error_exit "Failed to clone repository. Check network connectivity and repository URL."
    }
    
    log_success "Repository cloned to $WORK_DIR"
}

# Setup Route 19 logo
setup_route19_logo() {
    log "Setting up Route 19 logo..."
    
    LOGO_DEST="/opt/route19-logo.png"
    
    # Create destination directory
    mkdir -p "$(dirname "$LOGO_DEST")"
    
    # Check for Route 19 logo in repository (primary location)
    if [ -f "$WORK_DIR/route19-logo.png" ]; then
        cp "$WORK_DIR/route19-logo.png" "$LOGO_DEST"
        log_success "Route 19 logo copied from repository root"
        return 0
    fi
    
    # Check for logo in assets directory (secondary location)
    if [ -f "$WORK_DIR/assets/route19-logo.png" ]; then
        cp "$WORK_DIR/assets/route19-logo.png" "$LOGO_DEST"
        log_success "Route 19 logo copied from repository assets"
        return 0
    fi
    
    log_warning "Route 19 logo not found in repository. Installer will create a placeholder."
    log_warning "To use actual Route 19 logo, place it at: $LOGO_DEST"
}

# Verify installation files
verify_files() {
    log "Verifying installation files..."
    
    main_installer="$WORK_DIR/installer/main.sh"
    
    if [ ! -f "$main_installer" ]; then
        error_exit "Main installer not found at $main_installer"
    fi
    
    if [ ! -x "$main_installer" ]; then
        chmod +x "$main_installer"
        log "Made main installer executable"
    fi
    
    log_success "Installation files verified"
}

# Execute main installer
execute_main_installer() {
    log "Executing main installer with bash..."
    
    cd "$WORK_DIR"
    
    # Ensure bash is available
    if ! command_exists bash; then
        error_exit "Bash not available after installation"
    fi
    
    # Execute main installer
    exec bash "./installer/main.sh" "$@"
}

# Main bootstrap process
main() {
    echo ""
    echo "${BLUE}================================================${NC}"
    echo "${BLUE}    KioskBook Alpine Linux Bootstrap${NC}"
    echo "${BLUE}================================================${NC}"
    echo ""
    
    log "Starting bootstrap process..."
    
    # Perform bootstrap steps
    check_root
    setup_networking
    configure_repositories
    update_repositories
    install_packages
    clone_repository
    setup_route19_logo
    verify_files
    
    echo ""
    log_success "Bootstrap completed successfully!"
    log "Switching to main installer..."
    echo ""
    
    # Pass all arguments to main installer
    execute_main_installer "$@"
}

# Execute main function with all arguments
main "$@"