#!/bin/bash
# Navigate Chromium to screensaver page

SCREENSAVER_PATH="file:///opt/kioskbook-repo/configs/screensaver/screensaver.html"
DEBUG_PORT=9222

# Get the first tab/page ID
PAGE_ID=$(curl -s http://localhost:${DEBUG_PORT}/json | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -n "$PAGE_ID" ]]; then
    # Navigate using Chrome DevTools Protocol
    curl -s -X POST "http://localhost:${DEBUG_PORT}/json/activate/${PAGE_ID}" >/dev/null
    sleep 0.2
    curl -s "http://localhost:${DEBUG_PORT}/json/new?${SCREENSAVER_PATH}" >/dev/null
    sleep 0.2
    # Close the old tab
    curl -s -X GET "http://localhost:${DEBUG_PORT}/json/close/${PAGE_ID}" >/dev/null

    logger -t kioskbook-screensaver "Activated screensaver mode"
else
    logger -t kioskbook-screensaver "ERROR: Could not find Chrome tab"
    exit 1
fi
