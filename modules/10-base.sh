#!/bin/bash
#
# Module: 10-base.sh
# Description: Base system packages and configuration
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Base System"

log_module "$module_name" "Starting base system setup..."

# Update system packages
log_module "$module_name" "Updating package lists..."
apt-get update

log_module "$module_name" "Upgrading existing packages..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install essential packages
log_module "$module_name" "Installing essential packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget ca-certificates gnupg lsb-release \
    sudo systemd-timesyncd unzip git

# Disable swap for faster boot and deterministic performance
log_module "$module_name" "Disabling swap..."
swapoff -a 2>/dev/null || true
sed -i '/swap/d' /etc/fstab

# Set graphical target
log_module "$module_name" "Setting graphical target..."
systemctl set-default graphical.target

# Disable unnecessary services
log_module "$module_name" "Disabling unnecessary services..."
systemctl disable \
    bluetooth.service \
    cups.service \
    avahi-daemon.service \
    ModemManager.service \
    wpa_supplicant.service 2>/dev/null || true

log_module_success "$module_name" "Base system configured"
