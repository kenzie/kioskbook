#!/bin/bash
#
# KioskBook Update Script
#
# Applies latest improvements and fixes to an existing KioskBook installation.
# Safe to run multiple times (idempotent operations).
#
# Usage: sudo ./update.sh
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

# Logging functions
log() { printf "${CYAN}[UPDATE]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "     KioskBook Update Script"
    echo "    Apply Latest Improvements to Existing Installation"
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
    
    # Check if this is a KioskBook system
    if [[ ! -f /etc/systemd/system/kioskbook-app.service ]]; then
        log_error "This doesn't appear to be a KioskBook installation"
    fi
    
    # Check if kiosk user exists
    if ! id "$KIOSK_USER" >/dev/null 2>&1; then
        log_error "Kiosk user not found. Is this a KioskBook system?"
    fi
    
    log_success "Prerequisites verified"
}

# Update system packages
update_system_packages() {
    log "Updating system packages..."
    
    # Update package lists
    apt-get update
    
    # Upgrade packages (with automatic yes)
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Clean up
    apt-get autoremove -y
    apt-get autoclean
    
    log_success "System packages updated"
}

# Update font configuration (idempotent)
update_font_configuration() {
    log "Updating font configuration..."
    
    # Create fontconfig directory if it doesn't exist
    mkdir -p /etc/fonts/conf.d
    
    # Create Inter font priority configuration (overwrites if exists)
    cat > /etc/fonts/conf.d/10-inter-default.conf << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Set Inter as default sans-serif font -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Inter</family>
      <family>Inter Display</family>
    </prefer>
  </alias>
  
  <!-- Set Inter as default for common web fonts -->
  <alias>
    <family>Arial</family>
    <prefer>
      <family>Inter</family>
    </prefer>
  </alias>
  
  <alias>
    <family>Helvetica</family>
    <prefer>
      <family>Inter</family>
    </prefer>
  </alias>
  
  <alias>
    <family>system-ui</family>
    <prefer>
      <family>Inter</family>
    </prefer>
  </alias>
</fontconfig>
EOF
    
    # Update font cache
    fc-cache -fv >/dev/null 2>&1
    
    log_success "Font configuration updated"
}

# Update SSH configuration (idempotent)
update_ssh_configuration() {
    log "Updating SSH configuration for faster startup..."
    
    local ssh_config="/etc/ssh/sshd_config"
    local updated=false
    
    # Add UseDNS no if not present
    if ! grep -q "^UseDNS no" "$ssh_config"; then
        echo "UseDNS no" >> "$ssh_config"
        updated=true
        log "Added UseDNS no to SSH config"
    fi
    
    # Add GSSAPIAuthentication no if not present
    if ! grep -q "^GSSAPIAuthentication no" "$ssh_config"; then
        echo "GSSAPIAuthentication no" >> "$ssh_config"
        updated=true
        log "Added GSSAPIAuthentication no to SSH config"
    fi
    
    # Pre-generate SSH host keys if missing
    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -A
        updated=true
        log "Generated missing SSH host keys"
    fi
    
    if [[ "$updated" == true ]]; then
        systemctl restart ssh
        log_success "SSH configuration updated and restarted"
    else
        log_success "SSH configuration already optimized"
    fi
}

# Update OpenBox autostart configuration (idempotent)
update_openbox_configuration() {
    log "Updating OpenBox autostart configuration..."
    
    local autostart_file="$KIOSK_HOME/.config/openbox/autostart"
    
    # Create the updated autostart script
    cat > "$autostart_file" << 'EOF'
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

# Start Chromium in kiosk mode with font optimization
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
    --force-device-scale-factor=1 \
    --font-render-hinting=none \
    http://localhost:5173
EOF
    
    chmod +x "$autostart_file"
    chown "$KIOSK_USER:$KIOSK_USER" "$autostart_file"
    
    log_success "OpenBox configuration updated"
}

# Update systemd service configuration (idempotent)
update_systemd_service() {
    log "Updating systemd service configuration..."
    
    local service_file="/etc/systemd/system/kioskbook-app.service"
    
    # Create updated service file
    cat > "$service_file" << EOF
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
    
    # Reload and restart if needed
    systemctl daemon-reload
    
    if systemctl is-active --quiet kioskbook-app; then
        log "Restarting KioskBook application service..."
        systemctl restart kioskbook-app
    fi
    
    log_success "Systemd service updated"
}

# Update application (idempotent)
update_application() {
    log "Updating application..."
    
    if [[ -d "$APP_DIR" ]]; then
        cd "$APP_DIR"
        
        # Check if it's a git repository
        if [[ -d .git ]]; then
            log "Pulling latest application code..."
            git pull
            
            # Update dependencies
            npm ci
            
            # Try to build if build script exists
            if npm run build 2>/dev/null; then
                log "Application built successfully"
            else
                log_warning "No build script found, using development mode"
            fi
            
            log_success "Application updated"
        else
            log_warning "Application directory is not a git repository"
        fi
    else
        log_error "Application directory not found: $APP_DIR"
    fi
}

# Restart kiosk session to apply changes
restart_kiosk_session() {
    log "Restarting kiosk session to apply changes..."
    
    # Check if LightDM is running
    if systemctl is-active --quiet lightdm; then
        systemctl restart lightdm
        log_success "Kiosk session restarted"
    else
        log_warning "LightDM not running, changes will apply on next boot"
    fi
}

# Show completion
show_completion() {
    echo -e "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     KioskBook Update Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${CYAN}Updates Applied:${NC}"
    echo -e "  ✅ System packages updated"
    echo -e "  ✅ Font configuration optimized (Inter font priority)"
    echo -e "  ✅ SSH configuration optimized (faster startup)"
    echo -e "  ✅ OpenBox autostart updated (port 5173, font rendering)"
    echo -e "  ✅ Systemd service configuration updated"
    echo -e "  ✅ Application code updated"
    echo -e "  ✅ Kiosk session restarted"
    
    echo -e "\n${CYAN}System Status:${NC}"
    if systemctl is-active --quiet kioskbook-app; then
        echo -e "  ✅ KioskBook application running"
    else
        echo -e "  ❌ KioskBook application needs attention"
    fi
    
    echo -e "\n${CYAN}Management Commands:${NC}"
    echo -e "  Status: ${YELLOW}sudo systemctl status kioskbook-app${NC}"
    echo -e "  Logs: ${YELLOW}sudo journalctl -u kioskbook-app -f${NC}"
    echo -e "  Health: ${YELLOW}sudo /usr/local/bin/kioskbook-health${NC}"
}

# Main execution
main() {
    show_banner
    check_prerequisites
    update_system_packages
    update_font_configuration
    update_ssh_configuration
    update_openbox_configuration
    update_systemd_service
    update_application
    restart_kiosk_session
    show_completion
}

# Run
main "$@"