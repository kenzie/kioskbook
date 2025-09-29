#!/bin/sh
# KioskBook Screensaver Control Script

LOG_FILE="/var/log/screensaver.log"
SCREENSAVER_URL="http://localhost:3001"

# Function to log with timestamp
log_screensaver() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Check if it's screensaver time (11 PM to 7 AM)
is_screensaver_time() {
    current_hour=$(date +%H)
    if [ "$current_hour" -ge 23 ] || [ "$current_hour" -lt 7 ]; then
        return 0
    else
        return 1
    fi
}

# Start screensaver
start_screensaver() {
    log_screensaver "Starting screensaver"
    
    # Serve screensaver HTML
    npx http-server /opt/screensaver.html -p 3001 -a 0.0.0.0 &
    
    # Wait for screensaver to be ready
    sleep 3
    
    # Switch browser to screensaver
    xdotool key ctrl+l
    sleep 1
    xdotool type "$SCREENSAVER_URL"
    sleep 1
    xdotool key Return
    
    log_screensaver "Screensaver started"
}

# Stop screensaver
stop_screensaver() {
    log_screensaver "Stopping screensaver"
    
    # Kill screensaver server
    pkill -f "http-server.*screensaver.html"
    
    # Switch browser back to main app
    xdotool key ctrl+l
    sleep 1
    xdotool type "http://localhost:3000"
    sleep 1
    xdotool key Return
    
    log_screensaver "Screensaver stopped"
}

# Main screensaver control
main() {
    log_screensaver "Screensaver control started"
    
    while true; do
        if is_screensaver_time; then
            # Check if screensaver is already running
            if ! pgrep -f "http-server.*screensaver.html" >/dev/null; then
                start_screensaver
            fi
        else
            # Check if screensaver is running
            if pgrep -f "http-server.*screensaver.html" >/dev/null; then
                stop_screensaver
            fi
        fi
        
        # Check every 5 minutes
        sleep 300
    done
}

main "$@"
