#!/bin/ash
#
# KioskBook Alpine Setup - Part 2
#
# Configures Alpine Linux as a bulletproof kiosk system.
# Run this after booting into the base system installed by bootstrap.sh.
#
# Usage: ./setup.sh [github_repo] [tailscale_key]
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
KIOSK_USER="kiosk"
KIOSK_HOME="/home/kiosk"
APP_DIR="/opt/kiosk-app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default values
DEFAULT_REPO="https://github.com/kenzie/lobby-display"

# Logging
log() { printf "${CYAN}[SETUP]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "       KioskBook Alpine Setup - Part 2"  
    echo "    Transform Alpine into a Bulletproof Kiosk"
    echo "═══════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# Get configuration
get_configuration() {
    log "Configuration"
    
    # GitHub repo
    if [ -n "$1" ]; then
        GITHUB_REPO="$1"
    else
        echo -n "GitHub repository (default: $DEFAULT_REPO): "
        read GITHUB_REPO
        if [ -z "$GITHUB_REPO" ]; then
            GITHUB_REPO="$DEFAULT_REPO"
        fi
    fi
    log "Using repository: $GITHUB_REPO"
    
    # Tailscale key (optional)
    if [ -n "$2" ]; then
        TAILSCALE_KEY="$2"
    else
        echo -n "Tailscale auth key (optional, press Enter to skip): "
        read -s TAILSCALE_KEY
        echo
    fi
    
    if [ -n "$TAILSCALE_KEY" ]; then
        log "Tailscale VPN will be configured"
    else
        log "Skipping Tailscale VPN setup"
    fi
}

# Update system
update_system() {
    log "Updating system packages..."
    
    # Ensure repositories are configured
    if ! grep -q "community" /etc/apk/repositories; then
        echo "http://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /etc/apk/repositories
    fi
    
    apk update
    apk upgrade
    
    log_success "System updated"
}

# Install base packages
install_base_packages() {
    log "Installing base packages..."
    
    # Install packages individually to avoid one failure breaking everything
    local packages="bash git curl wget htop nano util-linux pciutils usbutils coreutils shadow sudo openrc openssh ca-certificates tzdata"
    
    for pkg in $packages; do
        if apk add "$pkg" 2>/dev/null; then
            log "✓ Installed $pkg"
        else
            log_warning "✗ Failed to install $pkg (package may not exist)"
        fi
    done
    
    # Try busybox-init instead of busybox-initscripts
    if ! apk add busybox-initscripts 2>/dev/null; then
        log_warning "busybox-initscripts not found, trying alternatives..."
        apk add busybox-init 2>/dev/null || apk add busybox 2>/dev/null || log_warning "Could not install busybox init scripts"
    fi
        
    log_success "Base packages installation completed"
}

# Install display stack
install_display() {
    log "Installing display stack..."
    
    # Install X11 and drivers
    apk add \
        xorg-server \
        xf86-input-libinput \
        xf86-video-amdgpu \
        mesa-dri-gallium \
        mesa-va-gallium \
        xset \
        xrandr \
        xinit
    
    # Install Chromium
    apk add \
        chromium \
        chromium-chromedriver \
        ttf-freefont \
        font-noto
    
    # Install additional tools
    apk add \
        unclutter-xfixes \
        xdotool
    
    log_success "Display stack installed"
}

# Install fonts
install_fonts() {
    log "Installing fonts..."
    
    # Install Inter font
    apk add font-inter
    
    # Install Nerd Fonts
    mkdir -p /usr/share/fonts/nerd-fonts
    cd /tmp
    
    # Clean any existing files first
    rm -f CascadiaCode.zip 2>/dev/null || true
    rm -rf /usr/share/fonts/nerd-fonts/* 2>/dev/null || true
    
    # Download CascadiaCode font
    log "Downloading CascadiaCode Nerd Font..."
    wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip
    
    # Extract fonts using unzip with force overwrite
    log "Extracting fonts..."
    unzip -o -q CascadiaCode.zip -d /usr/share/fonts/nerd-fonts/
    
    # Clean up
    rm -f CascadiaCode.zip
    
    # Update font cache
    fc-cache -fv >/dev/null 2>&1
    
    log_success "Fonts installed"
}

# Create kiosk user
create_kiosk_user() {
    log "Creating kiosk user..."
    
    # Check if user already exists and clean up if needed
    if id "$KIOSK_USER" >/dev/null 2>&1; then
        log "Kiosk user already exists, removing for clean setup..."
        
        # Kill any processes owned by kiosk user
        pkill -u "$KIOSK_USER" 2>/dev/null || true
        
        # Remove user from groups
        deluser "$KIOSK_USER" users 2>/dev/null || true
        deluser "$KIOSK_USER" audio 2>/dev/null || true
        deluser "$KIOSK_USER" video 2>/dev/null || true
        
        # Remove user and home directory
        deluser --remove-home "$KIOSK_USER" 2>/dev/null || true
        
        # Clean up any remaining files
        rm -rf "$KIOSK_HOME" 2>/dev/null || true
        
        # Wait for cleanup
        sleep 1
    fi
    
    # Create user with error checking
    if adduser -D -s /bin/bash $KIOSK_USER; then
        log_success "Kiosk user '$KIOSK_USER' created successfully"
    else
        log_error "Failed to create kiosk user '$KIOSK_USER'"
        exit 1
    fi
    
    # Verify user was created
    if ! id "$KIOSK_USER" >/dev/null 2>&1; then
        log_error "Kiosk user '$KIOSK_USER' was not created properly"
        exit 1
    fi
    
    # Configure auto-login for Alpine
    log "Configuring auto-login using inittab method..."
    
    # Backup original inittab
    cp /etc/inittab /etc/inittab.backup 2>/dev/null || true
    
    # Use Alpine's correct auto-login method
    if command -v agetty >/dev/null; then
        # Alpine uses agetty for auto-login
        if sed -i "s/^tty1:.*/tty1::respawn:\/sbin\/agetty --autologin $KIOSK_USER --noclear tty1 linux/" /etc/inittab; then
            log_success "Auto-login configured with agetty"
        else
            log_error "Failed to configure agetty auto-login"
            exit 1
        fi
    else
        # Fallback to simple su method (most reliable)
        log "agetty not found, using su method..."
        if sed -i "s/^tty1:.*/tty1::respawn:\/bin\/su - $KIOSK_USER/" /etc/inittab; then
            log_success "Auto-login configured with su method"
        else
            log_error "Failed to configure su auto-login"
            exit 1
        fi
    fi
    
    # Verify the auto-login configuration
    if grep -q "$KIOSK_USER" /etc/inittab; then
        log "Verified: Auto-login entry found in inittab"
        log "Auto-login line: $(grep tty1 /etc/inittab)"
    else
        log_error "Auto-login verification failed"
        exit 1
    fi
    
    # Create .xinitrc
    cat > $KIOSK_HOME/.xinitrc << 'EOF'
#!/bin/sh
# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor  
unclutter -idle 0.1 &

# Wait for app
while ! nc -z localhost 3000; do
    sleep 1
done

# Get display size
RESOLUTION=$(xrandr | grep '\*' | awk '{print $1}' | head -1)

# Launch Chromium
exec chromium \
    --kiosk \
    --start-fullscreen \
    --window-size=$RESOLUTION \
    --noerrdialogs \
    --disable-infobars \
    --no-first-run \
    --check-for-update-interval=31536000 \
    --disable-features=TranslateUI \
    http://localhost:3000
EOF
    chmod +x $KIOSK_HOME/.xinitrc
    
    # Configure auto-startx
    cat > $KIOSK_HOME/.profile << 'EOF'
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
EOF
    
    # Set ownership and verify
    chown -R $KIOSK_USER:$KIOSK_USER $KIOSK_HOME
    
    # Verify files were created correctly
    if [ -f "$KIOSK_HOME/.xinitrc" ] && [ -f "$KIOSK_HOME/.profile" ]; then
        log_success "Kiosk user configured with X11 auto-start"
    else
        log_error "Failed to create kiosk user configuration files"
        exit 1
    fi
    
    # Final verification of auto-login setup
    if grep -q "getty -a $KIOSK_USER" /etc/inittab; then
        log_success "Auto-login verified in /etc/inittab"
    else
        log_warning "Auto-login verification failed - manual setup may be required"
    fi
}

# Install Node.js
install_nodejs() {
    log "Installing Node.js..."
    
    apk add nodejs npm
    
    log_success "Node.js installed"
}

# Install application
install_application() {
    log "Installing application..."
    
    # Clone repository
    if [ -d "$APP_DIR" ]; then
        rm -rf $APP_DIR
    fi
    
    git clone $GITHUB_REPO $APP_DIR
    cd $APP_DIR
    
    # Install dependencies
    npm install
    
    # Try to build
    if npm run build 2>/dev/null; then
        log "Application built successfully"
    fi
    
    # Create OpenRC service
    cat > /etc/init.d/kiosk-app << 'EOF'
#!/sbin/openrc-run

name="Kiosk Application"
description="Vue.js kiosk application"

command="/usr/bin/npm"
command_args="run dev"
command_background=true
pidfile="/run/kiosk-app.pid"
directory="/opt/kiosk-app"

start_pre() {
    export HOST="0.0.0.0"
    export PORT="3000"
}

depend() {
    need networking
}
EOF
    chmod +x /etc/init.d/kiosk-app
    
    # Enable service
    rc-update add kiosk-app default
    rc-service kiosk-app start
    
    log_success "Application installed and started"
}

# Configure silent boot (Alpine native)
configure_silent_boot() {
    log "Configuring silent boot..."
    
    # Configure silent boot parameters in bootloader
    if [ -f /boot/extlinux.conf ]; then
        log "Configuring extlinux for silent boot..."
        # Create backup
        cp /boot/extlinux.conf /boot/extlinux.conf.backup
        
        # Add comprehensive silent boot parameters
        sed -i 's/APPEND.*/& quiet loglevel=1 console=ttyS0 rd.systemd.show_status=false rd.udev.log_level=1/' /boot/extlinux.conf
        
        log "Updated extlinux.conf:"
        grep APPEND /boot/extlinux.conf
    elif [ -f /etc/update-extlinux.conf ]; then
        log "Configuring update-extlinux for silent boot..."
        # Update Alpine's extlinux configuration
        sed -i 's/^default_kernel_opts=.*/default_kernel_opts="quiet loglevel=1 console=ttyS0"/' /etc/update-extlinux.conf
        update-extlinux
        log "Updated kernel options via update-extlinux"
    else
        log_warning "No bootloader configuration found"
    fi
    
    # Suppress OpenRC service messages
    echo 'rc_logger="YES"' >> /etc/rc.conf
    echo 'rc_log_path="/dev/null"' >> /etc/rc.conf
    echo 'rc_verbose="NO"' >> /etc/rc.conf
    
    # Hide kernel messages
    echo 'kernel.printk = 1 1 1 1' >> /etc/sysctl.conf
    
    # Disable getty on other ttys to reduce noise
    sed -i 's/^tty[2-6]/#&/' /etc/inittab
    
    log_success "Silent boot configured - suppressed OpenRC and kernel messages"
}

# Optimize boot
optimize_boot() {
    log "Optimizing boot sequence..."
    
    # Disable unnecessary services
    rc-update del acpid default 2>/dev/null || true
    rc-update del crond default 2>/dev/null || true
    
    # Configure kernel parameters for faster boot
    if [ -f /boot/extlinux.conf ]; then
        sed -i 's/APPEND.*/& quiet loglevel=3/' /boot/extlinux.conf
    fi
    
    log_success "Boot optimized"
}

# Install Tailscale (if key provided)
install_tailscale() {
    if [ -z "$TAILSCALE_KEY" ]; then
        return
    fi
    
    log "Installing Tailscale VPN..."
    
    # Tailscale isn't in Alpine repos, install manually
    cd /tmp
    wget -q https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz
    tar xzf tailscale_latest_amd64.tgz
    cp tailscale_*_amd64/tailscale /usr/bin/
    cp tailscale_*_amd64/tailscaled /usr/sbin/
    
    # Create service
    cat > /etc/init.d/tailscaled << 'EOF'
#!/sbin/openrc-run

name="Tailscale Daemon"
command="/usr/sbin/tailscaled"
command_background=true
pidfile="/run/tailscaled.pid"

depend() {
    need net
}
EOF
    chmod +x /etc/init.d/tailscaled
    
    # Start and configure
    rc-service tailscaled start
    tailscale up --authkey=$TAILSCALE_KEY --ssh
    
    rc-update add tailscaled default
    
    log_success "Tailscale configured"
}

# Finalize
finalize() {
    log "Finalizing installation..."
    
    # Set timezone
    setup-timezone -z America/Halifax
    
    # Remove setup marker
    rm -f /root/.needs_kiosk_setup
    
    log_success "Installation finalized"
}

# Show completion
show_completion() {
    echo -e "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}      KioskBook Installation Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${CYAN}System Status:${NC}"
    rc-service kiosk-app status
    
    echo -e "\n${CYAN}Next Steps:${NC}"
    echo -e "1. Reboot: ${YELLOW}reboot${NC}"
    echo -e "2. System will auto-login and start kiosk"
    
    echo -e "\n${CYAN}Management Commands:${NC}"
    echo -e "  Check app:    ${YELLOW}rc-service kiosk-app status${NC}"
    echo -e "  Restart app:  ${YELLOW}rc-service kiosk-app restart${NC}"
    echo -e "  App logs:     ${YELLOW}cat /var/log/messages | grep kiosk${NC}"
}

# Main execution
main() {
    show_banner
    
    # Check if this is first run after bootstrap
    if [ ! -f "/root/.needs_kiosk_setup" ] && [ "$1" != "--force" ]; then
        log_warning "System appears to be already configured"
        echo -n "Continue anyway? [y/N]: "
        read CONFIRM
        if [ "$CONFIRM" != "y" ]; then
            exit 0
        fi
    fi
    
    get_configuration "$@"
    update_system
    install_base_packages
    install_display
    install_fonts
    create_kiosk_user
    install_nodejs
    install_application
    configure_silent_boot
    optimize_boot
    install_tailscale
    finalize
    show_completion
}

# Run
main "$@"