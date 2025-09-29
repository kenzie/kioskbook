#!/bin/bash
# KioskBook Auto Update Service

LOG_FILE="/var/log/auto-update.log"
UPDATE_STATUS="/var/run/update-status"

# Function to log with timestamp
log_update() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Update Alpine packages
update_alpine() {
    log_update "Updating Alpine packages"
    apk update
    apk upgrade
    log_update "Alpine packages updated"
}

# Update Tailscale
update_tailscale() {
    log_update "Updating Tailscale"
    apk update
    apk upgrade tailscale
    log_update "Tailscale updated"
}

# Update kiosk app
update_kiosk_app() {
    log_update "Updating kiosk app"
    
    if [ -d "/opt/kiosk-app" ]; then
        cd /opt/kiosk-app
        
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
        rc-service kiosk-app restart
        
        log_update "Kiosk app updated"
    else
        log_update "Kiosk app directory not found"
    fi
}

# Main update function
main() {
    log_update "Starting auto-update"
    
    # Update system packages
    update_alpine
    
    # Update Tailscale
    update_tailscale
    
    # Update kiosk app
    update_kiosk_app
    
    # Update status
    echo "last_update=$(date)" > "$UPDATE_STATUS"
    
    log_update "Auto-update completed"
}

main "$@"
