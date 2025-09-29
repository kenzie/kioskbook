#!/bin/sh
# KioskBook Health Check Script

LOG_FILE="/var/log/kiosk-health.log"
HEALTH_STATUS="/var/run/kiosk-health.status"

# Function to log with timestamp
log_health() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Check if browser process is running
check_browser_process() {
    if ! pgrep -f "chromium-browser.*kiosk" >/dev/null; then
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

# Main health check
main() {
    log_health "Starting health check"
    
    # Run all checks
    if check_browser_process && check_app_responsive && check_display && check_browser_window; then
        echo "healthy" > "$HEALTH_STATUS"
        log_health "Health check passed"
    else
        echo "unhealthy" > "$HEALTH_STATUS"
        log_health "Health check failed"
        
        # Restart browser service
        log_health "Restarting browser service"
        rc-service kiosk-browser restart
    fi
}

main "$@"
