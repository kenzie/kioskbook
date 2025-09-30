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

# Create boot splash script
create_boot_splash_script() {
    log_info "Creating boot splash script..."
    
    cat > "$SPLASH_DIR/boot-splash.sh" << 'EOF'
#!/bin/sh
# KioskBook Boot Splash Screen with Route 19 Logo

# Clear screen and set colors
clear
echo -e "\033[2J\033[H"

# Show Route 19 logo/startup message
echo -e "\033[1;33m"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║                                                       ║"
echo "║                     ROUTE 19                          ║"
echo "║                                                       ║"
echo "║                  KIOSKBOOK                            ║"
echo "║                                                       ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "\033[0m"
echo
echo -e "\033[1;37mStarting KioskBook...\033[0m"

# Try to display Route 19 logo using framebuffer if available
if [ -c /dev/fb0 ] && [ -f /usr/share/kioskbook/route19-logo.png ]; then
    fbi -d /dev/fb0 -T 1 /usr/share/kioskbook/route19-logo.png &
    sleep 2
    killall fbi 2>/dev/null
fi

sleep 2
EOF
    
    chmod +x "$SPLASH_DIR/boot-splash.sh"
    
    log_info "Boot splash script created"
}

# Create startup service
create_startup_service() {
    log_info "Creating Route 19 startup service..."
    
    # Copy the startup script from config
    if [ -f "$KIOSKBOOK_DIR/config/route19-startup.start" ]; then
        cp "$KIOSKBOOK_DIR/config/route19-startup.start" "$SPLASH_DIR/"
        chmod +x "$SPLASH_DIR/route19-startup.start"
    fi
    
    # Create systemd service for startup display
    cat > /etc/systemd/system/route19-startup.service << EOF
[Unit]
Description=Route 19 Startup Display
After=local-fs.target
Before=graphical-session.target

[Service]
Type=oneshot
ExecStart=$SPLASH_DIR/boot-splash.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable route19-startup.service
    
    log_info "Route 19 startup service created"
}

# Configure Plymouth (if available)
configure_plymouth() {
    log_info "Checking for Plymouth configuration..."
    
    if command -v plymouth >/dev/null 2>&1; then
        log_info "Plymouth found, configuring custom theme..."
        
        # Create custom Plymouth theme directory
        mkdir -p /usr/share/plymouth/themes/route19/
        
        # Create simple Plymouth theme
        cat > /usr/share/plymouth/themes/route19/route19.plymouth << 'EOF'
[Plymouth Theme]
Name=Route 19
Description=Route 19 KioskBook Theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/route19
ScriptFile=/usr/share/plymouth/themes/route19/route19.script
EOF
        
        cat > /usr/share/plymouth/themes/route19/route19.script << 'EOF'
# Route 19 Plymouth Theme Script

Window.SetBackgroundTopColor (0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor (0.0, 0.0, 0.0);

# Show Route 19 logo
logo_image = Image("route19-logo.png");
logo_sprite = Sprite(logo_image);
logo_sprite.SetPosition(screen_width / 2 - logo_image.GetWidth() / 2, screen_height / 2 - logo_image.GetHeight() / 2, 0);
logo_sprite.SetOpacity(1);

# Show progress
progress = Progress.Bar(logo_image.GetWidth(), 10);
progress.SetPosition(screen_width / 2 - progress.GetWidth() / 2, logo_sprite.GetY() + logo_image.GetHeight() + 20, 0);
progress.SetOpacity(1);

# Show message
message = Text("Starting KioskBook...");
message.SetPosition(screen_width / 2 - message.GetWidth() / 2, progress.GetY() + 30, 0);
message.SetColor(1.0, 1.0, 1.0, 1.0);
EOF
        
        # Update Plymouth configuration
        if [ -f /etc/plymouth/plymouthd.conf ]; then
            sed -i 's/^Theme=.*/Theme=route19/' /etc/plymouth/plymouthd.conf
        fi
        
        log_info "Plymouth theme configured"
    else
        log_info "Plymouth not available, skipping theme configuration"
    fi
}

# Main function
main() {
    echo -e "${CYAN}=== Boot Splash Module ===${NC}"
    
    setup_splash_assets
    create_boot_splash_script
    create_startup_service
    configure_plymouth
    
    log_info "Boot splash configuration complete"
    log_info "Route 19 logo will display during boot"
}

main "$@"
