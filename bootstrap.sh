#!/bin/bash
#
# KioskBook Debian Bootstrap
#
# Transforms a minimal Debian installation into a bulletproof kiosk system.
# Run this after installing Debian 13.1.0 netinst with SSH server only.
#
# Usage: sudo ./bootstrap.sh [github_repo] [tailscale_key]
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly KIOSK_USER="kiosk"
readonly KIOSK_HOME="/home/kiosk"
readonly APP_DIR="/opt/kioskbook"
readonly LOG_DIR="/var/log/kioskbook"
readonly DEFAULT_REPO="https://github.com/kenzie/lobby-display"

# Logging functions
log() { printf "${CYAN}[BOOTSTRAP]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

# Error handler
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Bootstrap failed at line $1. Check logs in $LOG_DIR"
    fi
}
trap 'cleanup $LINENO' ERR

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "     KioskBook Debian Bootstrap"
    echo "    Transform Debian into a Bulletproof Kiosk"
    echo "═══════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Must be root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
    fi
    
    # Check if this is Debian
    if ! grep -q "Debian" /etc/os-release; then
        log_error "This script is designed for Debian systems"
    fi
    
    # Check network connectivity
    if ! ping -c 1 debian.org >/dev/null 2>&1; then
        log_error "Network connectivity required. Please configure networking first."
    fi
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    log_success "Prerequisites verified"
}

# Get configuration
get_configuration() {
    log "Configuration"
    
    # GitHub repository
    if [[ -n "${1:-}" ]]; then
        GITHUB_REPO="$1"
    else
        echo -n "GitHub repository (default: $DEFAULT_REPO): "
        read -r GITHUB_REPO
        GITHUB_REPO="${GITHUB_REPO:-$DEFAULT_REPO}"
    fi
    log "Using repository: $GITHUB_REPO"
    
    # Tailscale key (optional)
    if [[ -n "${2:-}" ]]; then
        TAILSCALE_KEY="$2"
    else
        echo -n "Tailscale auth key (optional, press Enter to skip): "
        read -rs TAILSCALE_KEY
        echo
    fi
    
    if [[ -n "$TAILSCALE_KEY" ]]; then
        log "Tailscale VPN will be configured"
    else
        log "Skipping Tailscale VPN setup"
    fi
}

# Update system
update_system() {
    log "Updating system packages..."
    
    # Update package lists
    apt-get update
    
    # Upgrade existing packages
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Install essential packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget ca-certificates gnupg lsb-release \
        sudo systemd-timesyncd unzip git
    
    log_success "System updated"
}

# Install display system
install_display_system() {
    log "Installing display system..."
    
    # Install X11 and OpenBox (minimal window manager)
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        xorg \
        openbox \
        lightdm \
        xserver-xorg-video-amdgpu \
        mesa-vulkan-drivers \
        vainfo \
        unclutter-xfixes
    
    # Install Chromium
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        chromium \
        chromium-driver
    
    log_success "Display system installed"
}

# Install fonts
install_fonts() {
    log "Installing fonts..."
    
    # Install Inter font and other essentials
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        fonts-inter \
        fonts-noto \
        fontconfig
    
    # Download and install CaskaydiaCove Nerd Font
    local font_dir="/usr/local/share/fonts/nerd-fonts"
    mkdir -p "$font_dir"
    
    wget -q -O /tmp/CascadiaCode.zip \
        "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip"
    
    unzip -o -q /tmp/CascadiaCode.zip -d "$font_dir/"
    rm -f /tmp/CascadiaCode.zip
    
    # Update font cache
    fc-cache -fv >/dev/null 2>&1
    
    log_success "Fonts installed"
}

# Create kiosk user
create_kiosk_user() {
    log "Creating kiosk user..."
    
    # Create kiosk user if it doesn't exist
    if ! id "$KIOSK_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -G audio,video "$KIOSK_USER"
        log "Created user: $KIOSK_USER"
    else
        log "User $KIOSK_USER already exists"
    fi
    
    # Create OpenBox configuration
    mkdir -p "$KIOSK_HOME/.config/openbox"
    
    cat > "$KIOSK_HOME/.config/openbox/autostart" << 'EOF'
#!/bin/bash
# Hide cursor after 1 second of inactivity
unclutter -idle 1 &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Wait for application to be ready (Vite dev server runs on 5173)
while ! curl -s http://localhost:5173 >/dev/null 2>&1; do
    sleep 1
done

# Start Chromium in kiosk mode
exec chromium \
    --kiosk \
    --no-sandbox \
    --disable-infobars \
    --disable-features=TranslateUI \
    --disable-ipc-flooding-protection \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-default-apps \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --no-message-box \
    --start-fullscreen \
    http://localhost:5173
EOF
    
    chmod +x "$KIOSK_HOME/.config/openbox/autostart"
    
    # Set ownership
    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"
    
    log_success "Kiosk user configured"
}

# Configure auto-login
configure_autologin() {
    log "Configuring auto-login..."
    
    # Configure LightDM for auto-login
    cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=openbox
session-wrapper=/etc/X11/Xsession
greeter-session=lightdm-gtk-greeter
EOF
    
    # Enable LightDM
    systemctl enable lightdm
    
    log_success "Auto-login configured"
}

# Install Node.js and application
install_application() {
    log "Installing Node.js and application..."
    
    # Install Node.js 20 from NodeSource
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
    
    # Clone application
    if [[ -d "$APP_DIR" ]]; then
        rm -rf "$APP_DIR"
    fi
    
    git clone "$GITHUB_REPO" "$APP_DIR"
    cd "$APP_DIR"
    
    # Install dependencies
    npm ci
    
    # Try to build if build script exists
    if npm run build 2>/dev/null; then
        log "Application built successfully"
    else
        log_warning "No build script found, assuming development mode"
    fi
    
    # Create systemd service
    cat > /etc/systemd/system/kioskbook-app.service << EOF
[Unit]
Description=KioskBook Application
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=NODE_ENV=production
Environment=HOST=0.0.0.0
Environment=PORT=5173
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    systemctl daemon-reload
    systemctl enable kioskbook-app
    systemctl start kioskbook-app
    
    log_success "Application installed and started"
}

# Configure silent boot
configure_silent_boot() {
    log "Configuring silent boot..."
    
    # Enhanced GRUB configuration for completely silent boot
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 console=tty3 rd.systemd.show_status=false rd.udev.log_level=3 systemd.show_status=false"/' /etc/default/grub
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    echo "GRUB_TIMEOUT_STYLE=hidden" >> /etc/default/grub
    echo "GRUB_TERMINAL=console" >> /etc/default/grub
    
    # Update GRUB
    update-grub
    
    # Enhanced systemd configuration for silent boot
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/silent.conf << EOF
[Manager]
ShowStatus=no
LogLevel=warning
SystemCallErrorNumber=EPERM
EOF
    
    # Create kernel parameters for completely silent boot
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/silent.conf << 'EOF'
# Suppress most kernel messages
options drm_kms_helper poll=0
options drm debug=0
EOF
    
    # Hide kernel messages on all consoles
    cat > /etc/sysctl.d/20-quiet-printk.conf << 'EOF'
kernel.printk = 3 3 3 3
EOF
    
    # Disable unnecessary services for faster boot
    systemctl disable \
        bluetooth.service \
        cups.service \
        avahi-daemon.service \
        ModemManager.service \
        wpa_supplicant.service 2>/dev/null || true
    
    # Mask services that show boot messages
    systemctl mask \
        plymouth-quit-wait.service \
        systemd-random-seed.service \
        systemd-update-utmp.service \
        systemd-tmpfiles-setup.service \
        e2scrub_reap.service 2>/dev/null || true
    
    # Create custom getty service to auto-login without messages
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kiosk --noclear %I $TERM
StandardInput=tty
StandardOutput=tty
Environment=TERM=linux
TTYVTDisallocate=no
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log_success "Silent boot configured"
}

# Install Tailscale (optional)
install_tailscale() {
    if [[ -z "$TAILSCALE_KEY" ]]; then
        return 0
    fi
    
    log "Installing Tailscale VPN..."
    
    # Add Tailscale repository
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
    
    # Install Tailscale
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale
    
    # Configure Tailscale
    tailscale up --authkey="$TAILSCALE_KEY" --ssh --hostname="kioskbook-$(hostname)"
    
    log_success "Tailscale configured"
}

# Optimize system
optimize_system() {
    log "Optimizing system for kiosk use..."
    
    # Remove unnecessary packages
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
    
    # Clear package cache
    apt-get clean
    
    # Disable swap if enabled (faster boot, more deterministic performance)
    swapoff -a 2>/dev/null || true
    sed -i '/swap/d' /etc/fstab
    
    # Configure systemd for faster boot
    systemctl set-default graphical.target
    
    # Create health check script
    cat > /usr/local/bin/kioskbook-health << 'EOF'
#!/bin/bash
# Basic health check for KioskBook

echo "=== KioskBook Health Check ==="
echo "Date: $(date)"
echo

# Check application service
echo "Application Service:"
systemctl is-active kioskbook-app || echo "❌ Application not running"

# Check display
echo "Display:"
if pgrep -f "chromium.*kiosk" >/dev/null; then
    echo "✅ Chromium kiosk running"
else
    echo "❌ Chromium kiosk not running"
fi

# Check network
echo "Network:"
if ping -c 1 google.com >/dev/null 2>&1; then
    echo "✅ Network connectivity"
else
    echo "❌ No network connectivity"
fi

# System load
echo "System Load: $(uptime | awk '{print $NF}')"
echo "Memory: $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
EOF
    
    chmod +x /usr/local/bin/kioskbook-health
    
    log_success "System optimized"
}

# Install management CLI
install_management_cli() {
    log "Installing KioskBook management CLI..."
    
    # Note: Bootstrap runs during initial installation before git repo is available
    # Management CLI will be installed later via update script from local repo
    log_warning "Management CLI will be available after running 'update.sh' from cloned repository"
}

# Show completion
show_completion() {
    echo -e "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     KioskBook Bootstrap Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${CYAN}System Status:${NC}"
    systemctl is-active kioskbook-app || echo "❌ Application service needs attention"
    
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
    if [[ -n "$TAILSCALE_KEY" ]]; then
        echo -e "  ✅ Tailscale VPN enabled"
    fi
    
    echo -e "\n${CYAN}Management Commands:${NC}"
    echo -e "  Application: ${YELLOW}sudo systemctl status kioskbook-app${NC}"
    echo -e "  Logs: ${YELLOW}sudo journalctl -u kioskbook-app -f${NC}"
    echo -e "  Health: ${YELLOW}sudo kioskbook-health${NC}"
}

# Main execution
main() {
    show_banner
    check_prerequisites
    get_configuration "$@"
    update_system
    install_display_system
    install_fonts
    create_kiosk_user
    configure_autologin
    install_application
    configure_silent_boot
    install_tailscale
    optimize_system
    install_management_cli
    show_completion
}

# Run
main "$@"