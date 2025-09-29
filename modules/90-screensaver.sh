#!/bin/bash
#
# KioskBook Module: Screensaver System
#
# Sets up time-based screensaver functionality.
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
SCREENSAVER_SCRIPT="/opt/screensaver-control.sh"
SCREENSAVER_HTML="/opt/screensaver.html"

log_info() {
    echo -e "${GREEN}[SCREENSAVER]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[SCREENSAVER]${NC} $1"
}

log_error() {
    echo -e "${RED}[SCREENSAVER]${NC} $1"
    exit 1
}

# Create screensaver HTML
create_screensaver_html() {
    log_info "Creating screensaver HTML..."
    
    # Use config version if available
    if [ -f "$KIOSKBOOK_DIR/config/screensaver.html" ]; then
        cp "$KIOSKBOOK_DIR/config/screensaver.html" "$SCREENSAVER_HTML"
        log_info "Using screensaver HTML from config"
    else
        # Create default screensaver HTML
        cat > "$SCREENSAVER_HTML" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KioskBook Screensaver</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            overflow: hidden;
        }
        
        .screensaver-content {
            text-align: center;
            animation: fadeIn 2s ease-in-out;
        }
        
        .logo {
            font-size: 4rem;
            font-weight: bold;
            margin-bottom: 1rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.5);
        }
        
        .time {
            font-size: 3rem;
            font-weight: 300;
            margin-bottom: 0.5rem;
            font-variant-numeric: tabular-nums;
        }
        
        .date {
            font-size: 1.5rem;
            opacity: 0.8;
            margin-bottom: 2rem;
        }
        
        .status {
            font-size: 1.2rem;
            opacity: 0.7;
        }
        
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .pulse {
            animation: pulse 2s infinite;
        }
    </style>
</head>
<body>
    <div class="screensaver-content">
        <div class="logo">Route 19</div>
        <div class="time" id="time"></div>
        <div class="date" id="date"></div>
        <div class="status pulse">KioskBook Standby Mode</div>
    </div>

    <script>
        function updateTime() {
            const now = new Date();
            const timeElement = document.getElementById('time');
            const dateElement = document.getElementById('date');
            
            // Format time
            const time = now.toLocaleTimeString('en-US', {
                hour12: false,
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
            
            // Format date
            const date = now.toLocaleDateString('en-US', {
                weekday: 'long',
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
            
            timeElement.textContent = time;
            dateElement.textContent = date;
        }
        
        // Update time immediately and then every second
        updateTime();
        setInterval(updateTime, 1000);
        
        // Prevent context menu and selection
        document.addEventListener('contextmenu', e => e.preventDefault());
        document.addEventListener('selectstart', e => e.preventDefault());
        
        // Keep screen awake
        if ('wakeLock' in navigator) {
            navigator.wakeLock.request('screen');
        }
    </script>
</body>
</html>
EOF
        log_info "Created default screensaver HTML"
    fi
    
    log_info "Screensaver HTML created at $SCREENSAVER_HTML"
}

# Create screensaver control script
create_screensaver_script() {
    log_info "Creating screensaver control script..."
    
    # Use config version if available
    if [ -f "$KIOSKBOOK_DIR/config/screensaver-control.sh" ]; then
        cp "$KIOSKBOOK_DIR/config/screensaver-control.sh" "$SCREENSAVER_SCRIPT"
        log_info "Using screensaver control script from config"
    else
        # Create enhanced screensaver control script
        cat > "$SCREENSAVER_SCRIPT" << 'EOF'
#!/bin/sh
# KioskBook Enhanced Screensaver Control Script

LOG_FILE="/var/log/screensaver.log"
SCREENSAVER_URL="http://localhost:3001"
SCREENSAVER_HTML="/opt/screensaver.html"

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
    
    # Install http-server if not available
    if ! command -v http-server >/dev/null 2>&1; then
        npm install -g http-server
    fi
    
    # Serve screensaver HTML
    npx http-server "$SCREENSAVER_HTML" -p 3001 -a 0.0.0.0 &
    SCREENSAVER_PID=$!
    echo $SCREENSAVER_PID > /var/run/screensaver.pid
    
    # Wait for screensaver to be ready
    sleep 3
    
    # Switch browser to screensaver using xdotool
    if command -v xdotool >/dev/null 2>&1; then
        xdotool key ctrl+l
        sleep 1
        xdotool type "$SCREENSAVER_URL"
        sleep 1
        xdotool key Return
    fi
    
    log_screensaver "Screensaver started (PID: $SCREENSAVER_PID)"
}

# Stop screensaver
stop_screensaver() {
    log_screensaver "Stopping screensaver"
    
    # Kill screensaver server
    if [ -f /var/run/screensaver.pid ]; then
        SCREENSAVER_PID=$(cat /var/run/screensaver.pid)
        kill $SCREENSAVER_PID 2>/dev/null || true
        rm -f /var/run/screensaver.pid
    fi
    
    # Kill any remaining http-server processes serving screensaver
    pkill -f "http-server.*screensaver.html" 2>/dev/null || true
    
    # Switch browser back to main app using xdotool
    if command -v xdotool >/dev/null 2>&1; then
        xdotool key ctrl+l
        sleep 1
        xdotool type "http://localhost:3000"
        sleep 1
        xdotool key Return
    fi
    
    log_screensaver "Screensaver stopped"
}

# Check screensaver status
check_screensaver_status() {
    if pgrep -f "http-server.*screensaver.html" >/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Manual control
manual_control() {
    case "$1" in
        "start")
            start_screensaver
            ;;
        "stop")
            stop_screensaver
            ;;
        "status")
            echo "Screensaver status: $(check_screensaver_status)"
            ;;
        "toggle")
            if [ "$(check_screensaver_status)" = "running" ]; then
                stop_screensaver
            else
                start_screensaver
            fi
            ;;
        *)
            echo "Usage: $0 {start|stop|status|toggle}"
            exit 1
            ;;
    esac
}

# Main screensaver control loop
main() {
    if [ -n "$1" ]; then
        manual_control "$1"
        return
    fi
    
    log_screensaver "Screensaver control started"
    
    while true; do
        if is_screensaver_time; then
            # Check if screensaver is already running
            if [ "$(check_screensaver_status)" != "running" ]; then
                start_screensaver
            fi
        else
            # Check if screensaver is running
            if [ "$(check_screensaver_status)" = "running" ]; then
                stop_screensaver
            fi
        fi
        
        # Check every 5 minutes
        sleep 300
    done
}

main "$@"
EOF
        log_info "Created enhanced screensaver control script"
    fi
    
    chmod +x "$SCREENSAVER_SCRIPT"
    
    log_info "Screensaver control script created at $SCREENSAVER_SCRIPT"
}

# Create screensaver service
create_screensaver_service() {
    log_info "Creating screensaver systemd service..."
    
    # Use config version if available
    if [ -f "$KIOSKBOOK_DIR/config/screensaver.service" ]; then
        cp "$KIOSKBOOK_DIR/config/screensaver.service" /etc/systemd/system/
        log_info "Using screensaver service from config"
    else
        # Create systemd service
        cat > /etc/systemd/system/screensaver.service << 'EOF'
[Unit]
Description=KioskBook Screensaver Service
After=kiosk-browser.service
Wants=kiosk-browser.service

[Service]
Type=simple
ExecStart=/opt/screensaver-control.sh
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        log_info "Created screensaver systemd service"
    fi
    
    systemctl daemon-reload
    systemctl enable screensaver.service
    systemctl start screensaver.service
    
    log_info "Screensaver service created and started"
}

# Setup log rotation
setup_log_rotation() {
    log_info "Setting up log rotation for screensaver logs..."
    
    cat > /etc/logrotate.d/kiosk-screensaver << 'EOF'
/var/log/screensaver.log {
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
    echo -e "${CYAN}=== Screensaver Module ===${NC}"
    
    create_screensaver_html
    create_screensaver_script
    create_screensaver_service
    setup_log_rotation
    
    log_info "Screensaver setup complete"
    log_info "Screensaver will activate from 11 PM to 7 AM"
    log_info "Manual control: /opt/screensaver-control.sh {start|stop|status|toggle}"
    log_info "View screensaver logs: journalctl -u screensaver -f"
}

main "$@"
