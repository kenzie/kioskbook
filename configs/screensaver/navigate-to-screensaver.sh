#!/bin/bash
# Navigate Chromium to screensaver page

SCREENSAVER_PATH="file:///opt/kioskbook-repo/configs/screensaver/screensaver.html"
CHROME_REMOTE_DEBUG_PORT=9222

# Use Chrome DevTools Protocol to navigate
curl -s "http://localhost:${CHROME_REMOTE_DEBUG_PORT}/json" | \
    grep -Po '"webSocketDebuggerUrl":.*?[^\\]"' | \
    head -1 | \
    grep -Po 'ws://.*?[^\\]"' | \
    sed 's/"$//' | \
    xargs -I {} wscat -x "{\"id\":1,\"method\":\"Page.navigate\",\"params\":{\"url\":\"${SCREENSAVER_PATH}\"}}" -c {} 2>/dev/null || {
        # Fallback: Use xdotool to navigate
        export DISPLAY=:0
        sleep 1
        xdotool key --clearmodifiers ctrl+l
        sleep 0.2
        xdotool type --clearmodifiers "${SCREENSAVER_PATH}"
        sleep 0.2
        xdotool key --clearmodifiers Return
    }

logger -t kioskbook-screensaver "Activated screensaver mode"
