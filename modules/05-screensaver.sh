#!/bin/bash
# KioskBook Screensaver Module

# Setup screensaver service
setup_screensaver() {
    log_step "Setting Up Screensaver Service"
    
    # Create screensaver service
    cat > /mnt/root/etc/init.d/screensaver << 'EOF'
#!/sbin/openrc-run

name="Screensaver"
description="Time-based screensaver for kiosk"

depend() {
    need kiosk-browser
    after kiosk-browser
}

start() {
    ebegin "Starting screensaver service"
    # Service runs via cron, no persistent daemon needed
    eend 0
}

stop() {
    ebegin "Stopping screensaver service"
    eend 0
}
EOF
    
    chmod +x /mnt/root/etc/init.d/screensaver
    chroot /mnt/root rc-update add screensaver default
    
    # Create screensaver HTML
    cat > /mnt/root/opt/screensaver.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>KioskBook Screensaver</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            font-family: 'Arial', sans-serif;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            height: 100vh;
            overflow: hidden;
        }
        
        .logo {
            width: 200px;
            height: 200px;
            background: white;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 40px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        
        .logo img {
            width: 150px;
            height: 150px;
        }
        
        .main-text {
            font-size: 3em;
            font-weight: bold;
            text-align: center;
            margin-bottom: 20px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.5);
        }
        
        .sub-text {
            font-size: 1.5em;
            text-align: center;
            margin-bottom: 40px;
            opacity: 0.9;
        }
        
        .time-info {
            position: absolute;
            bottom: 40px;
            left: 50%;
            transform: translateX(-50%);
            text-align: center;
            font-size: 1.2em;
        }
        
        .date {
            font-size: 1.5em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .time {
            font-size: 2em;
            font-weight: bold;
        }
        
        .return-time {
            font-size: 1em;
            margin-top: 20px;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div class="logo">
        <img src="data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTUwIiBoZWlnaHQ9IjE1MCIgdmlld0JveD0iMCAwIDE1MCAxNTAiIGZpbGw9Im5vbmUiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+CjxyZWN0IHdpZHRoPSIxNTAiIGhlaWdodD0iMTUwIiBmaWxsPSIjMUUzQzcyIi8+CjxwYXRoIGQ9Ik03NSAzN0M5Ny4wOTUgMzcgMTE1IDU0LjkwNDcgMTE1IDc3QzExNSA5OS4wOTUzIDk3LjA5NSAxMTcgNzUgMTE3QzUyLjkwNDcgMTE3IDM1IDk5LjA5NTMgMzUgNzdDMzUgNTQuOTA0NyA1Mi45MDQ3IDM3IDc1IDM3WiIgZmlsbD0id2hpdGUiLz4KPHBhdGggZD0iTTc1IDU3Qzg4LjgwNzEgNTcgMTAwIDY4LjE5MjkgMTAwIDgyQzEwMCA5NS44MDcxIDg4LjgwNzEgMTA3IDc1IDEwN0M2MS4xOTI5IDEwNyA1MCA5NS44MDcxIDUwIDgyQzUwIDY4LjE5MjkgNjEuMTkyOSA1NyA3NSA1N1oiIGZpbGw9IiMxRTNDNzIiLz4KPC9zdmc+" alt="Route 19 Logo">
    </div>
    
    <div class="main-text">Cape Breton West</div>
    <div class="sub-text">KioskBook Professional Display</div>
    
    <div class="time-info">
        <div class="date" id="currentDate"></div>
        <div class="time" id="currentTime"></div>
        <div class="return-time">Will return at 7am</div>
    </div>
    
    <script>
        function updateTime() {
            const now = new Date();
            const dateStr = now.toLocaleDateString('en-CA', {
                weekday: 'long',
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
            const timeStr = now.toLocaleTimeString('en-CA', {
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
            
            document.getElementById('currentDate').textContent = dateStr;
            document.getElementById('currentTime').textContent = timeStr;
        }
        
        updateTime();
        setInterval(updateTime, 1000);
    </script>
</body>
</html>
EOF
    
    # Create screensaver control script
    cat > /mnt/root/opt/screensaver-control.sh << 'EOF'
#!/bin/bash
# Screensaver control script

current_hour=$(date +%H)

# Screensaver hours: 11 PM to 7 AM (23:00 to 06:59)
if [ "$current_hour" -ge 23 ] || [ "$current_hour" -lt 7 ]; then
    # Screensaver time - switch to screensaver
    if ! curl -s http://localhost:3001 >/dev/null; then
        echo "$(date): Starting screensaver server"
        cd /opt
        start-stop-daemon --start --pidfile /run/screensaver.pid \
            --make-pidfile --background --exec /usr/bin/http-server -- \
            -p 3001 screensaver.html
        
        # Switch browser to screensaver
        sleep 2
        xdotool key ctrl+l
        sleep 1
        xdotool type "http://localhost:3001"
        xdotool key Return
    fi
else
    # Business hours - switch to kiosk app
    if curl -s http://localhost:3001 >/dev/null; then
        echo "$(date): Stopping screensaver, switching to kiosk app"
        start-stop-daemon --stop --pidfile /run/screensaver.pid 2>/dev/null
        
        # Switch browser to kiosk app
        sleep 2
        xdotool key ctrl+l
        sleep 1
        xdotool type "http://localhost:3000"
        xdotool key Return
    fi
fi
EOF
    
    chmod +x /mnt/root/opt/screensaver-control.sh
    
    # Create manual screensaver control
    cat > /mnt/root/opt/screensaver-manual.sh << 'EOF'
#!/bin/bash
# Manual screensaver control

case "$1" in
    "on")
        echo "Activating screensaver manually..."
        /opt/screensaver-control.sh
        ;;
    "off")
        echo "Deactivating screensaver manually..."
        start-stop-daemon --stop --pidfile /run/screensaver.pid 2>/dev/null
        xdotool key ctrl+l
        sleep 1
        xdotool type "http://localhost:3000"
        xdotool key Return
        ;;
    *)
        echo "Usage: $0 {on|off}"
        ;;
esac
EOF
    
    chmod +x /mnt/root/opt/screensaver-manual.sh
    
    # Install xdotool if not already installed
    chroot /mnt/root apk add xdotool
    
    # Add screensaver check to crontab (every 5 minutes)
    echo "*/5 * * * * /opt/screensaver-control.sh" | chroot /mnt/root crontab -
    
    log_info "Screensaver service installed"
}
