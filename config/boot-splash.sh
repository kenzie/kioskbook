#!/bin/bash
# KioskBook Boot Splash Screen with Route 19 Logo

# Clear screen
clear
echo -e "\033[2J\033[H"

# Try to display Route 19 logo using framebuffer
if [ -c /dev/fb0 ]; then
    # Display Route 19 logo on framebuffer
    fbi -d /dev/fb0 -T 1 /usr/share/kioskbook/route19-fb-logo.png &
    sleep 3
    killall fbi 2>/dev/null
fi

# Fallback: show simple text message
echo -e "\033[1;33mRoute 19 KioskBook\033[0m"
echo
echo -e "\033[1;37mStarting KioskBook...\033[0m"
