#!/bin/bash
#
# KioskBook Module: Kiosk Services Configuration
#
# Creates and configures systemd services for kiosk operation.
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
KIOSK_USER="kiosk"
KIOSK_HOME="/home/kiosk"

log_info() {
    echo -e "${GREEN}[SERVICES]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[SERVICES]${NC} $1"
}

log_error() {
    echo -e "${RED}[SERVICES]${NC} $1"
    exit 1
}

# Create kiosk browser service
create_browser_service() {
    log_info "Creating kiosk-browser systemd service..."
    
    cat > /etc/systemd/system/kiosk-browser.service << 'EOF'
[Unit]
Description=Kiosk Browser Service
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple
User=kiosk
Environment=DISPLAY=:0
ExecStart=/usr/bin/chromium --kiosk --start-fullscreen --noerrdialogs --disable-infobars --no-first-run --disable-session-crashed-bubble --disable-features=TranslateUI --check-for-update-interval=31536000 --disable-http-cache --disable-cache --disk-cache-size=1 http://localhost:3000
Restart=always
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF
    
    systemctl daemon-reload
    systemctl enable kiosk-browser.service
    
    log_info "Kiosk-browser service created"
}

# Configure auto-login for kiosk user
configure_autologin() {
    log_info "Configuring auto-login for kiosk user..."
    
    # Configure getty for auto-login
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
EOF
    
    # Configure display manager (if using one)
    if [ -f /etc/lightdm/lightdm.conf ]; then
        sed -i 's/#autologin-user=/autologin-user=kiosk/' /etc/lightdm/lightdm.conf
        sed -i 's/#autologin-user-timeout=0/autologin-user-timeout=0/' /etc/lightdm/lightdm.conf
    fi
    
    log_info "Auto-login configured"
}

# Create X11 session configuration
create_x11_session() {
    log_info "Creating X11 session configuration..."
    
    # Create desktop session file
    mkdir -p /usr/share/xsessions/
    cat > /usr/share/xsessions/kiosk.desktop << 'EOF'
[Desktop Entry]
Name=Kiosk
Comment=Kiosk Display
Exec=startx
Type=Application
EOF
    
    # Ensure kiosk user has proper X11 setup
    cat > $KIOSK_HOME/.xinitrc << 'EOF'
#!/bin/bash
# KioskBook X11 Configuration

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor after 0.1 seconds
unclutter -idle 0.1 &

# Wait for kiosk app to be ready
echo "Waiting for kiosk app..."
while ! curl -s http://localhost:3000 > /dev/null; do
    sleep 1
done

# Detect display resolution
RESOLUTION=$(xrandr | grep '\*' | awk '{print $1}' | head -1)
WIDTH=$(echo $RESOLUTION | cut -d'x' -f1)
HEIGHT=$(echo $RESOLUTION | cut -d'x' -f2)

echo "Starting kiosk browser at ${WIDTH}x${HEIGHT}"

# Launch Chromium in kiosk mode
exec chromium --kiosk --start-fullscreen --window-size=$WIDTH,$HEIGHT \
    --noerrdialogs --disable-infobars --no-first-run \
    --disable-session-crashed-bubble --disable-features=TranslateUI \
    --check-for-update-interval=31536000 \
    --disable-http-cache --disable-cache --disk-cache-size=1 \
    http://localhost:3000
EOF
    chmod +x $KIOSK_HOME/.xinitrc
    
    # Configure bash profile to start X
    cat > $KIOSK_HOME/.bash_profile << 'EOF'
# KioskBook Auto-start Configuration
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF
    
    chown -R $KIOSK_USER:$KIOSK_USER $KIOSK_HOME
    
    log_info "X11 session configuration created"
}

# Configure service restart policies
configure_restart_policies() {
    log_info "Configuring service restart policies..."
    
    # Kiosk app service restart policy
    mkdir -p /etc/systemd/system/kiosk-app.service.d/
    cat > /etc/systemd/system/kiosk-app.service.d/restart.conf << EOF
[Service]
Restart=always
RestartSec=10
StartLimitInterval=0
EOF
    
    # Kiosk browser service restart policy
    mkdir -p /etc/systemd/system/kiosk-browser.service.d/
    cat > /etc/systemd/system/kiosk-browser.service.d/restart.conf << EOF
[Service]
Restart=always
RestartSec=10
StartLimitInterval=0
EOF
    
    systemctl daemon-reload
    
    log_info "Restart policies configured"
}

# Main function
main() {
    echo -e "${CYAN}=== Kiosk Services Module ===${NC}"
    
    create_browser_service
    configure_autologin
    create_x11_session
    configure_restart_policies
    
    log_info "Kiosk services configuration complete"
    log_info "Services will start automatically after reboot"
}

main "$@"
