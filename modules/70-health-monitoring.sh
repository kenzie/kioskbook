#!/bin/bash
#
# KioskBook Module: Health Monitoring
#
# Sets up health monitoring and watchdog functionality.
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
HEALTH_SCRIPT="/opt/kiosk-health-check.sh"

log_info() {
    echo -e "${GREEN}[HEALTH]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[HEALTH]${NC} $1"
}

log_error() {
    echo -e "${RED}[HEALTH]${NC} $1"
    exit 1
}

# Create health check script
create_health_script() {
    log_info "Creating health monitoring script..."
    
    # Use config version if available, otherwise create enhanced version
    if [ -f "$KIOSKBOOK_DIR/config/kiosk-health-check.sh" ]; then
        cp "$KIOSKBOOK_DIR/config/kiosk-health-check.sh" "$HEALTH_SCRIPT"
        log_info "Using health check script from config"
    else
        # Create enhanced health check script
        cat > "$HEALTH_SCRIPT" << 'EOF'
#!/bin/sh
# KioskBook Enhanced Health Check Script

LOG_FILE="/var/log/kiosk-health.log"
HEALTH_STATUS="/var/run/kiosk-health.status"

# Function to log with timestamp
log_health() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Check if browser process is running
check_browser_process() {
    if ! pgrep -f "chromium.*kiosk" >/dev/null; then
        log_health "ERROR: Browser process not running"
        return 1
    fi
    return 0
}

# Check if app is responsive
check_app_responsive() {
    # Check current time to determine which URL to check
    current_hour=$(date +%H)
    if [ "$current_hour" -ge 23 ] || [ "$current_hour" -lt 7 ]; then
        # Screensaver hours (11 PM to 7 AM)
        url="http://localhost:3001"
    else
        # Normal hours
        url="http://localhost:3000"
    fi
    
    if ! curl -s "$url" >/dev/null 2>&1; then
        log_health "ERROR: App not responsive at $url"
        return 1
    fi
    return 0
}

# Check if display is working
check_display() {
    if ! xrandr >/dev/null 2>&1; then
        log_health "ERROR: Display not working"
        return 1
    fi
    return 0
}

# Check if browser window is visible
check_browser_window() {
    if ! xdotool search --name "Chromium" >/dev/null 2>&1; then
        log_health "ERROR: Browser window not visible"
        return 1
    fi
    return 0
}

# Check system resources
check_system_resources() {
    # Check disk space
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log_health "WARNING: Disk usage high: ${disk_usage}%"
    fi
    
    # Check memory usage
    memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$memory_usage" -gt 90 ]; then
        log_health "WARNING: Memory usage high: ${memory_usage}%"
    fi
    
    return 0
}

# Check network connectivity
check_network() {
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_health "ERROR: No network connectivity"
        return 1
    fi
    return 0
}

# Main health check
main() {
    log_health "Starting health check"
    
    # Run all checks
    checks_passed=0
    total_checks=6
    
    check_browser_process && ((checks_passed++))
    check_app_responsive && ((checks_passed++))
    check_display && ((checks_passed++))
    check_browser_window && ((checks_passed++))
    check_system_resources && ((checks_passed++))
    check_network && ((checks_passed++))
    
    if [ $checks_passed -eq $total_checks ]; then
        echo "healthy" > "$HEALTH_STATUS"
        log_health "Health check passed ($checks_passed/$total_checks)"
    else
        echo "unhealthy" > "$HEALTH_STATUS"
        log_health "Health check failed ($checks_passed/$total_checks)"
        
        # Restart browser service if browser checks failed
        if ! check_browser_process || ! check_browser_window; then
            log_health "Restarting browser service"
            systemctl restart kiosk-browser.service 2>/dev/null || true
        fi
        
        # Restart app service if app is not responsive
        if ! check_app_responsive; then
            log_health "Restarting app service"
            systemctl restart kiosk-app.service 2>/dev/null || true
        fi
    fi
}

main "$@"
EOF
        log_info "Created enhanced health check script"
    fi
    
    chmod +x "$HEALTH_SCRIPT"
    
    log_info "Health monitoring script created at $HEALTH_SCRIPT"
}

# Create health monitoring service
create_health_service() {
    log_info "Creating health monitoring systemd service..."
    
    cat > /etc/systemd/system/kiosk-health.service << 'EOF'
[Unit]
Description=KioskBook Health Monitor
After=kiosk-app.service kiosk-browser.service
Wants=kiosk-app.service kiosk-browser.service

[Service]
Type=simple
ExecStart=/opt/kiosk-health-check.sh
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable kiosk-health.service
    systemctl start kiosk-health.service
    
    log_info "Health monitoring service created and started"
}

# Create health monitoring timer
create_health_timer() {
    log_info "Creating health monitoring timer..."
    
    cat > /etc/systemd/system/kiosk-health.timer << 'EOF'
[Unit]
Description=Run KioskBook Health Check
Requires=kiosk-health.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable kiosk-health.timer
    systemctl start kiosk-health.timer
    
    log_info "Health monitoring timer created and started"
}

# Setup log rotation
setup_log_rotation() {
    log_info "Setting up log rotation for health logs..."
    
    cat > /etc/logrotate.d/kiosk-health << 'EOF'
/var/log/kiosk-health.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
    
    log_info "Log rotation configured"
}

# Main function
main() {
    echo -e "${CYAN}=== Health Monitoring Module ===${NC}"
    
    create_health_script
    create_health_service
    create_health_timer
    setup_log_rotation
    
    log_info "Health monitoring setup complete"
    log_info "Health checks will run every 2 minutes"
    log_info "View health status: /var/run/kiosk-health.status"
    log_info "View health logs: journalctl -u kiosk-health -f"
}

main "$@"
