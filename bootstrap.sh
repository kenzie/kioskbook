#!/bin/ash
#
# KioskBook Alpine Bootstrap - Part 1
# 
# Installs minimal Alpine Linux base system with kernel and bootloader.
# Run this from Alpine Live USB, then run setup.sh after reboot.
#
# Usage: ash bootstrap.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TARGET_DISK="/dev/sda"
HOSTNAME="kioskbook"

# Logging
log() { printf "${CYAN}[BOOTSTRAP]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "     KioskBook Alpine Linux Bootstrap - Part 1"
    echo "═══════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [ "$(id -u)" != "0" ]; then
        error_exit "This script must be run as root"
    fi
    
    # Check network
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_warning "No network detected, setting up..."
        setup-interfaces -a
        rc-service networking restart
        sleep 2
        if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            error_exit "Network setup failed. Please configure manually."
        fi
    fi
    
    # Configure APK repositories first (moved from install_system)
    log "Configuring Alpine repositories..."
    
    # Detect Alpine version
    local alpine_version
    if [ -f /etc/alpine-release ]; then
        alpine_version="v$(cat /etc/alpine-release | cut -d. -f1,2)"
        log "Detected Alpine version: $alpine_version"
    else
        alpine_version="v3.22"
        log_warning "Could not detect Alpine version, using $alpine_version"
    fi
    
    # Configure repositories for the live system
    cat > /etc/apk/repositories << EOF
http://dl-cdn.alpinelinux.org/alpine/${alpine_version}/main
http://dl-cdn.alpinelinux.org/alpine/${alpine_version}/community
EOF
    
    # Update package index
    apk update || log_warning "Failed to update package index"
    
    # Check for required tools (most should be available in Alpine Live)
    log "Checking for required tools..."
    
    # Only install tools that are missing
    missing_tools=""
    
    if ! command -v setup-alpine >/dev/null; then
        missing_tools="$missing_tools alpine-conf"
    fi
    
    if ! command -v parted >/dev/null; then
        missing_tools="$missing_tools parted"
    fi
    
    if ! command -v mkfs.ext4 >/dev/null; then
        missing_tools="$missing_tools e2fsprogs"
    fi
    
    if [ -n "$missing_tools" ]; then
        log "Installing missing tools:$missing_tools"
        # Now we can install tools since repositories are configured
        apk add $missing_tools || log_warning "Some tools may be missing (continuing anyway)"
    else
        log_success "All required tools already available"
    fi
    
    log_success "Prerequisites checked"
}

# Prepare disk
prepare_disk() {
    log "Preparing disk $TARGET_DISK..."
    
    # Check if disk exists
    if [ ! -b "$TARGET_DISK" ]; then
        error_exit "Disk $TARGET_DISK not found"
    fi
    
    # Unmount any existing partitions
    log "Unmounting any existing partitions..."
    for partition in ${TARGET_DISK}*; do
        if [ -b "$partition" ] && mount | grep -q "$partition"; then
            umount -f "$partition" 2>/dev/null || true
        fi
    done
    
    # Confirm disk wipe
    echo -e "\n${YELLOW}WARNING: This will ERASE ALL DATA on $TARGET_DISK${NC}"
    echo -n "Continue? [y/N]: "
    read CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        error_exit "Aborted by user"
    fi
    
    log_success "Disk prepared"
}

# Install Alpine system
install_system() {
    log "Installing Alpine Linux to $TARGET_DISK..."
    
    # Run setup steps individually for better control
    log "Configuring system settings..."
    
    # Keyboard layout
    setup-keymap us us
    
    # Hostname
    setup-hostname -n $HOSTNAME
    
    # Networking (already done in prerequisites, but ensure it's set)
    cat > /etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Timezone (skip tzdata package issues, set manually later)
    echo "UTC" > /etc/timezone || log_warning "Timezone setup skipped"
    
    # Install and enable SSH (repositories are now configured)
    log "Installing and configuring SSH..."
    if apk add openssh; then
        rc-update add sshd default || log_warning "Failed to enable SSH service"
        log_success "SSH configured"
    else
        log_warning "SSH installation failed"
    fi
    
    # Set root password
    log "Setting root password..."
    echo "Please set the root password:"
    passwd
    
    # Now install to disk using setup-disk directly
    log "Installing Alpine to disk..."
    
    # Try setup-disk with verbose output
    log "Running: setup-disk -m sys -L $TARGET_DISK"
    if setup-disk -m sys -L $TARGET_DISK; then
        log_success "Disk installation completed"
    else
        log_warning "setup-disk failed, trying manual approach..."
        
        # Manual disk setup as fallback
        log "Attempting manual disk installation..."
        
        # Create filesystem if not already done
        if ! mount | grep -q "$TARGET_DISK"; then
            mkfs.ext4 -F ${TARGET_DISK}1 || error_exit "Failed to format disk"
        fi
        
        # Mount target
        mkdir -p /mnt/disk
        mount ${TARGET_DISK}1 /mnt/disk || error_exit "Failed to mount target disk"
        
        # Copy system files
        cp -a /etc /mnt/disk/ || error_exit "Failed to copy /etc"
        mkdir -p /mnt/disk/{root,home,var,tmp,usr,opt,srv}
        
        # Install base packages to target
        mkdir -p /mnt/disk/etc/apk
        cp /etc/apk/repositories /mnt/disk/etc/apk/
        
        # Install essential packages to the target system
        log "Installing essential packages to target system..."
        
        # Initialize APK database in target
        mkdir -p /mnt/disk/var/cache/apk
        apk add --root /mnt/disk --initdb \
            alpine-base \
            bash \
            busybox \
            busybox-initscripts \
            openrc \
            alpine-conf \
            git \
            curl \
            wget \
            htop \
            nano \
            util-linux \
            coreutils \
            shadow \
            sudo \
            pciutils \
            usbutils \
            e2fsprogs \
            openssh \
            linux-lts \
            linux-firmware-none \
            2>/dev/null || log_warning "Some packages failed to install"
        
        # Basic bootloader setup
        mkdir -p /mnt/disk/boot
        extlinux --install /mnt/disk/boot || error_exit "Failed to install bootloader"
        
        # Create basic boot config
        cat > /mnt/disk/boot/extlinux.conf << EOF
DEFAULT kioskbook
PROMPT 0
TIMEOUT 10

LABEL kioskbook
    LINUX vmlinuz
    INITRD initramfs
    APPEND root=${TARGET_DISK}1 rw modules=sd-mod,usb-storage,ext4 quiet
EOF
        
        # Copy kernel if available
        if [ -f /boot/vmlinuz* ]; then
            cp /boot/vmlinuz* /mnt/disk/boot/vmlinuz || log_warning "Kernel copy failed"
        fi
        if [ -f /boot/initramfs* ]; then
            cp /boot/initramfs* /mnt/disk/boot/initramfs || log_warning "Initramfs copy failed"
        fi
        
        # Install MBR
        dd if=/usr/share/syslinux/mbr.bin of=$TARGET_DISK bs=440 count=1 2>/dev/null || log_warning "MBR install failed"
        
        umount /mnt/disk
        log_success "Manual disk installation completed"
    fi
    
    log_success "Alpine system installed"
}

# Post-install configuration
post_install() {
    log "Configuring installed system..."
    
    # Mount the installed system
    mkdir -p /mnt/target
    mount ${TARGET_DISK}1 /mnt/target 2>/dev/null || mount ${TARGET_DISK}2 /mnt/target
    
    # Configure networking for installed system
    log "Setting up networking in installed system..."
    cat > /mnt/target/etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Ensure networking service is enabled
    mkdir -p /mnt/target/etc/runlevels/boot
    ln -sf /etc/init.d/networking /mnt/target/etc/runlevels/boot/networking 2>/dev/null || true
    
    # Copy DNS settings from live system
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /mnt/target/etc/ || log_warning "Failed to copy DNS settings"
    fi
    
    # Configure proper APK repositories for Alpine 3.22
    log "Configuring APK repositories for installed system..."
    mkdir -p /mnt/target/etc/apk
    
    # Detect actual Alpine version and configure correct repositories
    local alpine_version
    if [ -f /etc/alpine-release ]; then
        alpine_version="v$(cat /etc/alpine-release | cut -d. -f1,2)"
        log "Detected Alpine version: $alpine_version"
    else
        alpine_version="v3.22"
        log_warning "Could not detect Alpine version, using $alpine_version"
    fi
    
    # Write correct repositories for the detected version
    cat > /mnt/target/etc/apk/repositories << EOF
http://dl-cdn.alpinelinux.org/alpine/${alpine_version}/main
http://dl-cdn.alpinelinux.org/alpine/${alpine_version}/community
@edge http://dl-cdn.alpinelinux.org/alpine/edge/main
@testing http://dl-cdn.alpinelinux.org/alpine/edge/testing
EOF
    
    log_success "APK repositories configured for Alpine ${alpine_version}"
    
    # Download setup.sh directly to the installed system
    log "Downloading setup.sh to installed system..."
    if command -v wget >/dev/null; then
        wget -q -O /mnt/target/root/setup.sh https://raw.githubusercontent.com/kenzie/kioskbook/main/setup.sh || log_warning "Failed to download setup.sh"
        chmod +x /mnt/target/root/setup.sh 2>/dev/null || true
    elif [ -f "setup.sh" ]; then
        cp setup.sh /mnt/target/root/
        chmod +x /mnt/target/root/setup.sh
        log_success "Copied local setup.sh to /root/"
    else
        log_warning "setup.sh not available - will need to download manually after boot"
    fi
    
    # Create setup marker
    touch /mnt/target/root/.needs_kiosk_setup
    
    # Create a simple network test script
    cat > /mnt/target/root/test-network.sh << 'EOF'
#!/bin/sh
echo "Testing network connectivity..."
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "✓ Network is working"
    echo "✓ You can run: ./setup.sh"
else
    echo "✗ Network not working, trying to restart..."
    /etc/init.d/networking restart
    sleep 2
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "✓ Network is now working"
        echo "✓ You can run: ./setup.sh"
    else
        echo "✗ Network still not working"
        echo "Try: /etc/init.d/networking restart"
    fi
fi
EOF
    chmod +x /mnt/target/root/test-network.sh
    
    # Ensure kernel parameters for quiet boot
    if [ -f /mnt/target/etc/update-extlinux.conf ]; then
        sed -i 's/^default_kernel_opts=.*/default_kernel_opts="quiet"/' /mnt/target/etc/update-extlinux.conf
        
        # Add root device to suppress warning
        if ! grep -q "^root=" /mnt/target/etc/update-extlinux.conf; then
            echo "root=$TARGET_DISK" >> /mnt/target/etc/update-extlinux.conf
        fi
        
        # Update bootloader config (warning is expected and harmless)
        chroot /mnt/target update-extlinux || log_warning "Bootloader config updated with warnings (normal)"
    fi
    
    # Unmount
    umount /mnt/target
    
    log_success "Post-install configuration complete"
}

# Show completion
show_completion() {
    echo -e "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     Bootstrap Complete - Base System Installed!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${CYAN}Next Steps:${NC}"
    echo -e "1. Remove USB and reboot: ${YELLOW}reboot${NC}"
    echo -e "2. Login as root with the password you set"
    echo -e "3. Run: ${YELLOW}./setup.sh${NC} to complete kiosk installation"
    
    echo -e "\n${CYAN}The system now has:${NC}"
    echo -e "  ✓ Alpine Linux base system"
    echo -e "  ✓ Linux kernel and drivers"
    echo -e "  ✓ Bootloader configured"
    echo -e "  ✓ Basic networking"
    echo -e "  ✓ Root access configured"
}

# Main execution
main() {
    show_banner
    check_prerequisites
    prepare_disk
    install_system
    post_install
    show_completion
}

# Run
main "$@"