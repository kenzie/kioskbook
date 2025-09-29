#!/bin/bash
# KioskBook Auto-Update Module

# Setup auto-update service
setup_auto_update() {
    log_step "Setting Up Auto-Update Service"
    
    # Create auto-update service
    cat > /mnt/root/etc/init.d/auto-update << 'EOF'
#!/sbin/openrc-run

name="Auto Update"
description="Automatic system and app updates"

depend() {
    need net
    after net
}

start() {
    ebegin "Starting auto-update service"
    # Service runs via cron, no persistent daemon needed
    eend 0
}

stop() {
    ebegin "Stopping auto-update service"
    eend 0
}
EOF
    
    chmod +x /mnt/root/etc/init.d/auto-update
    chroot /mnt/root rc-update add auto-update default
    
    # Create auto-update script
    cat > /mnt/root/opt/auto-update.sh << 'EOF'
#!/bin/bash
# Comprehensive auto-update script for KioskBook

LOG_FILE="/var/log/auto-update.log"
LOCK_FILE="/tmp/auto-update.lock"

# Prevent concurrent updates
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Update already in progress, skipping" >> "$LOG_FILE"
    exit 0
fi

# Create lock file
touch "$LOCK_FILE"

# Log function
log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

log "Starting auto-update process"

# Update Alpine Linux packages
log "Updating Alpine Linux packages"
if apk update && apk upgrade; then
    log "Alpine packages updated successfully"
else
    log "ERROR: Alpine package update failed"
    rm -f "$LOCK_FILE"
    exit 1
fi

# Update Tailscale if installed
if command -v tailscale >/dev/null; then
    log "Updating Tailscale"
    if curl -fsSL https://tailscale.com/install.sh | sh; then
        log "Tailscale updated successfully"
    else
        log "WARNING: Tailscale update failed"
    fi
fi

# Update Node.js packages if kiosk app exists
if [ -d /opt/kiosk-app/.git ]; then
    log "Updating Vue.js kiosk app"
    cd /opt/kiosk-app
    
    # Pull latest changes
    if git pull; then
        log "Git pull successful"
        
        # Update dependencies if package.json exists
        if [ -f package.json ]; then
            log "Updating Node.js dependencies"
            if npm install; then
                log "Dependencies updated successfully"
                
                # Rebuild Vue.js app if it's a Vue project
                if [ -f vue.config.js ] || grep -q "vue" package.json; then
                    log "Rebuilding Vue.js app"
                    if npm run build; then
                        log "Vue.js app rebuilt successfully"
                        
                        # Restart services
                        log "Restarting kiosk services"
                        rc-service kiosk-app restart
                        sleep 5
                        rc-service kiosk-browser restart
                        log "Services restarted successfully"
                    else
                        log "ERROR: Vue.js app build failed"
                    fi
                else
                    log "Not a Vue.js project, skipping build"
                fi
            else
                log "ERROR: npm install failed"
            fi
        else
            log "No package.json found, skipping npm update"
        fi
    else
        log "ERROR: Git pull failed"
    fi
else
    log "No kiosk app repository found, skipping app update"
fi

# Clean up package cache
log "Cleaning up package cache"
apk cache clean

# Check for kernel updates and reboot if needed
if [ -f /var/run/reboot-required ]; then
    log "Kernel update detected, scheduling reboot"
    echo "Reboot required for kernel update" > /var/run/reboot-required-kiosk
fi

log "Auto-update process completed successfully"

# Remove lock file
rm -f "$LOCK_FILE"
EOF
    
    chmod +x /mnt/root/opt/auto-update.sh
    
    # Create manual update script
    cat > /mnt/root/opt/update-now.sh << 'EOF'
#!/bin/bash
# Manual immediate update script

echo "Starting immediate update..."
/opt/auto-update.sh
echo "Update completed"
EOF
    
    chmod +x /mnt/root/opt/update-now.sh
    
    # Create update status script
    cat > /mnt/root/opt/update-status.sh << 'EOF'
#!/bin/bash
# Check update status

echo "=== Update Status ==="
echo "Last update: $(tail -1 /var/log/auto-update.log 2>/dev/null || echo 'Never')"
echo "Update lock: $([ -f /tmp/auto-update.lock ] && echo 'In progress' || echo 'Idle')"
echo "Reboot required: $([ -f /var/run/reboot-required-kiosk ] && echo 'Yes' || echo 'No')"
EOF
    
    chmod +x /mnt/root/opt/update-status.sh
    
    # Add auto-update to crontab (3 AM daily)
    echo "0 3 * * * /opt/auto-update.sh" | chroot /mnt/root crontab -
    
    log_info "Auto-update service installed"
}
