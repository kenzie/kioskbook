#!/bin/sh
# Alpine Linux Kiosk Installation - Proper Way
# Based on Alpine Linux official documentation

set -e

echo "Alpine Linux Kiosk Installation"
echo "================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Check for NVMe drive
DISK="/dev/nvme0n1"
if [ ! -b "$DISK" ]; then
    echo "ERROR: NVMe drive $DISK not found"
    exit 1
fi

echo "Target disk: $DISK"
echo ""
echo "WARNING: This will erase all data on $DISK"
echo "Press Enter to continue, or Ctrl+C to abort"
read

# Run Alpine's standard setup
echo "Starting Alpine Linux installation..."
echo "Follow the prompts to configure your system:"
echo "- Keyboard: us us"
echo "- Hostname: kioskbook" 
echo "- Network: eth0 dhcp"
echo "- Root password: [set your password]"
echo "- Timezone: UTC"
echo "- Proxy: none"
echo "- SSH: openssh"
echo "- Disk: sys $DISK"
echo ""

setup-alpine

echo ""
echo "Alpine Linux base installation complete!"
echo "System will reboot automatically."
echo ""
echo "After reboot, login as root and run:"
echo "  apk add curl"
echo "  curl -O https://raw.githubusercontent.com/kenzie/kioskbook/main/setup-kiosk.sh"
echo "  chmod +x setup-kiosk.sh"
echo "  ./setup-kiosk.sh"
echo ""
echo "Remove the USB drive and press Enter to reboot..."
read
reboot