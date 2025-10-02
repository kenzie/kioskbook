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

# Update GRUB defaults for silent boot with branded message
if ! grep -q "amdgpu.gpu_recovery=1" /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 systemd.show_status=false rd.udev.log_level=0 console=tty3 amdgpu.hdcp=0 amdgpu.tmz=0 amdgpu.sg_display=0 amdgpu.gpu_recovery=1 amdgpu.noretry=0"/' /etc/default/grub
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
    sed -i 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT=console/' /etc/default/grub
    if ! grep -q "^GRUB_TERMINAL_OUTPUT=" /etc/default/grub; then
        echo "GRUB_TERMINAL_OUTPUT=console" >> /etc/default/grub
    fi
    updated=true
fi

if ! grep -q "^GRUB_TERMINAL=console" /etc/default/grub; then
    sed -i 's/^GRUB_TERMINAL=.*/GRUB_TERMINAL=console/' /etc/default/grub
    if ! grep -q "^GRUB_TERMINAL=" /etc/default/grub; then
        echo "GRUB_TERMINAL=console" >> /etc/default/grub
    fi
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
    sed -i 's/^GRUB_GFXMODE=.*/GRUB_GFXMODE=text/' /etc/default/grub
    if ! grep -q "^GRUB_GFXMODE=" /etc/default/grub; then
        echo "GRUB_GFXMODE=text" >> /etc/default/grub
    fi
    updated=true
fi

# Replace GRUB boot messages with branded KioskBook message
log_module "$module_name" "Branding GRUB boot messages..."
if [[ -f /etc/grub.d/10_linux ]]; then
    # Replace "Loading Linux" with branded message
    if grep -q "Loading Linux" /etc/grub.d/10_linux && ! grep -q "Starting up KioskBook" /etc/grub.d/10_linux; then
        sed -i 's/Loading Linux.*/Starting up KioskBook by Route 19.../' /etc/grub.d/10_linux
        updated=true
    fi
    # Comment out "Loading initial ramdisk" message
    if grep -q "Loading initial ramdisk" /etc/grub.d/10_linux && ! grep -q "# KIOSKBOOK-SILENCED.*Loading initial ramdisk" /etc/grub.d/10_linux; then
        sed -i '/Loading initial ramdisk/s/^/# KIOSKBOOK-SILENCED: /' /etc/grub.d/10_linux
        updated=true
    fi
fi

# Also brand 20_linux_xen if it exists
if [[ -f /etc/grub.d/20_linux_xen ]]; then
    if grep -q "Loading Linux" /etc/grub.d/20_linux_xen && ! grep -q "Starting up KioskBook" /etc/grub.d/20_linux_xen; then
        sed -i 's/Loading Linux.*/Starting up KioskBook by Route 19.../' /etc/grub.d/20_linux_xen
        updated=true
    fi
    if grep -q "Loading initial ramdisk" /etc/grub.d/20_linux_xen && ! grep -q "# KIOSKBOOK-SILENCED.*Loading initial ramdisk" /etc/grub.d/20_linux_xen; then
        sed -i '/Loading initial ramdisk/s/^/# KIOSKBOOK-SILENCED: /' /etc/grub.d/20_linux_xen
        updated=true
    fi
fi

# Ensure Plymouth is not installed (conflicts with silent boot)
log_module "$module_name" "Checking Plymouth..."
if dpkg -l | grep -q "^ii.*plymouth"; then
    log_module "$module_name" "Removing Plymouth..."
    apt-get purge -y plymouth plymouth-themes 2>/dev/null || true
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

# Update initramfs to apply modprobe changes
log_module "$module_name" "Updating initramfs..."
update-initramfs -u

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
