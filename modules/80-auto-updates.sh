#!/bin/bash
#
# KioskBook Module: Auto Updates
#
# Sets up automatic system and application updates.
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
UPDATE_SCRIPT="/opt/auto-update.sh"
APP_DIR="/opt/kiosk-app"

log_info() {
    echo -e "${GREEN}[AUTO-UPDATE]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[AUTO-UPDATE]${NC} $1"
}

log_error() {
    echo -e "${RED}[AUTO-UPDATE]${NC} $1"
    exit 1
}

# Create auto-update script
create_update_script() {
    log_info "Creating auto-update script..."
    
    # Use config version if available, otherwise create enhanced version
    if [ -f "$KIOSKBOOK_DIR/config/auto-update.sh" ]; then
        cp "$KIOSKBOOK_DIR/config/auto-update.sh" "$UPDATE_SCRIPT"
        log_info "Using auto-update script from config"
    else
        # Create enhanced auto-update script
        cat > "$UPDATE_SCRIPT" << 'EOF'
#!/bin/sh
# KioskBook Enhanced Auto Update Service

LOG_FILE="/var/log/auto-update.log"
UPDATE_STATUS="/var/run/update-status"

# Function to log with timestamp
log_update() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Update Debian packages
update_debian() {
    log_update "Updating Debian packages"
    
    # Update package list
    apt-get update
    
    # Upgrade packages
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Clean up
    apt-get autoremove -y
    apt-get autoclean
    
    log_update "Debian packages updated"
}

# Update Tailscale
update_tailscale() {
    log_update "Updating Tailscale"
    
    # Update Tailscale repository
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
    
    # Update Tailscale
    apt-get update
    apt-get install -y tailscale
    
    log_update "Tailscale updated"
}

# Update kiosk app
update_kiosk_app() {
    log_update "Updating kiosk app"
    
    if [ -d "/opt/kiosk-app" ]; then
        cd /opt/kiosk-app
        
        # Check if there are updates
        git fetch origin
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/main)
        
        if [ "$LOCAL" != "$REMOTE" ]; then
            log_update "New app version available, updating..."
            
            # Pull latest changes
            git pull origin main
            
            # Rebuild if needed
            if [ -f package.json ]; then
                npm install
                
                # Build Vue.js app
                if [ -f vue.config.js ] || grep -q "vue" package.json; then
                    npm run build
                fi
            fi
            
            # Restart app service
            systemctl restart kiosk-app.service
            
            log_update "Kiosk app updated successfully"
        else
            log_update "Kiosk app is up to date"
        fi
    else
        log_update "Kiosk app directory not found"
    fi
}

# Update KioskBook itself
update_kioskbook() {
    log_update "Checking for KioskBook updates"
    
    if [ -d "/opt/kioskbook" ]; then
        cd /opt/kioskbook
        
        # Check if there are updates
        git fetch origin
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse origin/main)
        
        if [ "$LOCAL" != "$REMOTE" ]; then
            log_update "New KioskBook version available"
            # Note: We don't auto-update KioskBook itself as it might affect running services
            # This could be implemented with a staged update approach
        else
            log_update "KioskBook is up to date"
        fi
    fi
}

# Main update function
main() {
    log_update "Starting auto-update"
    
    # Update system packages
    update_debian
    
    # Update Tailscale
    update_tailscale
    
    # Update kiosk app
    update_kiosk_app
    
    # Check for KioskBook updates
    update_kioskbook
    
    # Update status
    echo "last_update=$(date)" > "$UPDATE_STATUS"
    
    log_update "Auto-update completed"
}

main "$@"
EOF
        log_info "Created enhanced auto-update script"
    fi
    
    chmod +x "$UPDATE_SCRIPT"
    
    log_info "Auto-update script created at $UPDATE_SCRIPT"
}

# Create auto-update service
create_update_service() {
    log_info "Creating auto-update systemd service..."
    
    # Create systemd service (config file is OpenRC format, not systemd)
    cat > /etc/systemd/system/auto-update.service << 'EOF'
[Unit]
Description=KioskBook Auto Update Service
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/opt/auto-update.sh
StandardOutput=journal
StandardError=journal
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
EOF
    log_info "Created auto-update systemd service"
    
    systemctl daemon-reload
    
    # Validate the service file
    if systemctl cat auto-update.service >/dev/null 2>&1; then
        systemctl enable auto-update.service
        log_info "Auto-update service created and enabled"
    else
        log_error "Auto-update service file is invalid"
        systemctl cat auto-update.service
    fi
}

# Create auto-update timer
create_update_timer() {
    log_info "Creating auto-update timer..."
    
    cat > /etc/systemd/system/auto-update.timer << 'EOF'
[Unit]
Description=Run KioskBook Auto Update
Requires=auto-update.service

[Timer]
OnBootSec=1h
OnUnitActiveSec=24h
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    
    # Validate the timer file
    if systemctl cat auto-update.timer >/dev/null 2>&1; then
        systemctl enable auto-update.timer
        systemctl start auto-update.timer
        log_info "Auto-update timer created and started"
    else
        log_error "Auto-update timer file is invalid"
        systemctl cat auto-update.timer
    fi
}

# Setup update notification
setup_update_notification() {
    log_info "Setting up update notifications..."
    
    # Create update notification script
    cat > /opt/update-notification.sh << 'EOF'
#!/bin/bash
# Send update notification to system log

if [ -f "/var/run/update-status" ]; then
    last_update=$(grep "last_update" /var/run/update-status | cut -d'=' -f2)
    echo "Last update: $last_update"
    
    # Check if update was recent (within last 24 hours)
    if [ -n "$last_update" ]; then
        last_update_epoch=$(date -d "$last_update" +%s 2>/dev/null || echo 0)
        current_epoch=$(date +%s)
        hours_since_update=$(( (current_epoch - last_update_epoch) / 3600 ))
        
        if [ $hours_since_update -lt 24 ]; then
            echo "System updated $hours_since_update hours ago"
        fi
    fi
fi
EOF
    
    chmod +x /opt/update-notification.sh
    
    log_info "Update notification configured"
}

# Main function
main() {
    echo -e "${CYAN}=== Auto Updates Module ===${NC}"
    
    create_update_script
    create_update_service
    create_update_timer
    setup_update_notification
    
    log_info "Auto-update setup complete"
    log_info "Updates will run daily at random time"
    log_info "Manual update: systemctl start auto-update.service"
    log_info "Check update status: /var/run/update-status"
    log_info "View update logs: journalctl -u auto-update -f"
}

main "$@"
