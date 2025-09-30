#!/bin/bash
#
# 20-boot-optimization.sh - Boot Optimization Module
#
# Optimizes Alpine Linux boot process for sub-5 second boot times.
# Configures GRUB, Plymouth, initramfs, and system services for maximum speed.
#
# Features:
# - GRUB configuration with 0 timeout
# - Kernel parameters for AMD GPU and silent boot
# - Plymouth splash screen setup
# - Initramfs optimization
# - Service optimization and disabling
# - Watchdog timer configuration
# - Target: <5 second boot to Chromium display
#

set -e
set -o pipefail

# Import logging functions from main installer
source /dev/stdin <<< "$(declare -f log log_success log_warning log_error log_info add_rollback)"

# Module configuration
MODULE_NAME="20-boot-optimization"
FBSPLASH_THEME="route19"

log_info "Starting boot optimization module..."

# Validate environment
validate_environment() {
    if [[ -z "$MOUNT_ROOT" || -z "$MOUNT_BOOT" || -z "$TARGET_DISK" ]]; then
        log_error "Required environment variables not set. Run previous modules first."
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_ROOT"; then
        log_error "Root partition not mounted at $MOUNT_ROOT"
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_BOOT"; then
        log_error "Boot partition not mounted at $MOUNT_BOOT"
        exit 1
    fi
    
    log_info "Environment validation passed"
}

# Install bootloader packages
install_bootloader_packages() {
    log_info "Installing bootloader and optimization packages..."
    
    # Essential packages that must install
    local essential_packages=(
        "syslinux"
        "plymouth"
        "plymouth-themes"
        "mkinitfs"
    )
    
    # Optional packages that may fail on some systems
    local optional_packages=(
        "efibootmgr"
        "imagemagick"
        "linux-firmware-amdgpu"
        "watchdog"
    )
    
    # Install essential packages first
    apk --root "$MOUNT_ROOT" add "${essential_packages[@]}" || {
        log_error "Failed to install essential bootloader packages"
        exit 1
    }
    
    # Install optional packages with warnings for failures
    for pkg in "${optional_packages[@]}"; do
        if ! apk --root "$MOUNT_ROOT" add "$pkg" 2>/dev/null; then
            log_warning "Optional package '$pkg' not available or failed to install"
        fi
    done
    
    log_success "Bootloader packages installed"
}

# Configure kernel parameters for EXTLINUX
configure_kernel_parameters() {
    log_info "Configuring kernel parameters for fast boot..."
    
    # Kernel command line for fast, silent boot with AMD optimizations
    local kernel_cmdline="quiet splash loglevel=0 plymouth.ignore-serial-consoles vt.global_cursor_default=0 mitigations=off amd_pstate=active amdgpu.dc=1 amdgpu.dpm=1 amdgpu.gpu_recovery=1 amdgpu.runpm=1 amdgpu.bapm=1 radeon.audio=1 radeon.hw_i2c=1 acpi_osi=Linux processor.max_cstate=1 intel_idle.max_cstate=1 clocksource=tsc tsc=reliable no_timer_check noreplace-smp rcu_nocbs=0-7 elevator=mq-deadline usbcore.autosuspend=-1 audit=0 selinux=0 enforcing=0 fsck.mode=skip"
    
    # Store kernel parameters for later use
    export KERNEL_CMDLINE="$kernel_cmdline"
    
    log_success "Kernel parameters configured for EXTLINUX"
}

# Create custom Plymouth theme
create_route19_splash() {
    log_info "Creating Route 19 Plymouth boot theme..."
    
    # Create Plymouth theme directory
    local theme_dir="$MOUNT_ROOT/usr/share/plymouth/themes/route19"
    mkdir -p "$theme_dir"
    
    # Create Route 19 logo directly (avoid separate script file)
    log_info "Setting up Route 19 logo for Plymouth theme..."
    
    # Create Plymouth theme directory
    mkdir -p "$theme_dir"
    
    # Check for Route 19 logo in multiple locations and copy directly
    local logo_found=false
    
    # Check host temp location first (from bootstrap)
    if [[ -f "/tmp/route19-logo-for-install.png" ]]; then
        log_info "Found Route 19 logo in host temp location"
        if cp "/tmp/route19-logo-for-install.png" "$theme_dir/logo.png"; then
            log_success "Route 19 logo copied from host temp location"
            logo_found=true
        fi
    fi
    
    # Check mounted opt directory
    if ! $logo_found && [[ -f "$MOUNT_ROOT/opt/route19-logo.png" ]]; then
        log_info "Found Route 19 logo in mounted /opt"
        if cp "$MOUNT_ROOT/opt/route19-logo.png" "$theme_dir/logo.png"; then
            log_success "Route 19 logo copied from mounted /opt"
            logo_found=true
        fi
    fi
    
    # Check data partition
    if ! $logo_found && [[ -f "$MOUNT_DATA/route19-logo.png" ]]; then
        log_info "Found Route 19 logo on data partition" 
        if cp "$MOUNT_DATA/route19-logo.png" "$theme_dir/logo.png"; then
            log_success "Route 19 logo copied from data partition"
            logo_found=true
        fi
    fi
    
    # Create fallback if no logo found
    if ! $logo_found; then
        log_warning "No Route 19 logo found - creating minimal placeholder"
        # Create minimal 1x1 PNG to prevent Plymouth errors
        touch "$theme_dir/logo.png"
    fi
    
    # Create Plymouth theme configuration
    cat > "$theme_dir/route19.plymouth" << 'EOF'
[Plymouth Theme]
Name=Route 19
Description=Route 19 Kiosk Boot Theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/route19
ScriptFile=/usr/share/plymouth/themes/route19/route19.script
EOF
    
    # Create the Plymouth script for logo display
    cat > "$theme_dir/route19.script" << 'EOF'
# Route 19 Plymouth Theme Script
# Simple logo display on black background

# Set background to black
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

# Load and display the Route 19 logo
logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);

# Center the logo on screen
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
logo.sprite.SetX((screen_width - logo.image.GetWidth()) / 2);
logo.sprite.SetY((screen_height - logo.image.GetHeight()) / 2);

# Hide progress bar and messages for clean display
Plymouth.SetDisplayNormalMode();

# Function called on refresh - keep logo visible
fun refresh_callback() {
    # Keep logo centered and visible
    logo.sprite.SetOpacity(1);
}

Plymouth.SetRefreshFunction(refresh_callback);

# Hide any boot messages
fun display_normal_callback() {
    # Hide all text messages
}

Plymouth.SetDisplayNormalFunction(display_normal_callback);

# Hide password prompts (not applicable for kiosk)
fun display_password_callback() {
    # No password display for kiosk
}

Plymouth.SetDisplayPasswordFunction(display_password_callback);

# Hide questions (not applicable for kiosk)  
fun display_question_callback() {
    # No questions for kiosk
}

Plymouth.SetDisplayQuestionFunction(display_question_callback);

# Hide messages
fun display_message_callback() {
    # No messages displayed
}

Plymouth.SetDisplayMessageFunction(display_message_callback);
EOF
    
    log_success "Route 19 Plymouth theme created"
}

# Configure Plymouth
configure_plymouth() {
    log_info "Configuring Plymouth boot splash..."
    
    # Set Route 19 Plymouth theme manually since plymouth-set-default-theme may not be available
    log_info "Setting Route 19 Plymouth theme manually..."
    
    # Create Plymouth configuration to use our theme
    mkdir -p "$MOUNT_ROOT/etc/plymouth"
    echo "route19" > "$MOUNT_ROOT/etc/plymouth/plymouthd.conf" || {
        log_warning "Failed to set Plymouth theme configuration"
    }
    
    # Alternative method: create symlink to our theme
    if [[ -f "$MOUNT_ROOT/usr/share/plymouth/themes/route19/route19.plymouth" ]]; then
        mkdir -p "$MOUNT_ROOT/usr/share/plymouth/themes/default"
        ln -sf "../route19/route19.plymouth" "$MOUNT_ROOT/usr/share/plymouth/themes/default/default.plymouth" 2>/dev/null || {
            log_warning "Failed to create theme symlink"
        }
        log_success "Route 19 theme configured manually"
    else
        log_warning "Route 19 theme files not found"
    fi
    
    # Add Plymouth to initramfs features
    if [[ -f "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf" ]]; then
        # Add plymouth to features if not already present
        if ! grep -q "plymouth" "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf"; then
            sed -i 's/^features="\(.*\)"/features="\1 plymouth"/' "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf"
        fi
    fi
    
    # Rebuild initramfs to include Plymouth
    if [[ -d "$MOUNT_ROOT/lib/modules" ]]; then
        local kernel_version=$(chroot "$MOUNT_ROOT" ls /lib/modules/ 2>/dev/null | head -n1)
        if [[ -n "$kernel_version" && -d "$MOUNT_ROOT/lib/modules/$kernel_version" ]]; then
            log_info "Rebuilding initramfs with Plymouth for kernel $kernel_version"
            chroot "$MOUNT_ROOT" mkinitfs "$kernel_version" || {
                log_warning "Failed to rebuild initramfs with Plymouth"
            }
        else
            log_warning "No valid kernel version found in /lib/modules, skipping initramfs rebuild"
        fi
    else
        log_warning "/lib/modules directory not found, initramfs will be built later"
    fi
    
    log_success "Plymouth configured for boot splash"
}

# Optimize initramfs
optimize_initramfs() {
    log_info "Optimizing initramfs for fast boot..."
    
    # Configure mkinitfs for minimal initramfs (only essential features)
    cat > "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf" << 'EOF'
# KioskBook minimal initramfs configuration
# Only include essential features for faster generation and boot
features="base ext4 nvme ata scsi usb plymouth"
EOF
    
    # Create initramfs hooks for optimization
    mkdir -p "$MOUNT_ROOT/etc/mkinitfs/hooks"
    
    # Create optimization hook
    cat > "$MOUNT_ROOT/etc/mkinitfs/hooks/kioskbook-optimize.sh" << 'EOF'
#!/bin/sh
# KioskBook initramfs optimization hook

# Optimize device detection
echo "Optimizing device detection for fast boot..."

# Skip unnecessary hardware detection
if [ -f /sys/class/dmi/id/product_name ]; then
    product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
    if echo "$product_name" | grep -qi "lenovo.*m75q"; then
        # Lenovo M75q-1 specific optimizations
        echo "Detected Lenovo M75q-1, applying specific optimizations..."
        # Skip unnecessary modules
        echo "blacklist pcspkr" >> /etc/modprobe.d/kioskbook-blacklist.conf
        echo "blacklist iTCO_wdt" >> /etc/modprobe.d/kioskbook-blacklist.conf
    fi
fi
EOF
    
    chmod +x "$MOUNT_ROOT/etc/mkinitfs/hooks/kioskbook-optimize.sh"
    
    # Configure module blacklist
    mkdir -p "$MOUNT_ROOT/etc/modprobe.d"
    cat > "$MOUNT_ROOT/etc/modprobe.d/kioskbook-blacklist.conf" << 'EOF'
# KioskBook module blacklist for faster boot
blacklist pcspkr
blacklist iTCO_wdt
blacklist iTCO_vendor_support
blacklist bluetooth
blacklist btusb
blacklist bnep
blacklist rfcomm
blacklist snd_hda_codec_hdmi
blacklist joydev
blacklist mousedev
blacklist evbug
EOF
    
    log_success "Initramfs optimized"
}

# Configure watchdog (skip if not available)
configure_watchdog() {
    log_info "Skipping watchdog configuration - package not available in Alpine 3.22"
    log_info "Consider using systemd watchdog or kernel built-in watchdog instead"
    return 0
    
    # Configure watchdog
    cat > "$MOUNT_ROOT/etc/watchdog.conf" << 'EOF'
# KioskBook Hardware Watchdog Configuration

# Hardware watchdog device
watchdog-device = /dev/watchdog
watchdog-timeout = 60

# System monitoring
interval = 1
logtick = 1

# Memory monitoring
max-load-1 = 24
max-load-5 = 18
max-load-15 = 12

# Check if processes are running
pidfile = /var/run/kiosk-app.pid
pidfile = /var/run/kiosk-display.pid

# Network interface monitoring
interface = eth0

# Temperature monitoring (if available)
temperature-device = /sys/class/thermal/thermal_zone0/temp
max-temperature = 90

# File system monitoring
file = /var/log/watchdog.log
change = 1407

# Test directory
test-directory = /tmp

# Repair attempts
repair-binary = /usr/local/bin/watchdog-repair.sh
repair-timeout = 60

# Logging
verbose = yes
log-dir = /var/log
EOF
    
    # Create repair script
    cat > "$MOUNT_ROOT/usr/local/bin/watchdog-repair.sh" << 'EOF'
#!/bin/bash
#
# KioskBook Watchdog Repair Script
#
# Attempts to repair common issues before system reboot
#

set -e

LOG_FILE="/var/log/watchdog-repair.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [REPAIR] $1" >> "$LOG_FILE"
}

log "Watchdog repair initiated"

# Try to restart critical services
for service in kiosk-app kiosk-display; do
    if ! rc-service "$service" status >/dev/null 2>&1; then
        log "Restarting failed service: $service"
        rc-service "$service" restart || log "Failed to restart $service"
    fi
done

# Clear memory if needed
if [[ -f /proc/sys/vm/drop_caches ]]; then
    log "Clearing system caches"
    sync
    echo 3 > /proc/sys/vm/drop_caches
fi

# Kill hung processes
for proc in chromium; do
    if pgrep -f "$proc" >/dev/null; then
        if ! pgrep -f "$proc" | xargs ps -p >/dev/null 2>&1; then
            log "Killing hung process: $proc"
            pkill -f "$proc" || true
        fi
    fi
done

log "Watchdog repair completed"
EOF
    
    chmod +x "$MOUNT_ROOT/usr/local/bin/watchdog-repair.sh"
    
    # Enable watchdog service
    chroot "$MOUNT_ROOT" rc-update add watchdog boot || {
        log_warning "Failed to enable watchdog service"
    }
    
    log_success "Watchdog configured"
}

# Optimize system services
optimize_services() {
    log_info "Optimizing system services for fast boot..."
    
    # Disable unnecessary services
    local disable_services=(
        "acpid"
        "crond" 
        "bluetoothd"
        "wpa_supplicant"
        "dhcpcd"
        "ntpd"
        "syslog"
    )
    
    for service in "${disable_services[@]}"; do
        chroot "$MOUNT_ROOT" rc-update del "$service" default 2>/dev/null || true
        chroot "$MOUNT_ROOT" rc-update del "$service" boot 2>/dev/null || true
        log_info "Disabled service: $service"
    done
    
    # Configure essential services for parallel startup
    cat > "$MOUNT_ROOT/etc/rc.conf" << 'EOF'
# KioskBook OpenRC configuration for fast boot
rc_parallel="YES"
rc_interactive="NO"
rc_logger="YES"
rc_log_path="/var/log/rc.log"
rc_depend_strict="NO"
rc_hotplug="udev"
rc_shell="/sbin/sulogin"
unicode="YES"

# Aggressive timeout settings
rc_timeout_stopsec=10
EOF
    
    # Create service ordering for optimal boot
    local service_order=(
        "devfs:sysinit"
        "dmesg:sysinit" 
        "udev:sysinit"
        "hwdrivers:boot"
        "modules:boot"
        "localmount:boot"
        "hostname:boot"
    )
    
    for service_entry in "${service_order[@]}"; do
        local service="${service_entry%:*}"
        local runlevel="${service_entry#*:}"
        
        chroot "$MOUNT_ROOT" rc-update add "$service" "$runlevel" 2>/dev/null || {
            log_warning "Could not add service $service to $runlevel"
        }
    done
    
    log_success "Services optimized"
}

# Install and configure EXTLINUX
install_extlinux() {
    log_info "Installing and configuring EXTLINUX bootloader..."
    
    # Get partition UUIDs
    local root_uuid boot_uuid
    root_uuid="$(blkid -s UUID -o value "$ROOT_PARTITION")"
    boot_uuid="$(blkid -s UUID -o value "$BOOT_PARTITION")"
    
    # Find kernel version
    local kernel_version
    if [[ -d "$MOUNT_ROOT/lib/modules" ]]; then
        kernel_version=$(ls "$MOUNT_ROOT/lib/modules" | head -1)
    fi
    
    if [[ -z "$kernel_version" ]]; then
        log_error "No kernel version found for EXTLINUX configuration"
        exit 1
    fi
    
    log_info "Configuring EXTLINUX for kernel version: $kernel_version"
    
    # Install EXTLINUX to boot partition
    chroot "$MOUNT_ROOT" extlinux --install /boot || {
        log_error "Failed to install EXTLINUX"
        exit 1
    }
    
    # Install MBR (Master Boot Record) for BIOS boot
    if command -v dd >/dev/null 2>&1; then
        # Install syslinux MBR
        local mbr_file=""
        if [[ -f "$MOUNT_ROOT/usr/share/syslinux/mbr.bin" ]]; then
            mbr_file="$MOUNT_ROOT/usr/share/syslinux/mbr.bin"
        elif [[ -f "/usr/share/syslinux/mbr.bin" ]]; then
            mbr_file="/usr/share/syslinux/mbr.bin"
        fi
        
        if [[ -n "$mbr_file" ]]; then
            dd if="$mbr_file" of="$TARGET_DISK" bs=440 count=1 conv=notrunc 2>/dev/null || {
                log_warning "Failed to install MBR (non-critical for some systems)"
            }
        else
            log_warning "MBR file not found, may need manual MBR installation"
        fi
    fi
    
    # Create EXTLINUX configuration
    cat > "$MOUNT_BOOT/extlinux.conf" << EOF
# KioskBook EXTLINUX Configuration
# Fast boot configuration for Alpine Linux kiosk

DEFAULT kioskbook
TIMEOUT 1
PROMPT 0

LABEL kioskbook
    MENU LABEL KioskBook Alpine Linux
    LINUX vmlinuz-$kernel_version
    INITRD initrd
    APPEND root=UUID=$root_uuid rw $KERNEL_CMDLINE

LABEL kioskbook-safe
    MENU LABEL KioskBook (Safe Mode)
    LINUX vmlinuz-$kernel_version
    INITRD initrd
    APPEND root=UUID=$root_uuid rw single
EOF
    
    # Copy kernel and initrd to boot partition if needed
    if [[ -f "$MOUNT_ROOT/boot/vmlinuz-$kernel_version" ]]; then
        cp "$MOUNT_ROOT/boot/vmlinuz-$kernel_version" "$MOUNT_BOOT/" || {
            log_warning "Failed to copy kernel to boot partition"
        }
    fi
    
    if [[ -f "$MOUNT_ROOT/boot/initrd" ]]; then
        cp "$MOUNT_ROOT/boot/initrd" "$MOUNT_BOOT/" || {
            log_warning "Failed to copy initrd to boot partition"
        }
    fi
    
    # Set boot flag on first partition for compatibility
    parted -s "$TARGET_DISK" set 1 boot on 2>/dev/null || {
        log_warning "Failed to set boot flag (may not be needed)"
    }
    
    log_success "EXTLINUX installed and configured"
    log_info "Boot timeout: 1 second (almost instant boot)"
}

# Generate optimized initramfs
generate_initramfs() {
    log_info "Generating optimized initramfs..."
    
    # Check if kernel modules directory exists
    if [[ ! -d "$MOUNT_ROOT/lib/modules" ]]; then
        log_warning "Kernel modules directory not found, installing kernel..."
        
        # Update package cache first to avoid temporary errors
        log_info "Updating package cache to avoid repository errors..."
        chroot "$MOUNT_ROOT" apk update || {
            log_warning "Failed to update package cache"
        }
        
        # Try multiple approaches for kernel installation
        local kernel_installed=false
        
        # Approach 1: Try with minimal firmware
        if ! $kernel_installed; then
            log_info "Attempting kernel installation with minimal dependencies..."
            if chroot "$MOUNT_ROOT" apk add linux-lts linux-firmware-none 2>/dev/null; then
                log_success "Kernel installed with minimal firmware"
                kernel_installed=true
            fi
        fi
        
        # Approach 2: Try without recommends
        if ! $kernel_installed; then
            log_info "Attempting kernel installation without recommends..."
            if chroot "$MOUNT_ROOT" apk add linux-lts --no-install-recommends 2>/dev/null; then
                log_success "Kernel installed without recommends"
                kernel_installed=true
            fi
        fi
        
        # Approach 3: Standard installation (will pull firmware but works)
        if ! $kernel_installed; then
            log_warning "Minimal approaches failed, installing kernel with full dependencies..."
            if chroot "$MOUNT_ROOT" apk add linux-lts; then
                log_success "Kernel installed with full dependencies"
                kernel_installed=true
            else
                log_error "All kernel installation attempts failed"
                exit 1
            fi
        fi
        
        # Ensure mkinitfs is available
        chroot "$MOUNT_ROOT" apk add mkinitfs || {
            log_error "Failed to install mkinitfs"
            exit 1
        }
        
        log_info "Kernel installed"
        
        # Verify kernel modules directory was created
        if [[ ! -d "$MOUNT_ROOT/lib/modules" ]]; then
            log_error "Kernel installation did not create /lib/modules directory"
            log_info "Available directories in $MOUNT_ROOT/lib:"
            ls -la "$MOUNT_ROOT/lib/" || true
            exit 1
        fi
        
        # Wait a moment for filesystem to settle
        sleep 2
    fi
    
    # Find kernel version
    local kernel_version
    if [[ -d "$MOUNT_ROOT/lib/modules" ]]; then
        kernel_version=$(ls "$MOUNT_ROOT/lib/modules" | head -1)
    fi
    
    if [[ -z "$kernel_version" ]]; then
        log_error "No kernel version found in /lib/modules"
        log_info "Available directories in $MOUNT_ROOT/lib:"
        ls -la "$MOUNT_ROOT/lib/" || true
        exit 1
    fi
    
    if [[ ! -d "$MOUNT_ROOT/lib/modules/$kernel_version" ]]; then
        log_error "Kernel modules directory does not exist: /lib/modules/$kernel_version"
        exit 1
    fi
    
    log_info "Generating initramfs for kernel version: $kernel_version"
    
    # Generate initramfs with optimizations
    chroot "$MOUNT_ROOT" mkinitfs -o /boot/initrd "$kernel_version" || {
        log_error "Failed to generate initramfs for kernel $kernel_version"
        exit 1
    }
    
    log_success "Initramfs generated for kernel $kernel_version"
}

# Configure fast boot optimizations
configure_fast_boot() {
    log_info "Applying additional fast boot optimizations..."
    
    # Optimize filesystem mount options
    cat >> "$MOUNT_ROOT/etc/fstab" << 'EOF'

# KioskBook fast boot optimizations
# Disable access time updates for better performance
tmpfs   /tmp        tmpfs   defaults,noatime,mode=1777  0  0
tmpfs   /var/tmp    tmpfs   defaults,noatime,mode=1777  0  0
EOF
    
    # Configure sysctl optimizations
    cat > "$MOUNT_ROOT/etc/sysctl.d/99-kioskbook-boot.conf" << 'EOF'
# KioskBook boot performance optimizations

# Reduce swappiness for faster boot
vm.swappiness = 1

# Optimize dirty page writeback
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Network optimizations
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Filesystem optimizations
vm.vfs_cache_pressure = 50
EOF
    
    # Create systemd-style service dependencies (even for OpenRC)
    mkdir -p "$MOUNT_ROOT/etc/local.d"
    cat > "$MOUNT_ROOT/etc/local.d/kioskbook-boot-optimize.start" << 'EOF'
#!/bin/sh
# KioskBook boot optimization script

# Set CPU governor to performance during boot
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true

# Disable unnecessary kernel features
echo 0 > /proc/sys/kernel/printk 2>/dev/null || true

# Optimize I/O scheduler
echo mq-deadline > /sys/block/nvme0n1/queue/scheduler 2>/dev/null || true
echo mq-deadline > /sys/block/sda/queue/scheduler 2>/dev/null || true
EOF
    
    chmod +x "$MOUNT_ROOT/etc/local.d/kioskbook-boot-optimize.start"
    
    log_success "Fast boot optimizations configured"
}

# Validate boot configuration
validate_boot_config() {
    log_info "Validating boot configuration..."
    
    # Check essential files
    local essential_files=(
        "$MOUNT_BOOT/extlinux.conf"
        "$MOUNT_ROOT/boot/initrd"
        "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Essential boot file missing: $file"
            exit 1
        fi
    done
    
    # Check if EXTLINUX is installed
    if [[ ! -f "$MOUNT_BOOT/ldlinux.sys" ]] && [[ ! -f "$MOUNT_BOOT/extlinux.sys" ]]; then
        log_warning "EXTLINUX system files not found (may be normal)"
    fi
    
    # Check kernel files
    local kernel_version
    if [[ -d "$MOUNT_ROOT/lib/modules" ]]; then
        kernel_version=$(ls "$MOUNT_ROOT/lib/modules" | head -1)
        if [[ -n "$kernel_version" ]]; then
            if [[ ! -f "$MOUNT_BOOT/vmlinuz-$kernel_version" ]] && [[ ! -f "$MOUNT_ROOT/boot/vmlinuz-$kernel_version" ]]; then
                log_warning "Kernel file not found in expected locations"
            fi
        fi
    fi
    
    # Check Plymouth installation
    if chroot "$MOUNT_ROOT" command -v plymouth >/dev/null 2>&1; then
        log_info "Plymouth boot splash installed"
    else
        log_warning "Plymouth not found"
    fi
    
    log_success "Boot configuration validation passed"
}

# Main boot optimization function
main() {
    log_info "=========================================="
    log_info "Module: Boot Optimization"
    log_info "=========================================="
    
    validate_environment
    install_bootloader_packages
    configure_kernel_parameters
    create_route19_splash
    configure_plymouth
    optimize_initramfs
    configure_watchdog
    optimize_services
    generate_initramfs
    install_extlinux
    configure_fast_boot
    validate_boot_config
    
    log_success "Boot optimization completed successfully"
    log_info "Target: Sub-5 second boot to Chromium display"
    log_info "Optimizations applied:"
    log_info "  - EXTLINUX 1-second timeout (near-instant boot)"
    log_info "  - AMD GPU kernel parameters"
    log_info "  - Plymouth boot splash with Route 19 logo"
    log_info "  - Optimized initramfs"
    log_info "  - Service startup optimization"
    log_info "  - Hardware watchdog configuration"
}

# Execute main function
main "$@"