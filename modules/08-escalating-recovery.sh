#!/bin/bash
# KioskBook Escalating Recovery Module

# Setup escalating recovery system
setup_escalating_recovery() {
    log_step "Setting Up Escalating Recovery System"
    
    # Create recovery state tracking
    cat > /mnt/root/opt/recovery-state << 'EOF'
LEVEL=0
LAST_FAILURE=0
FAILURE_COUNT=0
EOF
    
    # Create escalating recovery script
    cat > /mnt/root/opt/escalating-recovery.sh << 'EOF'
#!/bin/bash
# KioskBook Escalating Recovery System

RECOVERY_STATE="/opt/recovery-state"
RECOVERY_LOG="/var/log/recovery.log"
LOCK_FILE="/tmp/recovery.lock"

# Prevent concurrent recovery
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Recovery already in progress, skipping" >> "$RECOVERY_LOG"
    exit 0
fi

touch "$LOCK_FILE"

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
}

trap cleanup EXIT

# Load recovery state
load_state() {
    if [ -f "$RECOVERY_STATE" ]; then
        source "$RECOVERY_STATE"
    else
        LEVEL=0
        LAST_FAILURE=0
        FAILURE_COUNT=0
    fi
}

# Save recovery state
save_state() {
    cat > "$RECOVERY_STATE" << 'STATEEOF'
LEVEL=$LEVEL
LAST_FAILURE=$LAST_FAILURE
FAILURE_COUNT=$FAILURE_COUNT
STATEEOF
}

# Logging function
log_recovery() {
    echo "$(date): $1" >> "$RECOVERY_LOG"
}

# Check if we should reset escalation level
check_reset_condition() {
    local current_time=$(date +%s)
    local time_since_failure=$((current_time - LAST_FAILURE))
    
    # Reset if no failures for 1 hour
    if [ "$time_since_failure" -gt 3600 ]; then
        LEVEL=0
        FAILURE_COUNT=0
        log_recovery "Recovery level reset - no failures for 1 hour"
        save_state
    fi
}

# Level 1: Service restart
level1_recovery() {
    log_recovery "LEVEL 1: Restarting kiosk services"
    
    rc-service kiosk-app restart
    sleep 3
    rc-service kiosk-browser restart
    
    # Check if recovery successful
    sleep 10
    if check_system_health; then
        log_recovery "LEVEL 1: Recovery successful"
        LEVEL=0
        FAILURE_COUNT=0
        save_state
        return 0
    else
        log_recovery "LEVEL 1: Recovery failed, escalating"
        return 1
    fi
}

# Level 2: Browser restart with cache clear
level2_recovery() {
    log_recovery "LEVEL 2: Restarting browser with cache clear"
    
    # Stop browser
    rc-service kiosk-browser stop
    
    # Clear browser cache and data
    rm -rf /tmp/chrome-kiosk/*
    
    # Clear system caches
    sync
    echo 1 > /proc/sys/vm/drop_caches
    
    # Restart browser
    rc-service kiosk-browser start
    
    # Check if recovery successful
    sleep 15
    if check_system_health; then
        log_recovery "LEVEL 2: Recovery successful"
        LEVEL=0
        FAILURE_COUNT=0
        save_state
        return 0
    else
        log_recovery "LEVEL 2: Recovery failed, escalating"
        return 1
    fi
}

# Level 3: X server restart
level3_recovery() {
    log_recovery "LEVEL 3: Restarting X server"
    
    # Stop all services
    rc-service kiosk-browser stop
    rc-service kiosk-app stop
    
    # Kill X server
    pkill -f "Xorg"
    sleep 5
    
    # Restart X server
    export DISPLAY=:0
    startx &
    sleep 10
    
    # Restart services
    rc-service kiosk-app start
    sleep 5
    rc-service kiosk-browser start
    
    # Check if recovery successful
    sleep 20
    if check_system_health; then
        log_recovery "LEVEL 3: Recovery successful"
        LEVEL=0
        FAILURE_COUNT=0
        save_state
        return 0
    else
        log_recovery "LEVEL 3: Recovery failed, escalating"
        return 1
    fi
}

# Level 4: Full system restart
level4_recovery() {
    log_recovery "LEVEL 4: Full system restart required"
    
    # Log the restart reason
    log_recovery "CRITICAL: All recovery levels failed, initiating system restart"
    
    # Save current state
    save_state
    
    # Schedule restart in 30 seconds
    echo "System restarting due to persistent failures..." > /dev/tty1
    sleep 30
    reboot
}

# Check system health
check_system_health() {
    # Check if browser process is running
    if ! pgrep -f "chromium-browser.*kiosk" >/dev/null; then
        return 1
    fi
    
    # Check if app is responding
    current_hour=$(date +%H)
    if [ "$current_hour" -ge 23 ] || [ "$current_hour" -lt 7 ]; then
        EXPECTED_URL="http://localhost:3001"
    else
        EXPECTED_URL="http://localhost:3000"
    fi
    
    if ! curl -s --max-time 5 "$EXPECTED_URL" >/dev/null; then
        return 1
    fi
    
    # Check display connectivity
    if ! xrandr --query 2>/dev/null | grep -q " connected"; then
        return 1
    fi
    
    # Check if browser window is visible
    if ! xwininfo -name "Chromium" >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Main recovery function
perform_recovery() {
    load_state
    check_reset_condition
    
    # Update failure tracking
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    LAST_FAILURE=$(date +%s)
    
    log_recovery "Recovery triggered - Level: $LEVEL, Failures: $FAILURE_COUNT"
    
    case $LEVEL in
        0)
            # First failure - try level 1
            if level1_recovery; then
                return 0
            else
                LEVEL=1
                save_state
                return 1
            fi
            ;;
        1)
            # Level 1 failed - try level 2
            if level2_recovery; then
                return 0
            else
                LEVEL=2
                save_state
                return 1
            fi
            ;;
        2)
            # Level 2 failed - try level 3
            if level3_recovery; then
                return 0
            else
                LEVEL=3
                save_state
                return 1
            fi
            ;;
        3)
            # Level 3 failed - escalate to level 4
            level4_recovery
            ;;
        *)
            # Unknown level - reset and try level 1
            LEVEL=0
            level1_recovery
            ;;
    esac
}

# Recovery command handler
case "$1" in
    "trigger")
        perform_recovery
        ;;
    "reset")
        log_recovery "Recovery level manually reset"
        LEVEL=0
        FAILURE_COUNT=0
        LAST_FAILURE=0
        save_state
        ;;
    "status")
        load_state
        echo "Recovery Level: $LEVEL"
        echo "Failure Count: $FAILURE_COUNT"
        echo "Last Failure: $(date -d "@$LAST_FAILURE" 2>/dev/null || echo "Never")"
        echo "System Health: $(check_system_health && echo "OK" || echo "FAILED")"
        ;;
    *)
        echo "Usage: $0 {trigger|reset|status}"
        exit 1
        ;;
esac
EOF
    
    chmod +x /mnt/root/opt/escalating-recovery.sh
    
    # Create recovery management script
    cat > /mnt/root/opt/recovery-manager.sh << 'EOF'
#!/bin/bash
# Recovery management interface

case "$1" in
    "trigger")
        echo "Triggering escalating recovery..."
        /opt/escalating-recovery.sh trigger
        ;;
    "reset")
        echo "Resetting recovery level..."
        /opt/escalating-recovery.sh reset
        echo "Recovery level reset to 0"
        ;;
    "status")
        echo "=== Recovery System Status ==="
        /opt/escalating-recovery.sh status
        echo
        echo "=== Recent Recovery Logs ==="
        if [ -f /var/log/recovery.log ]; then
            tail -10 /var/log/recovery.log
        else
            echo "No recovery logs found"
        fi
        ;;
    "test")
        echo "Testing recovery system..."
        echo "Simulating failure..."
        rc-service kiosk-browser stop
        sleep 2
        /opt/escalating-recovery.sh trigger
        ;;
    *)
        echo "Usage: $0 {trigger|reset|status|test}"
        echo
        echo "Commands:"
        echo "  trigger  - Trigger escalating recovery"
        echo "  reset    - Reset recovery level to 0"
        echo "  status   - Show recovery system status"
        echo "  test     - Test recovery system"
        exit 1
        ;;
esac
EOF
    
    chmod +x /mnt/root/opt/recovery-manager.sh
    
    log_info "Escalating recovery system installed"
}
