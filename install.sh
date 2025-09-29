#!/bin/bash
#
# KioskBook: Complete Kiosk Installation
#
# Transforms a minimal Debian system into a fast-booting (<10s), self-recovering
# kiosk running Vue.js applications in full-screen Chromium.
#
# Prerequisites:
# - Minimal Debian installation (tested on Debian 13/trixie)
# - Root access
# - Internet connection
# - Node.js and npm installed
#
# Usage: bash install.sh
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

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║                                                       ║"
    echo "║                  KIOSKBOOK INSTALLER                  ║"
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

    # GitHub repo for Vue.js application
    echo -e "${CYAN}Vue.js application git repository${NC}"
    echo -n -e "(default: https://github.com/kenzie/lobby-display): "
    read GITHUB_REPO
    if [ -z "$GITHUB_REPO" ]; then
        GITHUB_REPO="https://github.com/kenzie/lobby-display"
        log_info "Using default repository: $GITHUB_REPO"
    fi

    # Tailscale auth key
    echo -e "\n${CYAN}Tailscale auth key for remote access${NC}"
    echo -n -e "(required - get from https://login.tailscale.com/admin/settings/keys): "
    read TAILSCALE_KEY
    if [ -z "$TAILSCALE_KEY" ]; then
        log_error "Tailscale auth key is required for remote management"
    fi
}

# Show summary and confirm
show_summary() {
    log_step "Installation Summary"

    HOSTNAME=$(hostname)
    echo -e "${CYAN}Hostname:${NC}         $HOSTNAME"
    echo -e "${CYAN}Timezone:${NC}         $TIMEZONE"
    echo -e "${CYAN}Kiosk User:${NC}       $KIOSK_USER"
    echo -e "${CYAN}Application:${NC}      $GITHUB_REPO"
    echo -e "${CYAN}App Directory:${NC}    $APP_DIR"
    echo -e "${CYAN}Tailscale:${NC}        Enabled"
    echo -e "${CYAN}SSH Access:${NC}       Enabled (root)"

    echo -e "\n${YELLOW}This will install:${NC}"
    echo -e "  - X11 display server"
    echo -e "  - Chromium browser (kiosk mode)"
    echo -e "  - Vue.js application from GitHub"
    echo -e "  - Tailscale VPN"
    echo -e "  - Auto-login and kiosk services"
    echo -e "  - Boot optimization (<10s target)"

    echo -e "\n${GREEN}Ready to proceed?${NC} [y/N]"
    echo -n "> "
    read CONFIRM

    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        log_error "Installation cancelled"
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

    # Check for AMD GPU
    if lspci | grep -i amd | grep -i vga >/dev/null 2>&1; then
        GPU_INFO=$(lspci | grep -i amd | grep -i vga | head -1)
        log_info "AMD GPU detected: $(echo $GPU_INFO | cut -d: -f3)"
    else
        log_warn "No AMD GPU detected - may have display issues"
    fi

    # Check network
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No network connectivity - internet required"
    fi
    log_info "Network connectivity ✓"

    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js not found - please install Node.js first"
    fi
    NODE_VERSION=$(node --version)
    log_info "Node.js $NODE_VERSION ✓"

    # Check npm
    if ! command -v npm &> /dev/null; then
        log_error "npm not found - please install npm first"
    fi
    NPM_VERSION=$(npm --version)
    log_info "npm $NPM_VERSION ✓"
}

# Optimize boot sequence
optimize_boot() {
    log_step "Optimizing Boot Sequence"

    # Configure GRUB for instant boot
    log_info "Configuring GRUB for fast boot..."
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 vga=current"/' /etc/default/grub
    update-grub

    # Disable unnecessary services
    log_info "Disabling unnecessary services..."
    systemctl disable bluetooth.service 2>/dev/null || true
    systemctl disable cups.service 2>/dev/null || true
    systemctl disable ModemManager.service 2>/dev/null || true
    systemctl mask plymouth-quit-wait.service 2>/dev/null || true

    log_info "Boot optimization complete"
}

# Install display stack
install_display_stack() {
    log_step "Installing Display Stack"

    log_info "Installing X11 and Chromium..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        xorg \
        xserver-xorg-video-amdgpu \
        chromium \
        chromium-driver \
        unclutter \
        x11-xserver-utils

    log_info "Display stack installed"
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

    # Configure auto-login
    log_info "Configuring auto-login..."
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF

    # Create .xinitrc for kiosk user
    cat > $KIOSK_HOME/.xinitrc << 'EOF'
#!/bin/bash
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor
unclutter -idle 0.1 &

# Wait for kiosk app to be ready
while ! curl -s http://localhost:3000 > /dev/null; do
    sleep 1
done

# Launch Chromium in kiosk mode
chromium --kiosk --noerrdialogs --disable-infobars --no-first-run \
    --disable-session-crashed-bubble --disable-features=TranslateUI \
    --check-for-update-interval=31536000 http://localhost:3000
EOF
    chmod +x $KIOSK_HOME/.xinitrc

    # Configure .bash_profile to start X
    cat > $KIOSK_HOME/.bash_profile << 'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF

    chown -R $KIOSK_USER:$KIOSK_USER $KIOSK_HOME

    log_info "Kiosk user configured with auto-login"
}

# Install and configure Vue.js application
install_application() {
    log_step "Installing Vue.js Application"

    # Clone repository
    log_info "Cloning application from $GITHUB_REPO..."
    if [ -d "$APP_DIR" ]; then
        log_warn "App directory exists, removing..."
        rm -rf $APP_DIR
    fi

    git clone $GITHUB_REPO $APP_DIR
    cd $APP_DIR

    # Install dependencies
    log_info "Installing npm dependencies..."
    npm install

    # Build application
    log_info "Building production bundle..."
    if npm run build 2>/dev/null; then
        log_info "Build successful"
        # Check if dist directory exists
        if [ -d "dist" ]; then
            USE_DIST=true
        else
            USE_DIST=false
        fi
    else
        log_warn "Build failed or no build script, will serve in dev mode"
        USE_DIST=false
    fi

    # Create systemd service for app
    log_info "Creating kiosk-app service..."
    if [ "$USE_DIST" = true ]; then
        # Serve built files with http-server
        npm install -g http-server
        cat > /etc/systemd/system/kiosk-app.service << EOF
[Unit]
Description=Kiosk Vue.js Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR/dist
ExecStart=/usr/local/bin/http-server -p 3000
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

    systemctl daemon-reload
    systemctl enable kiosk-app.service
    systemctl start kiosk-app.service

    log_info "Application installed and started"
}

# Install and configure Tailscale
install_tailscale() {
    log_step "Installing Tailscale VPN"

    # Add Tailscale repository
    log_info "Adding Tailscale repository..."
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

    # Install Tailscale
    log_info "Installing Tailscale..."
    apt-get update
    apt-get install -y tailscale

    # Authenticate Tailscale
    log_info "Authenticating Tailscale..."
    tailscale up --authkey=$TAILSCALE_KEY --accept-routes --ssh

    log_info "Tailscale VPN configured"
}

# Setup monitoring and recovery
setup_monitoring() {
    log_step "Setting Up Monitoring & Recovery"

    # Create health check script
    log_info "Creating health check script..."
    if [ -f "$SCRIPT_DIR/config/kiosk-health-check.sh" ]; then
        cp $SCRIPT_DIR/config/kiosk-health-check.sh /opt/kiosk-health-check.sh
        chmod +x /opt/kiosk-health-check.sh
    else
        # Create basic health check
        cat > /opt/kiosk-health-check.sh << 'EOF'
#!/bin/bash
# Basic kiosk health check

# Check if kiosk app is responding
if ! curl -s http://localhost:3000 > /dev/null; then
    echo "ERROR: Kiosk app not responding"
    systemctl restart kiosk-app.service
fi

# Check if X is running
if ! pgrep -u kiosk X > /dev/null; then
    echo "ERROR: X server not running"
fi

echo "Health check complete"
EOF
        chmod +x /opt/kiosk-health-check.sh
    fi

    # Configure service restart policies
    log_info "Configuring service restart policies..."
    mkdir -p /etc/systemd/system/kiosk-app.service.d/
    cat > /etc/systemd/system/kiosk-app.service.d/restart.conf << EOF
[Service]
Restart=always
RestartSec=10
StartLimitInterval=0
EOF

    systemctl daemon-reload

    log_info "Monitoring and recovery configured"
}

# Finalize installation
finalize_installation() {
    log_step "Finalizing Installation"

    # Set timezone
    log_info "Setting timezone to $TIMEZONE..."
    timedatectl set-timezone $TIMEZONE

    # Sync filesystems
    sync

    log_info "Installation finalized"
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
    echo -e "  Current Boot Time: $CURRENT_BOOT_TIME"

    echo -e "\n${CYAN}Services Status:${NC}"
    systemctl is-active --quiet kiosk-app.service && echo -e "  ${GREEN}✓${NC} kiosk-app.service" || echo -e "  ${RED}✗${NC} kiosk-app.service"
    systemctl is-active --quiet tailscaled.service && echo -e "  ${GREEN}✓${NC} tailscaled.service" || echo -e "  ${RED}✗${NC} tailscaled.service"

    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo -e "  1. Reboot the system: ${CYAN}reboot${NC}"
    echo -e "  2. System will auto-login as $KIOSK_USER and start kiosk"
    echo -e "  3. Monitor via Tailscale SSH or local access"

    echo -e "\n${YELLOW}Management Commands:${NC}"
    echo -e "  Check app status:  ${CYAN}systemctl status kiosk-app${NC}"
    echo -e "  Restart app:       ${CYAN}systemctl restart kiosk-app${NC}"
    echo -e "  View app logs:     ${CYAN}journalctl -u kiosk-app -f${NC}"
    echo -e "  Health check:      ${CYAN}/opt/kiosk-health-check.sh${NC}"
    echo -e "  Update app:        ${CYAN}cd $APP_DIR && git pull && npm install${NC}"

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
    show_summary
    verify_system
    optimize_boot
    install_display_stack
    create_kiosk_user
    install_application
    install_tailscale
    setup_monitoring
    finalize_installation
    show_completion
}

# Run installation
main "$@"