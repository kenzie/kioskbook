#!/bin/bash
# Navigate Chromium back to application

APP_URL="http://localhost:5173"

export DISPLAY=:0

# Use xdotool to navigate Chromium
xdotool key --clearmodifiers ctrl+l
sleep 0.3
xdotool type --clearmodifiers "${APP_URL}"
sleep 0.3
xdotool key --clearmodifiers Return

logger -t kioskbook-screensaver "Restored application mode"
