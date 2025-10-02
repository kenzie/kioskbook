#!/bin/bash
#
# Module: 60-boot.sh
# Description: Silent boot configuration for GRUB and systemd
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Silent Boot"

log_module "$module_name" "Starting silent boot configuration..."

# Configure GRUB for silent boot
log_module "$module_name" "Configuring GRUB..."
updated=false

# Update GRUB defaults
if ! grep -q "quiet splash loglevel=0" /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 console=tty3 rd.systemd.show_status=false rd.udev.log_level=3 systemd.show_status=false"/' /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_TIMEOUT=0" /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_TIMEOUT_STYLE=hidden" /etc/default/grub; then
    echo "GRUB_TIMEOUT_STYLE=hidden" >> /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
    echo 'GRUB_CMDLINE_LINUX=""' >> /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_TERMINAL_OUTPUT=console" /etc/default/grub; then
    echo "GRUB_TERMINAL_OUTPUT=console" >> /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_DISABLE_OS_PROBER=true" /etc/default/grub; then
    echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_DISABLE_RECOVERY=true" /etc/default/grub; then
    echo "GRUB_DISABLE_RECOVERY=true" >> /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_GFXMODE=text" /etc/default/grub; then
    echo "GRUB_GFXMODE=text" >> /etc/default/grub
    updated=true
fi

if ! grep -q "^GRUB_TERMINAL=" /etc/default/grub; then
    sed -i 's/^GRUB_TERMINAL=.*//' /etc/default/grub
    echo "GRUB_TERMINAL=" >> /etc/default/grub
    updated=true
fi

if [[ "$updated" == true ]]; then
    update-grub
    log_module "$module_name" "GRUB updated"
fi

# Configure systemd for silent boot
log_module "$module_name" "Configuring systemd..."
mkdir -p /etc/systemd/system.conf.d
cp "$SCRIPT_DIR/configs/systemd/silent.conf" /etc/systemd/system.conf.d/silent.conf

# Configure kernel parameters
log_module "$module_name" "Configuring kernel parameters..."
mkdir -p /etc/modprobe.d
cp "$SCRIPT_DIR/configs/grub/modprobe-silent.conf" /etc/modprobe.d/silent.conf

# Hide kernel messages
mkdir -p /etc/sysctl.d
cp "$SCRIPT_DIR/configs/grub/sysctl-quiet.conf" /etc/sysctl.d/20-quiet-printk.conf

# Disable verbose fsck during boot
if [[ -f /etc/default/rcS ]]; then
    sed -i 's/^#FSCKFIX=.*/FSCKFIX=yes/' /etc/default/rcS
fi

# Mask services that show boot messages
log_module "$module_name" "Masking verbose services..."
systemctl mask \
    systemd-random-seed.service \
    systemd-update-utmp.service \
    systemd-tmpfiles-setup.service \
    e2scrub_reap.service 2>/dev/null || true

# Configure getty for silent auto-login
log_module "$module_name" "Configuring getty..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cp "$SCRIPT_DIR/configs/systemd/getty-override.conf" /etc/systemd/system/getty@tty1.service.d/override.conf

# Reload systemd
systemctl daemon-reload

log_module_success "$module_name" "Silent boot configured"
