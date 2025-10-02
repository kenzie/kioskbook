#!/bin/bash
# Navigate Chromium back to application

APP_URL="http://localhost:5173"
DEBUG_PORT=9222

# Get the first tab/page ID
PAGE_ID=$(curl -s http://localhost:${DEBUG_PORT}/json | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -n "$PAGE_ID" ]]; then
    # Open new tab with app (use PUT)
    curl -s -X PUT "http://localhost:${DEBUG_PORT}/json/new?${APP_URL}" >/dev/null
    sleep 0.5
    # Close the old screensaver tab
    curl -s -X GET "http://localhost:${DEBUG_PORT}/json/close/${PAGE_ID}" >/dev/null

    logger -t kioskbook-screensaver "Restored application mode"
else
    logger -t kioskbook-screensaver "ERROR: Could not find Chrome tab"
    exit 1
fi
