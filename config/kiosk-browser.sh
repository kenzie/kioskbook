#!/bin/sh
# KioskBook Browser Service

# Wait for app to be responsive
while ! curl -s http://localhost:3000 >/dev/null 2>&1; do
    echo "Waiting for kiosk app to be ready..."
    sleep 5
done

# Start Chromium in kiosk mode
exec chromium-browser \
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
    --silent \
    --no-first-run \
    --no-default-browser-check \
    --no-pings \
    --no-zygote \
    --incognito \
    --disable-web-security \
    --disable-features=VizDisplayCompositor \
    --user-data-dir=/tmp/chrome-kiosk \
    http://localhost:3000
