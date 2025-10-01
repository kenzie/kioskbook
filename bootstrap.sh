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
        # Try to install just the missing tools, ignore firmware bloat errors
        apk add $missing_tools 2>/dev/null || log_warning "Some tools may be missing (continuing anyway)"
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
    
    # Timezone
    setup-timezone -z UTC
    
    # SSH
    rc-update add sshd default
    rc-service sshd start
    
    # Set root password
    log "Setting root password..."
    echo "Please set the root password:"
    passwd
    
    # Now install to disk using setup-disk directly
    log "Installing Alpine to disk..."
    if ! setup-disk -m sys -L $TARGET_DISK; then
        error_exit "Disk installation failed"
    fi
    
    log_success "Alpine system installed"
}

# Post-install configuration
post_install() {
    log "Configuring installed system..."
    
    # Mount the installed system
    mkdir -p /mnt/target
    mount ${TARGET_DISK}1 /mnt/target 2>/dev/null || mount ${TARGET_DISK}2 /mnt/target
    
    # Copy setup.sh if it exists
    if [ -f "setup.sh" ]; then
        cp setup.sh /mnt/target/root/
        chmod +x /mnt/target/root/setup.sh
        log_success "Copied setup.sh to /root/"
    else
        log_warning "setup.sh not found in current directory"
    fi
    
    # Create setup marker
    touch /mnt/target/root/.needs_kiosk_setup
    
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