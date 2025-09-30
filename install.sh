#!/bin/bash
#
# KioskBook: Modular Installation System
#
# This installer is completely self-contained. It will:
# 1. Clone the KioskBook repository to the live system
# 2. Set up packages, create users, and configure the system
# 3. Run through a collection of modules in the right order to install everything
#
# Prerequisites:
# - Minimal Debian installation (tested on Debian 13/trixie)
# - Root access
# - Internet connection
#
# Usage: 
#   wget https://raw.githubusercontent.com/kenzie/kioskbook/modular-install/install.sh
#   bash install.sh
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEZONE="America/Halifax"
KIOSK_USER="kiosk"
KIOSK_HOME="/home/kiosk"
APP_DIR="/opt/kiosk-app"
KIOSKBOOK_DIR="/opt/kioskbook"
MODULES_DIR="$KIOSKBOOK_DIR/modules"

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║                                                       ║"
    echo "║               KIOSKBOOK MODULAR INSTALLER             ║"
    echo "║          Fast-Boot Kiosk Deployment System            ║"
    echo "║                                                       ║"
    echo "║         Lenovo M75q-1 | Debian 13 | <10s Boot        ║"
    echo "║                                                       ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_step() {
    echo -e "\n${BLUE}===${NC} ${CYAN}$1${NC} ${BLUE}===${NC}\n"
}

# Get user configuration
get_configuration() {
    log_step "Configuration"

    # KioskBook repository URL
    echo -e "${CYAN}KioskBook repository URL${NC}"
    echo -n -e "(default: https://github.com/kenzie/kioskbook.git): "
    read KIOSKBOOK_REPO
    if [ -z "$KIOSKBOOK_REPO" ]; then
        KIOSKBOOK_REPO="https://github.com/kenzie/kioskbook.git"
        log_info "Using default KioskBook repository: $KIOSKBOOK_REPO"
    fi
    
    # Ask for branch (default to modular-install for now)
    echo -e "\n${CYAN}Branch to use${NC}"
    echo -n -e "(default: modular-install): "
    read KIOSKBOOK_BRANCH
    if [ -z "$KIOSKBOOK_BRANCH" ]; then
        KIOSKBOOK_BRANCH="modular-install"
        log_info "Using default branch: $KIOSKBOOK_BRANCH"
    fi

    # GitHub repo for Vue.js application
    echo -e "\n${CYAN}Vue.js application git repository${NC}"
    echo -n -e "(default: https://github.com/kenzie/lobby-display): "
    read GITHUB_REPO
    if [ -z "$GITHUB_REPO" ]; then
        GITHUB_REPO="https://github.com/kenzie/lobby-display"
        log_info "Using default application repository: $GITHUB_REPO"
    fi

    # Tailscale auth key
    echo -e "\n${CYAN}Tailscale auth key for remote access${NC}"
    echo -e "${YELLOW}(Leave empty if Tailscale is already configured)${NC}"
    echo -n -e "(get from https://login.tailscale.com/admin/settings/keys): "
    read TAILSCALE_KEY
    if [ -z "$TAILSCALE_KEY" ]; then
        log_warn "No Tailscale auth key provided - will check for existing configuration"
        TAILSCALE_KEY=""
    fi
}

# Verify system prerequisites
verify_system() {
    log_step "System Verification"

    # Check running as root
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root"
    fi
    log_info "Running as root ✓"

    # Check Debian version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "Detected: $PRETTY_NAME"
        if [ "$ID" != "debian" ]; then
            log_warn "Not Debian - may have compatibility issues"
        fi
    fi

    # Check network
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No network connectivity - internet required"
    fi
    log_info "Network connectivity ✓"

    # Note: Node.js and npm will be installed by the Node.js module
    log_info "Node.js and npm will be installed during setup"
}

# Install base packages and setup system
install_base_system() {
    log_step "Installing Base System"

    # Update package list
    log_info "Updating package list..."
    apt-get update

    # Install essential packages
    log_info "Installing essential packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git \
        curl \
        wget \
        unzip \
        systemd \
        sudo \
        vim \
        htop

    log_info "Base system installed"
}

# Create kiosk user
create_kiosk_user() {
    log_step "Creating Kiosk User"

    # Create kiosk user
    if ! id -u $KIOSK_USER >/dev/null 2>&1; then
        useradd -m -s /bin/bash $KIOSK_USER
        log_info "Created user: $KIOSK_USER"
    else
        log_info "User $KIOSK_USER already exists"
    fi

    # Add to sudo group for management tasks
    usermod -aG sudo $KIOSK_USER

    # Configure auto-login
    log_info "Configuring auto-login..."
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

    chown -R $KIOSK_USER:$KIOSK_USER $KIOSK_HOME
    log_info "Kiosk user configured with auto-login"
}

# Clone KioskBook repository to live system
clone_kioskbook() {
    log_step "Cloning KioskBook Repository"

    # Clone KioskBook repository to the live system
    if [ -d "$KIOSKBOOK_DIR" ]; then
        log_warn "KioskBook directory exists, removing..."
        rm -rf $KIOSKBOOK_DIR
    fi
    
    log_info "Cloning KioskBook from $KIOSKBOOK_REPO (branch: $KIOSKBOOK_BRANCH)..."
    git clone -b $KIOSKBOOK_BRANCH $KIOSKBOOK_REPO $KIOSKBOOK_DIR

    # Make sure all scripts are executable
    find $KIOSKBOOK_DIR -name "*.sh" -exec chmod +x {} \;
    
    # Verify modules directory exists
    if [ ! -d "$MODULES_DIR" ]; then
        log_error "Modules directory not found at $MODULES_DIR - repository may be incomplete"
    fi
    
    # Verify we have the expected modules
    local expected_modules=("05-nodejs" "10-display-stack" "20-boot-optimization" "30-tailscale" "40-vue-app" "50-kiosk-services" "60-boot-splash" "70-health-monitoring" "80-auto-updates" "90-screensaver" "100-kiosk-cli" "110-finalization")
    for module in "${expected_modules[@]}"; do
        if [ ! -f "$MODULES_DIR/$module.sh" ]; then
            log_error "Required module $module.sh not found in $MODULES_DIR"
        fi
    done

    log_info "KioskBook repository cloned to $KIOSKBOOK_DIR"
    log_info "All modules verified and ready"
}

# Run installation modules in order
run_modules() {
    log_step "Running Installation Modules"

    # Define module order (numeric prefixes ensure proper ordering)
    MODULES=(
        "05-nodejs"
        "10-display-stack"
        "20-boot-optimization" 
        "30-tailscale"
        "40-vue-app"
        "50-kiosk-services"
        "60-minimal-boot"
        "70-health-monitoring"
        "80-auto-updates"
        "90-screensaver"
        "100-kiosk-cli"
        "110-finalization"
    )

    # Debug information
    log_info "Modules directory: $MODULES_DIR"
    log_info "Available modules:"
    ls -la "$MODULES_DIR"/*.sh 2>/dev/null || log_warn "No modules found in $MODULES_DIR"
    
    # Run each module
    for module in "${MODULES[@]}"; do
        MODULE_SCRIPT="$MODULES_DIR/$module.sh"
        log_info "Looking for module: $MODULE_SCRIPT"
        
        if [ -f "$MODULE_SCRIPT" ]; then
            log_info "Running module: $module"
            # Pass arguments based on module needs
            case "$module" in
                "30-tailscale")
                    if [ -n "$TAILSCALE_KEY" ]; then
                        bash "$MODULE_SCRIPT" "$TAILSCALE_KEY"
                    else
                        bash "$MODULE_SCRIPT" ""
                    fi
                    ;;
                "40-vue-app")
                    bash "$MODULE_SCRIPT" "$GITHUB_REPO"
                    ;;
                "20-boot-optimization"|"110-finalization")
                    bash "$MODULE_SCRIPT" "America/Halifax"
                    ;;
                *)
                    bash "$MODULE_SCRIPT"
                    ;;
            esac
            if [ $? -eq 0 ]; then
                log_info "Module $module completed successfully"
            else
                log_error "Module $module failed"
            fi
        else
            log_error "Module $module not found at $MODULE_SCRIPT - installation incomplete"
            log_error "Available files in $MODULES_DIR:"
            ls -la "$MODULES_DIR" 2>/dev/null || log_error "Directory $MODULES_DIR does not exist"
        fi
    done

    log_info "All modules completed"
}

# Show completion message
show_completion() {
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}║         KIOSKBOOK INSTALLATION COMPLETE!              ║${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"

    HOSTNAME=$(hostname)
    CURRENT_BOOT_TIME=$(systemd-analyze time 2>/dev/null | grep "Startup finished in" | awk '{print $(NF-1), $NF}' || echo "unknown")

    echo -e "\n${CYAN}System Configuration:${NC}"
    echo -e "  Hostname: $HOSTNAME"
    echo -e "  Kiosk User: $KIOSK_USER"
    echo -e "  Application: $GITHUB_REPO"
    echo -e "  App Location: $APP_DIR"
    echo -e "  KioskBook Location: $KIOSKBOOK_DIR"
    echo -e "  Current Boot Time: $CURRENT_BOOT_TIME"

    echo -e "\n${CYAN}Services Status:${NC}"
    systemctl is-active --quiet kiosk-app.service && echo -e "  ${GREEN}✓${NC} kiosk-app.service" || echo -e "  ${RED}✗${NC} kiosk-app.service"
    systemctl is-active --quiet kiosk-browser.service && echo -e "  ${GREEN}✓${NC} kiosk-browser.service" || echo -e "  ${RED}✗${NC} kiosk-browser.service"
    systemctl is-active --quiet tailscaled.service && echo -e "  ${GREEN}✓${NC} tailscaled.service" || echo -e "  ${RED}✗${NC} tailscaled.service"

    echo -e "\n${YELLOW}Management Commands:${NC}"
    echo -e "  Kiosk CLI:         ${CYAN}kiosk status${NC}"
    echo -e "  Check app status:  ${CYAN}systemctl status kiosk-app${NC}"
    echo -e "  Restart app:       ${CYAN}systemctl restart kiosk-app${NC}"
    echo -e "  View app logs:     ${CYAN}journalctl -u kiosk-app -f${NC}"
    echo -e "  Health check:      ${CYAN}kiosk health${NC}"
    echo -e "  Update system:     ${CYAN}kiosk update${NC}"

    echo -e "\n${BLUE}Reboot now?${NC} [y/N]"
    echo -n "> "
    read REBOOT_NOW

    if [ "$REBOOT_NOW" = "y" ] || [ "$REBOOT_NOW" = "Y" ]; then
        echo -e "\n${GREEN}Rebooting in 5 seconds...${NC}"
        sleep 5
        reboot
    else
        echo -e "\n${YELLOW}Remember to reboot manually when ready: ${CYAN}reboot${NC}"
    fi
}

# Main execution
main() {
    show_banner
    get_configuration
    verify_system
    install_base_system
    create_kiosk_user
    clone_kioskbook
    run_modules
    show_completion
}

# Run installation
main "$@"