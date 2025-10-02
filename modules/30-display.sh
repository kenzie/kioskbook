#!/bin/bash
#
# Module: 30-display.sh
# Description: Display system, window manager, and kiosk user configuration
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Display System"
KIOSK_USER="kiosk"
KIOSK_HOME="/home/kiosk"

log_module "$module_name" "Starting display system installation..."

# Install X11 and OpenBox
log_module "$module_name" "Installing X11 and window manager..."
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    xorg \
    openbox \
    lightdm \
    xserver-xorg-video-amdgpu \
    mesa-vulkan-drivers \
    vainfo \
    unclutter-xfixes

# Install Chromium
log_module "$module_name" "Installing Chromium browser..."
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    chromium \
    chromium-driver

# Create kiosk user if it doesn't exist
log_module "$module_name" "Creating kiosk user..."
if ! id "$KIOSK_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G audio,video,sudo "$KIOSK_USER"
    log_module "$module_name" "Created user: $KIOSK_USER"
else
    log_module "$module_name" "User $KIOSK_USER already exists"
fi

# Ensure kiosk user is in sudo group (for existing users)
if ! groups "$KIOSK_USER" | grep -q sudo; then
    usermod -aG sudo "$KIOSK_USER"
    log_module "$module_name" "Added $KIOSK_USER to sudo group"
fi

# Create OpenBox configuration directory
mkdir -p "$KIOSK_HOME/.config/openbox"

# Install OpenBox autostart configuration
log_module "$module_name" "Configuring OpenBox autostart..."
cp "$SCRIPT_DIR/configs/openbox/autostart" "$KIOSK_HOME/.config/openbox/autostart"
chmod +x "$KIOSK_HOME/.config/openbox/autostart"
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"

# Configure LightDM for auto-login
log_module "$module_name" "Configuring auto-login..."
cp "$SCRIPT_DIR/configs/systemd/lightdm.conf" /etc/lightdm/lightdm.conf

# Enable LightDM
systemctl enable lightdm

log_module_success "$module_name" "Display system configured"
