#!/bin/bash
#
# Module: 40-fonts.sh
# Description: Font installation and configuration
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Fonts"

log_module "$module_name" "Starting font installation..."

# Install Inter font and other essentials
log_module "$module_name" "Installing system fonts..."
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    fonts-inter \
    fonts-noto \
    fontconfig

# Download and install CaskaydiaCove Nerd Font
log_module "$module_name" "Installing CaskaydiaCove Nerd Font..."
font_dir="/usr/local/share/fonts/nerd-fonts"
mkdir -p "$font_dir"

wget -q -O /tmp/CascadiaCode.zip \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip"

unzip -o -q /tmp/CascadiaCode.zip -d "$font_dir/"
rm -f /tmp/CascadiaCode.zip

# Install fontconfig configuration
log_module "$module_name" "Configuring font priorities..."
mkdir -p /etc/fonts/conf.d
cp "$SCRIPT_DIR/configs/fonts/10-inter-default.conf" /etc/fonts/conf.d/10-inter-default.conf

# Update font cache
log_module "$module_name" "Updating font cache..."
fc-cache -fv >/dev/null 2>&1

log_module_success "$module_name" "Fonts installed and configured"
