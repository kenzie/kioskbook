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
        "grub"
        "plymouth"
        "plymouth-themes"
        "mkinitfs"
        "watchdog"
    )
    
    # Optional packages that may fail on some systems
    local optional_packages=(
        "grub-efi"
        "efibootmgr"
        "imagemagick"
        "linux-firmware-amdgpu"
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

# Configure kernel parameters
configure_kernel_parameters() {
    log_info "Configuring kernel parameters for fast boot..."
    
    # Create GRUB configuration directory
    mkdir -p "$MOUNT_ROOT/etc/default"
    
    # Configure GRUB defaults
    cat > "$MOUNT_ROOT/etc/default/grub" << 'EOF'
# GRUB configuration for KioskBook ultra-fast boot
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_DISTRIBUTOR="KioskBook"

# Silent boot parameters with Plymouth
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 rd.systemd.show_status=false rd.udev.log_priority=0 systemd.show_status=false plymouth.ignore-serial-consoles vt.global_cursor_default=0"

# Performance and AMD GPU optimizations
GRUB_CMDLINE_LINUX="mitigations=off amd_pstate=active amdgpu.dc=1 amdgpu.dpm=1 amdgpu.gpu_recovery=1 amdgpu.runpm=1 amdgpu.bapm=1 radeon.audio=1 radeon.hw_i2c=1 acpi_osi=Linux processor.max_cstate=1 intel_idle.max_cstate=1 clocksource=tsc tsc=reliable no_timer_check noreplace-smp rcu_nocbs=0-7 elevator=mq-deadline usbcore.autosuspend=-1 audit=0 selinux=0 enforcing=0 fsck.mode=skip"

# Boot optimization
GRUB_PRELOAD_MODULES="part_gpt part_msdos ext2 linux"
GRUB_DISABLE_RECOVERY=true
GRUB_DISABLE_SUBMENU=true
GRUB_DISABLE_OS_PROBER=true

# Graphics settings
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL=console
EOF
    
    log_success "Kernel parameters configured"
}

# Create custom Plymouth theme
create_route19_splash() {
    log_info "Creating Route 19 Plymouth boot theme..."
    
    # Create Plymouth theme directory
    local theme_dir="$MOUNT_ROOT/usr/share/plymouth/themes/route19"
    mkdir -p "$theme_dir"
    
    # Create route19-logo.png preparation script
    cat > "$MOUNT_ROOT/tmp/create_route19_logo.sh" << 'EOF'
#!/bin/bash
# Create Route 19 logo for boot splash
# This creates a placeholder - replace with actual Route 19 logo file

cd /tmp

# Debug: Check what logo files are available
echo "Checking for Route 19 logo files..."
ls -la /opt/route19-logo.png 2>/dev/null && echo "Found logo at /opt/route19-logo.png" || echo "No logo at /opt/route19-logo.png"
ls -la /data/route19-logo.png 2>/dev/null && echo "Found logo at /data/route19-logo.png" || echo "No logo at /data/route19-logo.png"

# Check if actual Route 19 logo exists (should be provided during installation)
if [[ -f "/opt/route19-logo.png" ]]; then
    echo "Using provided Route 19 logo..."
    cp "/opt/route19-logo.png" "./route19-logo.png" || {
        echo "Failed to copy logo from /opt - creating fallback"
        echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAI9jU77gwAAAABJRU5ErkJggg==" | base64 -d > "./route19-logo.png"
    }
elif [[ -f "/data/route19-logo.png" ]]; then
    echo "Using Route 19 logo from data partition..."
    cp "/data/route19-logo.png" "./route19-logo.png" || {
        echo "Failed to copy logo from /data - creating fallback"
        echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAI9jU77gwAAAABJRU5ErkJggg==" | base64 -d > "./route19-logo.png"
    }
else
    echo "No Route 19 logo found - creating fallback..."
    # Create a placeholder logo with Route 19 text
    if command -v convert >/dev/null 2>&1; then
        convert -size 400x200 xc:transparent \
                -font Liberation-Sans-Bold -pointsize 48 -fill white \
                -gravity center -annotate +0-20 "ROUTE 19" \
                -pointsize 24 -annotate +0+30 "Digital Signage Platform" \
                "./route19-logo.png"
    else
        # Fallback: minimal 1x1 transparent PNG
        echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChAI9jU77gwAAAABJRU5ErkJggg==" | base64 -d > "./route19-logo.png"
    fi
fi

# Prepare logo for optimal 1920x1080 display with black background
if command -v convert >/dev/null 2>&1; then
    echo "Resizing Route 19 logo for 1920x1080 display..."
    convert "./route19-logo.png" \
            -background black \
            -gravity center \
            -extent 1920x1080 \
            "/usr/share/plymouth/themes/route19/logo.png"
else
    echo "ImageMagick not available, using logo as-is..."
    cp "./route19-logo.png" "/usr/share/plymouth/themes/route19/logo.png"
fi

echo "Route 19 splash theme created successfully"
EOF
    
    chmod +x "$MOUNT_ROOT/tmp/create_route19_logo.sh"
    
    # Run the logo creation script
    if chroot "$MOUNT_ROOT" /tmp/create_route19_logo.sh; then
        log_success "Route 19 logo created successfully"
    else
        log_error "Failed to create Route 19 logo - this will affect boot display"
        log_error "Ensure route19-logo.png exists in repository and ImageMagick is available"
        # Create minimal placeholder to prevent Plymouth errors
        mkdir -p "$theme_dir"
        touch "$theme_dir/logo.png"
    fi
    
    # Clean up
    rm -f "$MOUNT_ROOT/tmp/create_route19_logo.sh"
    
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
    
    # Set Route 19 Plymouth theme
    if chroot "$MOUNT_ROOT" command -v plymouth-set-default-theme >/dev/null 2>&1; then
        chroot "$MOUNT_ROOT" plymouth-set-default-theme route19 || {
            log_warning "Failed to set Route 19 theme, falling back to spinner"
            chroot "$MOUNT_ROOT" plymouth-set-default-theme spinner || {
                log_warning "Failed to set any Plymouth theme - continuing without theme"
            }
        }
    else
        log_warning "plymouth-set-default-theme not available - Plymouth may not be properly installed"
        log_info "Boot splash will use default configuration"
    fi
    
    # Add Plymouth to initramfs features
    if [[ -f "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf" ]]; then
        # Add plymouth to features if not already present
        if ! grep -q "plymouth" "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf"; then
            sed -i 's/^features="\(.*\)"/features="\1 plymouth"/' "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf"
        fi
    fi
    
    # Rebuild initramfs to include Plymouth
    local kernel_version=$(chroot "$MOUNT_ROOT" ls /lib/modules/ | head -n1)
    if [[ -n "$kernel_version" ]]; then
        chroot "$MOUNT_ROOT" mkinitfs "$kernel_version" || {
            log_warning "Failed to rebuild initramfs with Plymouth"
        }
    fi
    
    log_success "Plymouth configured for boot splash"
}

# Optimize initramfs
optimize_initramfs() {
    log_info "Optimizing initramfs for fast boot..."
    
    # Configure mkinitfs for minimal initramfs
    cat > "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf" << 'EOF'
# KioskBook optimized initramfs configuration
features="ata base ext4 keymap kms mmc raid scsi usb virtio nvme plymouth"
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

# Configure watchdog
configure_watchdog() {
    log_info "Configuring hardware watchdog..."
    
    # Install watchdog daemon
    apk --root "$MOUNT_ROOT" add watchdog || {
        log_warning "Failed to install watchdog package"
        return 1
    }
    
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

# Install and configure GRUB
install_grub() {
    log_info "Installing and configuring GRUB bootloader..."
    
    # Set up chroot environment for GRUB installation
    log_info "Setting up chroot environment for GRUB..."
    mount --bind /dev "$MOUNT_ROOT/dev" 2>/dev/null || log_warning "Failed to bind mount /dev"
    mount --bind /proc "$MOUNT_ROOT/proc" 2>/dev/null || log_warning "Failed to bind mount /proc" 
    mount --bind /sys "$MOUNT_ROOT/sys" 2>/dev/null || log_warning "Failed to bind mount /sys"
    
    # Determine if system is EFI or BIOS
    local boot_mode="bios"
    if [[ -d "/sys/firmware/efi" ]]; then
        boot_mode="efi"
        log_info "Detected EFI boot mode"
    else
        log_info "Detected BIOS boot mode"
    fi
    
    # Copy optimized GRUB configuration
    local grub_config_source="$CONFIG_DIR/grub.cfg"
    if [[ -f "$grub_config_source" ]]; then
        mkdir -p "$MOUNT_BOOT/grub"
        cp "$grub_config_source" "$MOUNT_BOOT/grub/grub.cfg.template" || {
            log_warning "Failed to copy GRUB template - using generated config"
        }
    fi
    
    # Get partition UUIDs
    local root_uuid boot_uuid
    root_uuid="$(blkid -s UUID -o value "$ROOT_PARTITION")"
    boot_uuid="$(blkid -s UUID -o value "$BOOT_PARTITION")"
    
    # Install GRUB
    if [[ "$boot_mode" == "efi" ]]; then
        # EFI installation
        mkdir -p "$MOUNT_ROOT/boot/efi"
        if ! mountpoint -q "$MOUNT_ROOT/boot/efi"; then
            # Mount EFI system partition if not already mounted
            local esp_part="${TARGET_DISK}1"  # Assuming first partition is ESP
            mount "$esp_part" "$MOUNT_ROOT/boot/efi" 2>/dev/null || {
                log_warning "Could not mount EFI system partition"
            }
        fi
        
        if chroot "$MOUNT_ROOT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=KioskBook --recheck; then
            log_success "GRUB EFI installed successfully"
        else
            log_warning "EFI installation failed, falling back to BIOS mode"
            chroot "$MOUNT_ROOT" grub-install --target=i386-pc --recheck "$TARGET_DISK" || {
                log_error "Failed to install GRUB in both EFI and BIOS modes"
                exit 1
            }
        fi
    else
        # BIOS installation
        chroot "$MOUNT_ROOT" grub-install --target=i386-pc --recheck "$TARGET_DISK" || {
            log_error "Failed to install GRUB BIOS"
            exit 1
        }
    fi
    
    # Generate GRUB configuration
    chroot "$MOUNT_ROOT" grub-mkconfig -o /boot/grub/grub.cfg || {
        log_error "Failed to generate GRUB configuration"
        exit 1
    }
    
    # Apply optimizations to generated config
    if [[ -f "$MOUNT_ROOT/boot/grub/grub.cfg" ]]; then
        # Replace UUID placeholders
        sed -i "s/ROOT_UUID/$root_uuid/g" "$MOUNT_ROOT/boot/grub/grub.cfg"
        sed -i "s/BOOT_UUID/$boot_uuid/g" "$MOUNT_ROOT/boot/grub/grub.cfg"
    fi
    
    # Clean up chroot bind mounts
    log_info "Cleaning up chroot environment..."
    umount "$MOUNT_ROOT/sys" 2>/dev/null || true
    umount "$MOUNT_ROOT/proc" 2>/dev/null || true 
    umount "$MOUNT_ROOT/dev" 2>/dev/null || true
    
    log_success "GRUB installed and configured"
}

# Generate optimized initramfs
generate_initramfs() {
    log_info "Generating optimized initramfs..."
    
    # Generate initramfs with optimizations
    chroot "$MOUNT_ROOT" mkinitfs -o /boot/initrd "$(ls $MOUNT_ROOT/lib/modules | head -1)" || {
        log_error "Failed to generate initramfs"
        exit 1
    }
    
    log_success "Initramfs generated"
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
        "$MOUNT_ROOT/boot/grub/grub.cfg"
        "$MOUNT_ROOT/boot/initrd"
        "$MOUNT_ROOT/etc/mkinitfs/mkinitfs.conf"
        "$MOUNT_ROOT/etc/default/grub"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Essential boot file missing: $file"
            exit 1
        fi
    done
    
    # Check if GRUB is installed
    if [[ ! -d "$MOUNT_ROOT/boot/grub" ]]; then
        log_error "GRUB not properly installed"
        exit 1
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
    install_grub
    generate_initramfs
    configure_fast_boot
    validate_boot_config
    
    log_success "Boot optimization completed successfully"
    log_info "Target: Sub-5 second boot to Chromium display"
    log_info "Optimizations applied:"
    log_info "  - GRUB 0-timeout silent boot"
    log_info "  - AMD GPU kernel parameters"
    log_info "  - Plymouth boot splash"
    log_info "  - Optimized initramfs"
    log_info "  - Service startup optimization"
    log_info "  - Hardware watchdog configuration"
}

# Execute main function
main "$@"