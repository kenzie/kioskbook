#!/bin/bash
#
# 10-base-system.sh - Base System Setup Module
#
# Installs and configures the core Alpine Linux system components
# required for kiosk operation with read-only root filesystem.
#
# Features:
# - Alpine base system installation
# - Read-only root with tmpfs overlays
# - Kiosk user with autologin
# - Essential packages for X11 and Node.js
# - Optimized for fast boot
#

set -e
set -o pipefail

# Import logging functions from main installer
source /dev/stdin <<< "$(declare -f log log_success log_warning log_error log_info add_rollback)"

# Module configuration
MODULE_NAME="10-base-system"
ALPINE_MIRROR="http://dl-cdn.alpinelinux.org/alpine"
ALPINE_VERSION="latest-stable"

# Essential packages for kiosk operation (without kernel to avoid firmware bloat)
BASE_PACKAGES=(
    "alpine-base"
    "alpine-conf"
    "busybox"
    "openrc"
    "util-linux"
    "coreutils"
    "procps"
    "shadow"
    "sudo"
    "doas"
    "openssh"
    "chrony"
    "logrotate"
)

# Core kiosk functionality (install individually to catch specific failures)
KIOSK_CORE=(
    "nodejs"
    "npm"
    "chromium"
    "xorg-server"
    "eudev"
    "dbus"
)

log_info "Starting base system setup module..."

# Validate environment
validate_environment() {
    if [[ -z "$MOUNT_ROOT" || -z "$MOUNT_BOOT" || -z "$ROOT_PARTITION" || -z "$BOOT_PARTITION" ]]; then
        log_error "Required mount points not set. Run partition module first."
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_ROOT"; then
        log_error "Root partition not mounted at $MOUNT_ROOT"
        exit 1
    fi
    
    log_info "Environment validation passed"
}

# Set up package repositories
setup_repositories() {
    log_info "Setting up Alpine package repositories..."
    
    local repo_file="$MOUNT_ROOT/etc/apk/repositories"
    mkdir -p "$(dirname "$repo_file")"
    
    # Use the same version as the host system
    local alpine_version
    if [[ -f /etc/alpine-release ]]; then
        alpine_version="v$(cat /etc/alpine-release | cut -d. -f1,2)"
        log_info "Detected Alpine version: $alpine_version"
    else
        alpine_version="v3.22"
        log_warning "Could not detect Alpine version, using $alpine_version"
    fi
    
    cat > "$repo_file" << EOF
$ALPINE_MIRROR/${alpine_version}/main
$ALPINE_MIRROR/${alpine_version}/community
EOF
    
    log_success "Repository configuration created"
}

# Initialize apk database in chroot
initialize_apk() {
    log_info "Initializing Alpine package database..."
    
    # Copy current apk keys to target
    mkdir -p "$MOUNT_ROOT/etc/apk/keys"
    cp -r /etc/apk/keys/* "$MOUNT_ROOT/etc/apk/keys/" 2>/dev/null || {
        log_warning "Failed to copy apk keys, updating from network..."
    }
    
    # Initialize apk database
    apk --root "$MOUNT_ROOT" --initdb add || {
        log_error "Failed to initialize apk database"
        exit 1
    }
    
    # Update package index
    apk --root "$MOUNT_ROOT" update || {
        log_error "Failed to update package index"
        exit 1
    }
    
    log_success "APK database initialized"
}

# Install base system packages
install_base_packages() {
    log_info "Installing Alpine base system packages..."
    
    # Install base packages
    log_info "Installing base packages..."
    apk --root "$MOUNT_ROOT" add "${BASE_PACKAGES[@]}" || {
        log_error "Failed to install base packages"
        exit 1
    }
    
    log_success "Base packages installed"
}

# Install core kiosk packages individually to identify failures
install_kiosk_packages() {
    log_info "Installing core kiosk packages individually..."
    
    # Install each package individually to catch specific failures
    for pkg in "${KIOSK_CORE[@]}"; do
        log_info "Installing $pkg..."
        
        # Capture both output and exit code
        local output
        local exit_code
        output=$(apk --root "$MOUNT_ROOT" add "$pkg" 2>&1)
        exit_code=$?
        
        echo "$output"  # Show the apk output
        
        if [[ $exit_code -eq 0 ]]; then
            log_success "$pkg installed successfully"
        else
            log_error "Failed to install $pkg (exit code: $exit_code)"
            log_error "APK output: $output"
            exit 1
        fi
    done
    
    log_success "All core kiosk packages installed successfully"
}

# Configure hostname
configure_hostname() {
    log_info "Configuring hostname..."
    
    echo "$HOSTNAME" > "$MOUNT_ROOT/etc/hostname" || {
        log_error "Failed to set hostname"
        exit 1
    }
    
    # Configure hosts file
    cat > "$MOUNT_ROOT/etc/hosts" << EOF
127.0.0.1   localhost localhost.localdomain
127.0.1.1   $HOSTNAME $HOSTNAME.localdomain
::1         localhost ipv6-localhost ipv6-loopback
ff02::1     ipv6-allnodes
ff02::2     ipv6-allrouters
EOF
    
    log_success "Hostname configured as $HOSTNAME"
}

# Set timezone
configure_timezone() {
    log_info "Configuring timezone..."
    
    # Install timezone data
    apk --root "$MOUNT_ROOT" add tzdata || {
        log_error "Failed to install timezone data"
        exit 1
    }
    
    # Set timezone
    chroot "$MOUNT_ROOT" ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || {
        log_error "Failed to set timezone"
        exit 1
    }
    
    echo "$TIMEZONE" > "$MOUNT_ROOT/etc/timezone" || {
        log_error "Failed to write timezone file"
        exit 1
    }
    
    log_success "Timezone set to $TIMEZONE"
}

# Create kiosk user
create_kiosk_user() {
    log_info "Creating kiosk user..."
    
    # Check if kiosk user already exists
    if chroot "$MOUNT_ROOT" id kiosk >/dev/null 2>&1; then
        log_info "Kiosk user already exists, attempting thorough cleanup..."
        
        # Kill any processes owned by kiosk user
        chroot "$MOUNT_ROOT" pkill -u kiosk 2>/dev/null || true
        
        # Remove user from all groups first
        chroot "$MOUNT_ROOT" deluser kiosk users 2>/dev/null || true
        chroot "$MOUNT_ROOT" deluser kiosk audio 2>/dev/null || true
        chroot "$MOUNT_ROOT" deluser kiosk video 2>/dev/null || true
        chroot "$MOUNT_ROOT" deluser kiosk input 2>/dev/null || true
        chroot "$MOUNT_ROOT" deluser kiosk netdev 2>/dev/null || true
        
        # Remove user and home directory
        chroot "$MOUNT_ROOT" deluser kiosk 2>/dev/null || true
        chroot "$MOUNT_ROOT" delgroup kiosk 2>/dev/null || true
        
        # Force remove home directory and any locks
        rm -rf "$MOUNT_ROOT/home/kiosk" 2>/dev/null || true
        rm -f "$MOUNT_ROOT/etc/passwd.lock" "$MOUNT_ROOT/etc/shadow.lock" "$MOUNT_ROOT/etc/group.lock" 2>/dev/null || true
        
        # Wait a moment for system cleanup
        sleep 1
        
        # Verify user is gone
        if chroot "$MOUNT_ROOT" id kiosk >/dev/null 2>&1; then
            log_error "Failed to remove existing kiosk user completely"
            log_info "Manual cleanup required. Current user info:"
            chroot "$MOUNT_ROOT" id kiosk || true
            chroot "$MOUNT_ROOT" grep kiosk /etc/passwd || true
            exit 1
        fi
        
        log_info "Existing kiosk user removed successfully"
    fi
    
    # Create kiosk user with home directory (Alpine Linux syntax)
    chroot "$MOUNT_ROOT" adduser -D -s /bin/ash -h /home/kiosk kiosk || {
        log_error "Failed to create kiosk user"
        log_info "Debugging user creation issue..."
        chroot "$MOUNT_ROOT" id kiosk 2>/dev/null || log_info "No existing kiosk user found"
        chroot "$MOUNT_ROOT" ls -la /home/ 2>/dev/null || log_info "Cannot list /home directory"
        exit 1
    }
    log_success "Kiosk user created successfully"
    
    # Set password for kiosk user (disabled by default with -D)
    chroot "$MOUNT_ROOT" passwd -d kiosk || {
        log_warning "Failed to disable password for kiosk user"
    }
    
    # Add kiosk user to necessary groups (use adduser for group membership)
    chroot "$MOUNT_ROOT" adduser kiosk users || true
    chroot "$MOUNT_ROOT" adduser kiosk audio || true
    chroot "$MOUNT_ROOT" adduser kiosk video || true
    chroot "$MOUNT_ROOT" adduser kiosk input || true
    chroot "$MOUNT_ROOT" adduser kiosk netdev || true
    
    # Set up autologin for kiosk user on tty1
    mkdir -p "$MOUNT_ROOT/etc/conf.d"
    cat > "$MOUNT_ROOT/etc/conf.d/agetty.tty1" << EOF
# Autologin configuration for tty1
agetty_options="--autologin kiosk --noclear"
EOF
    
    # Create kiosk user profile
    mkdir -p "$MOUNT_ROOT/home/kiosk"
    cat > "$MOUNT_ROOT/home/kiosk/.profile" << 'EOF'
# Kiosk user profile
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export DISPLAY=:0

# Start X11 automatically on tty1
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$DISPLAY" ]; then
    exec startx
fi
EOF
    
    # Set ownership
    chroot "$MOUNT_ROOT" chown -R kiosk:kiosk /home/kiosk
    
    log_success "Kiosk user created with autologin"
}

# Configure read-only root filesystem
configure_readonly_root() {
    log_info "Configuring read-only root filesystem..."
    
    # Create fstab with read-only root and tmpfs overlays
    cat > "$MOUNT_ROOT/etc/fstab" << EOF
# KioskBook filesystem table
# <device>      <mountpoint>    <type>  <options>                           <dump> <pass>

# Root filesystem (read-only)
UUID=$(blkid -s UUID -o value "$ROOT_PARTITION")  /              ext4    ro,noatime,errors=remount-ro           0      1

# Boot filesystem
UUID=$(blkid -s UUID -o value "$BOOT_PARTITION")  /boot          ext4    rw,noatime,errors=remount-ro           0      2

# Data filesystem
UUID=$(blkid -s UUID -o value "$DATA_PARTITION")  /data          ext4    rw,noatime,errors=remount-ro           0      2

# Temporary filesystems (tmpfs overlays)
tmpfs                                              /tmp           tmpfs   defaults,nodev,nosuid,size=100M        0      0
tmpfs                                              /var/tmp       tmpfs   defaults,nodev,nosuid,size=50M         0      0
tmpfs                                              /var/log       tmpfs   defaults,nodev,nosuid,size=50M         0      0
tmpfs                                              /var/run       tmpfs   defaults,nodev,nosuid,size=10M         0      0
tmpfs                                              /var/lock      tmpfs   defaults,nodev,nosuid,size=5M          0      0

# Persistent directories on data partition
/data/var/cache                                    /var/cache     none    bind,rw                                0      0
/data/var/lib                                      /var/lib       none    bind,rw                                0      0
/data/home                                         /home          none    bind,rw                                0      0
/data/opt                                          /opt           none    bind,rw                                0      0
EOF
    
    # Create persistent directories on data partition
    mkdir -p "$MOUNT_DATA"/{var/cache,var/lib,home,opt}
    
    # Move kiosk home to data partition
    if [[ -d "$MOUNT_ROOT/home/kiosk" ]]; then
        # Ensure target directory exists
        mkdir -p "$MOUNT_DATA/home/kiosk"
        
        # Copy all files including hidden files (like .profile)
        cp -r "$MOUNT_ROOT/home/kiosk/." "$MOUNT_DATA/home/kiosk/" || {
            log_error "Failed to copy kiosk home directory to data partition"
            exit 1
        }
        
        # Verify .profile was copied
        if [[ ! -f "$MOUNT_DATA/home/kiosk/.profile" ]]; then
            log_error "Critical: .profile not copied to data partition"
            exit 1
        fi
        
        rm -rf "$MOUNT_ROOT/home/kiosk"
        log_success "Kiosk home directory moved to data partition"
    fi
    
    # Create necessary tmpfs directories
    mkdir -p "$MOUNT_ROOT"/{tmp,var/tmp,var/log,var/run,var/lock}
    
    log_success "Read-only root filesystem configured"
}

# Configure OpenRC for fast boot
configure_openrc() {
    log_info "Configuring OpenRC for fast boot..."
    
    # Configure OpenRC settings for fast boot
    cat > "$MOUNT_ROOT/etc/rc.conf" << EOF
# OpenRC configuration for fast boot
rc_parallel="YES"
rc_interactive="NO"
rc_logger="YES"
rc_log_path="/var/log/rc.log"
rc_depend_strict="NO"
rc_hotplug="edev"
rc_shell="/sbin/sulogin"
unicode="YES"
EOF
    
    # Enable essential services
    local services=(
        "devfs:sysinit"
        "dmesg:sysinit"
        "mdev:sysinit"
        "hwdrivers:boot"
        "hwclock:boot"
        "modules:boot"
        "sysctl:boot"
        "hostname:boot"
        "bootmisc:boot"
        "syslog:boot"
        "mount-ro:shutdown"
        "killprocs:shutdown"
        "savecache:shutdown"
    )
    
    for service in "${services[@]}"; do
        local service_name="${service%:*}"
        local runlevel="${service#*:}"
        
        chroot "$MOUNT_ROOT" rc-update add "$service_name" "$runlevel" 2>/dev/null || {
            log_warning "Failed to add service: $service_name to $runlevel"
        }
    done
    
    # Disable unnecessary services for faster boot
    local disable_services=(
        "acpid"
        "crond" 
        "networking"
    )
    
    for service in "${disable_services[@]}"; do
        chroot "$MOUNT_ROOT" rc-update del "$service" default 2>/dev/null || true
    done
    
    log_success "OpenRC configured for fast boot"
}

# Configure system settings
configure_system() {
    log_info "Configuring system settings..."
    
    # Configure shadow passwords (Alpine may not have pwconv)
    if chroot "$MOUNT_ROOT" command -v pwconv >/dev/null 2>&1; then
        chroot "$MOUNT_ROOT" pwconv || {
            log_warning "Failed to configure shadow passwords"
        }
    else
        log_info "pwconv not available in Alpine, shadow passwords handled by adduser"
    fi
    
    # Configure sudo/doas
    echo "permit nopass kiosk" > "$MOUNT_ROOT/etc/doas.conf"
    chmod 600 "$MOUNT_ROOT/etc/doas.conf"
    
    # Configure SSH
    mkdir -p "$MOUNT_ROOT/etc/ssh"
    cat > "$MOUNT_ROOT/etc/ssh/sshd_config" << 'EOF'
# KioskBook SSH configuration
Port 22
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
AllowUsers kiosk
EOF
    
    # Configure syslog
    cat > "$MOUNT_ROOT/etc/syslog.conf" << 'EOF'
# KioskBook syslog configuration
*.info;mail.none;authpriv.none;cron.none    /var/log/messages
authpriv.*                                  /var/log/secure
mail.*                                      /var/log/maillog
cron.*                                      /var/log/cron
*.emerg                                     *
uucp,news.crit                             /var/log/spooler
local7.*                                   /var/log/boot.log
EOF
    
    log_success "System settings configured"
}

# Configure bootloader preparation
prepare_bootloader() {
    log_info "Preparing bootloader configuration..."
    
    # EXTLINUX will be installed and configured by the boot optimization module
    # No preparation needed here - just ensure boot directory exists
    mkdir -p "$MOUNT_ROOT/boot"
    
    log_success "Bootloader preparation completed (EXTLINUX will be configured later)"
}

# Validate installation
validate_installation() {
    log_info "Validating base system installation..."
    
    # Check essential files
    local essential_files=(
        "$MOUNT_ROOT/etc/hostname"
        "$MOUNT_ROOT/etc/fstab"
        "$MOUNT_ROOT/etc/timezone"
        "$MOUNT_DATA/home/kiosk/.profile"
        "$MOUNT_ROOT/etc/rc.conf"
    )
    
    for file in "${essential_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Essential file missing: $file"
            exit 1
        fi
    done
    
    # Check user creation
    if ! chroot "$MOUNT_ROOT" id kiosk >/dev/null 2>&1; then
        log_error "Kiosk user not created properly"
        exit 1
    fi
    
    # Check package installation
    local check_packages=("nodejs" "chromium" "xorg-server")
    for pkg in "${check_packages[@]}"; do
        if ! chroot "$MOUNT_ROOT" apk info -e "$pkg" >/dev/null 2>&1; then
            log_error "Essential package not installed: $pkg"
            exit 1
        fi
    done
    
    log_success "Base system installation validation passed"
}

# Main base system setup
main() {
    log_info "=========================================="
    log_info "Module: Base System Setup"
    log_info "=========================================="
    
    validate_environment
    setup_repositories
    initialize_apk
    install_base_packages
    install_kiosk_packages
    configure_hostname
    configure_timezone
    create_kiosk_user
    configure_readonly_root
    configure_openrc
    configure_system
    prepare_bootloader
    validate_installation
    
    log_success "Base system setup completed successfully"
    log_info "Alpine Linux ready for kiosk configuration"
}

# Execute main function
main "$@"