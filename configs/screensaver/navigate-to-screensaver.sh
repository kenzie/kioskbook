#!/bin/bash
# Navigate Chromium to screensaver page

SCREENSAVER_PATH="file:///opt/kioskbook-repo/configs/screensaver/screensaver.html"
DEBUG_PORT=9222
MAX_WAIT=60
RETRY_INTERVAL=2

# Wait for Chromium debug port to be ready
elapsed=0
while [ $elapsed -lt $MAX_WAIT ]; do
    PAGE_ID=$(curl -s http://localhost:${DEBUG_PORT}/json 2>/dev/null | grep -oP '"id":\s*"\K[^"]+' | head -1)

    if [[ -n "$PAGE_ID" ]]; then
        # Chromium ready, switch to screensaver
        curl -s -X PUT "http://localhost:${DEBUG_PORT}/json/new?${SCREENSAVER_PATH}" >/dev/null
        sleep 0.5
        curl -s -X GET "http://localhost:${DEBUG_PORT}/json/close/${PAGE_ID}" >/dev/null

        logger -t kioskbook-screensaver "Activated screensaver mode (waited ${elapsed}s)"
        exit 0
    fi

    sleep $RETRY_INTERVAL
    elapsed=$((elapsed + RETRY_INTERVAL))
done

# Timeout reached
logger -t kioskbook-screensaver "ERROR: Chromium not ready after ${MAX_WAIT}s timeout"
exit 1
