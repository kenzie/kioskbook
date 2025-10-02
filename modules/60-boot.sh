#!/bin/bash
#
# Module: 60-boot.sh
# Description: Branded boot with Plymouth splash screen (Route 19 logo)
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Branded Boot"

log_module "$module_name" "Starting branded boot configuration with Plymouth..."

# Install Plymouth
log_module "$module_name" "Installing Plymouth..."
if ! dpkg -l | grep -q "^ii.*plymouth"; then
    apt-get update
    apt-get install -y plymouth plymouth-themes
    updated=true
fi

# Configure GRUB for Plymouth boot splash
log_module "$module_name" "Configuring GRUB..."
plymouth_updated=false

# Update GRUB defaults for Plymouth (requires 'splash' parameter and loglevel=0)
# Check if both splash and loglevel=0 are present (order doesn't matter)
current_params=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub || echo "")
if ! echo "$current_params" | grep -q "splash" || ! echo "$current_params" | grep -q "loglevel=0"; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 systemd.show_status=false rd.udev.log_level=0 vt.global_cursor_default=0 console=tty3 amdgpu.hdcp=0 amdgpu.tmz=0 amdgpu.sg_display=0 amdgpu.gpu_recovery=1 amdgpu.noretry=0"/' /etc/default/grub
    plymouth_updated=true
fi

if ! grep -q "^GRUB_TIMEOUT=0" /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    plymouth_updated=true
fi

if ! grep -q "^GRUB_TIMEOUT_STYLE=hidden" /etc/default/grub; then
    echo "GRUB_TIMEOUT_STYLE=hidden" >> /etc/default/grub
    plymouth_updated=true
fi

if ! grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
    echo 'GRUB_CMDLINE_LINUX=""' >> /etc/default/grub
    plymouth_updated=true
fi

# Use gfxterm for Plymouth (graphics mode required)
if ! grep -q "^GRUB_TERMINAL_OUTPUT=gfxterm" /etc/default/grub; then
    sed -i 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT=gfxterm/' /etc/default/grub
    if ! grep -q "^GRUB_TERMINAL_OUTPUT=" /etc/default/grub; then
        echo "GRUB_TERMINAL_OUTPUT=gfxterm" >> /etc/default/grub
    fi
    plymouth_updated=true
fi

# Remove GRUB_TERMINAL setting (let it auto-detect)
if grep -q "^GRUB_TERMINAL=" /etc/default/grub; then
    sed -i '/^GRUB_TERMINAL=/d' /etc/default/grub
    plymouth_updated=true
fi

if ! grep -q "^GRUB_DISABLE_OS_PROBER=true" /etc/default/grub; then
    echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
    plymouth_updated=true
fi

if ! grep -q "^GRUB_DISABLE_RECOVERY=true" /etc/default/grub; then
    echo "GRUB_DISABLE_RECOVERY=true" >> /etc/default/grub
    plymouth_updated=true
fi

# Use native resolution for Plymouth
if ! grep -q "^GRUB_GFXMODE=auto" /etc/default/grub; then
    sed -i 's/^GRUB_GFXMODE=.*/GRUB_GFXMODE=auto/' /etc/default/grub
    if ! grep -q "^GRUB_GFXMODE=" /etc/default/grub; then
        echo "GRUB_GFXMODE=auto" >> /etc/default/grub
    fi
    plymouth_updated=true
fi

if ! grep -q "^GRUB_GFXPAYLOAD_LINUX=keep" /etc/default/grub; then
    echo "GRUB_GFXPAYLOAD_LINUX=keep" >> /etc/default/grub
    plymouth_updated=true
fi

# Install Route 19 Plymouth theme
log_module "$module_name" "Installing Route 19 Plymouth theme..."
theme_dir="/usr/share/plymouth/themes/route19"

if [[ ! -d "$theme_dir" ]] || [[ ! -f "$theme_dir/route19.plymouth" ]]; then
    mkdir -p "$theme_dir"
    cp -r "$SCRIPT_DIR/configs/plymouth/route19/"* "$theme_dir/"
    plymouth_updated=true
    log_module "$module_name" "Route 19 theme installed"
fi

# Set Route 19 as default Plymouth theme (Debian way using update-alternatives)
log_module "$module_name" "Setting Route 19 as default theme..."
theme_file="$theme_dir/route19.plymouth"

# Register and set Route 19 theme as default
if [[ -f "$theme_file" ]]; then
    # Install alternative (doesn't error if already exists)
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth "$theme_file" 100 >/dev/null 2>&1 || true

    # Set as default
    update-alternatives --set default.plymouth "$theme_file" >/dev/null 2>&1

    plymouth_updated=true
    log_module "$module_name" "Route 19 theme activated"
fi

# Always update GRUB and initramfs to ensure changes are applied
# (needed because theme files might be updated even if checks pass)
log_module "$module_name" "Updating GRUB..."
update-grub

log_module "$module_name" "Updating initramfs (this may take a minute)..."
update-initramfs -u

log_module "$module_name" "Plymouth configuration updated"

# Configure systemd for silent boot
log_module "$module_name" "Configuring systemd..."
mkdir -p /etc/systemd/system.conf.d
cp "$SCRIPT_DIR/configs/systemd/silent.conf" /etc/systemd/system.conf.d/silent.conf

# Configure kernel parameters
log_module "$module_name" "Configuring kernel parameters..."
mkdir -p /etc/modprobe.d
cp "$SCRIPT_DIR/configs/grub/modprobe-silent.conf" /etc/modprobe.d/silent.conf

# Enable early KMS for AMD GPU (required for Plymouth graphics)
log_module "$module_name" "Enabling early KMS for AMD GPU..."
mkdir -p /etc/initramfs-tools/modules.d
cp "$SCRIPT_DIR/configs/initramfs/modules" /etc/initramfs-tools/modules.d/kioskbook.conf

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

log_module_success "$module_name" "Branded boot with Plymouth configured - Route 19 logo will display during boot"
