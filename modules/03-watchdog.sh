#!/bin/bash
# KioskBook Watchdog Module

# Setup kiosk watchdog
setup_kiosk_watchdog() {
    log_step "Setting Up Kiosk Watchdog"
    
    # Create kiosk browser service
    cat > /mnt/root/etc/init.d/kiosk-browser << 'EOF'
#!/sbin/openrc-run

name="Kiosk Browser"
description="Chromium browser in kiosk mode"

depend() {
    need kiosk-app
    after kiosk-app
}

start() {
    ebegin "Starting kiosk browser"
    
    # Wait for app to be responsive
    for i in {1..30}; do
        if curl -s http://localhost:3000 >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
    
    # Start Chromium in kiosk mode
    start-stop-daemon --start --pidfile /run/kiosk-browser.pid \
        --make-pidfile --background --chdir /home/kiosk \
        --user kiosk --exec /usr/bin/chromium-browser -- \
        --kiosk \
        --no-sandbox \
        --disable-dev-shm-usage \
        --disable-gpu \
        --disable-software-rasterizer \
        --disable-background-timer-throttling \
        --disable-backgrounding-occluded-windows \
        --disable-renderer-backgrounding \
        --disable-features=TranslateUI \
        --disable-ipc-flooding-protection \
        --disable-hang-monitor \
        --disable-prompt-on-repost \
        --disable-domain-reliability \
        --disable-background-networking \
        --disable-sync \
        --disable-default-apps \
        --disable-extensions \
        --disable-plugins \
        --disable-translate \
        --disable-logging \
        --disable-gpu-logging \
        --silent-debugger-extension-api \
        --no-first-run \
        --no-default-browser-check \
        --no-pings \
        --password-store=basic \
        --use-mock-keychain \
        --disable-component-extensions-with-background-pages \
        --disable-background-downloads \
        --disable-add-to-shelf \
        --disable-client-side-phishing-detection \
        --disable-datasaver-prompt \
        --disable-desktop-notifications \
        --disable-domain-reliability \
        --disable-features=TranslateUI \
        --disable-ipc-flooding-protection \
        --disable-save-password-bubble \
        --disable-web-security \
        --disable-features=VizDisplayCompositor \
        --user-data-dir=/tmp/chrome-kiosk \
        --start-fullscreen \
        --incognito \
        http://localhost:3000
    
    eend $?
}

stop() {
    ebegin "Stopping kiosk browser"
    start-stop-daemon --stop --pidfile /run/kiosk-browser.pid
    pkill -f "chromium-browser.*kiosk"
    eend $?
}

restart() {
    stop
    start
}
EOF
    
    chmod +x /mnt/root/etc/init.d/kiosk-browser
    chroot /mnt/root rc-update add kiosk-browser default
    
    # Create health check script
    cat > /mnt/root/opt/kiosk-health-check.sh << 'EOF'
#!/bin/bash
# Kiosk browser health check with escalating recovery

# Check if browser process is running
if ! pgrep -f "chromium-browser.*kiosk" >/dev/null; then
    echo "$(date): Browser not running, triggering recovery..."
    /opt/escalating-recovery.sh trigger
    exit 1
fi

# Determine which app should be active based on time
current_hour=$(date +%H)
if [ "$current_hour" -ge 23 ] || [ "$current_hour" -lt 7 ]; then
    # Screensaver hours (11pm to 7am)
    EXPECTED_URL="http://localhost:3001"
    APP_NAME="screensaver"
else
    # Business hours (7am to 11pm)
    EXPECTED_URL="http://localhost:3000"
    APP_NAME="kiosk app"
fi

# Check if the expected app is responding
if ! curl -s --max-time 5 "$EXPECTED_URL" >/dev/null; then
    echo "$(date): $APP_NAME not responding on expected URL ($EXPECTED_URL), triggering recovery..."
    /opt/escalating-recovery.sh trigger
    exit 1
fi

# Check display connectivity
if ! xrandr --query 2>/dev/null | grep -q " connected"; then
    echo "$(date): No display connected, triggering recovery..."
    /opt/escalating-recovery.sh trigger
    exit 1
fi

# Check if browser window is actually visible (X11 check)
if ! xwininfo -name "Chromium" >/dev/null 2>&1; then
    echo "$(date): Browser window not visible, triggering recovery..."
    /opt/escalating-recovery.sh trigger
    exit 1
fi

echo "$(date): Kiosk browser healthy ($APP_NAME active)"
exit 0
EOF
    
    chmod +x /mnt/root/opt/kiosk-health-check.sh
    
    # Add health check to crontab
    echo "*/2 * * * * /opt/kiosk-health-check.sh" | chroot /mnt/root crontab -
    
    log_info "Kiosk watchdog installed"
}
