#!/bin/bash
# Navigate Chromium to screensaver page

SCREENSAVER_PATH="file:///opt/kioskbook-repo/configs/screensaver/screensaver.html"

export DISPLAY=:0

# Use xdotool to navigate Chromium
xdotool key --clearmodifiers ctrl+l
sleep 0.3
xdotool type --clearmodifiers "${SCREENSAVER_PATH}"
sleep 0.3
xdotool key --clearmodifiers Return

logger -t kioskbook-screensaver "Activated screensaver mode"
