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
MOUNT_ROOT="/mnt"
HOSTNAME="kioskbook"

# Logging
log() { printf "${CYAN}[BOOTSTRAP]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

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
        log_error "This script must be run as root"
    fi
    
    # Check if running from live environment
    if [ -d "/mnt/sda1" ]; then
        log_error "System appears to be already installed. Run from Alpine Live USB."
    fi
    
    # Check network
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_warning "No network detected, setting up..."
        setup-interfaces -a
        rc-service networking restart
        sleep 2
        if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log_error "Network setup failed. Please configure manually."
        fi
    fi
    
    log_success "Prerequisites checked"
}

# Partition disk
partition_disk() {
    log "Partitioning disk $TARGET_DISK..."
    
    # Check if disk exists
    if [ ! -b "$TARGET_DISK" ]; then
        log_error "Disk $TARGET_DISK not found"
    fi
    
    # Confirm disk wipe
    echo -e "\n${YELLOW}WARNING: This will ERASE ALL DATA on $TARGET_DISK${NC}"
    echo -n "Continue? [y/N]: "
    read CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        log_error "Aborted by user"
    fi
    
    # Wipe and partition
    log "Creating partition table..."
    wipefs -af $TARGET_DISK
    parted -s $TARGET_DISK mklabel msdos
    parted -s $TARGET_DISK mkpart primary ext4 1MiB 100%
    parted -s $TARGET_DISK set 1 boot on
    
    # Format
    log "Formatting partition..."
    mkfs.ext4 -F ${TARGET_DISK}1
    
    log_success "Disk partitioned and formatted"
}

# Install base system
install_base() {
    log "Installing Alpine base system..."
    
    # Mount target
    mount ${TARGET_DISK}1 $MOUNT_ROOT
    
    # Configure repositories for correct Alpine version
    local alpine_version
    if [ -f "/etc/alpine-release" ]; then
        alpine_version="v$(cat /etc/alpine-release | cut -d. -f1,2)"
    else
        alpine_version="v3.22"
    fi
    
    cat > /etc/apk/repositories << EOF
http://dl-cdn.alpinelinux.org/alpine/${alpine_version}/main
http://dl-cdn.alpinelinux.org/alpine/${alpine_version}/community
EOF
    
    # Update package index
    apk update
    
    # Install base packages
    apk add --root $MOUNT_ROOT --initdb alpine-base
    
    # Copy repositories config
    cp /etc/apk/repositories $MOUNT_ROOT/etc/apk/
    
    log_success "Base system installed"
}

# Install kernel and bootloader
install_kernel() {
    log "Installing kernel and bootloader..."
    
    # Mount necessary filesystems
    mount --bind /dev $MOUNT_ROOT/dev
    mount --bind /proc $MOUNT_ROOT/proc
    mount --bind /sys $MOUNT_ROOT/sys
    
    # Install kernel (linux-lts for hardware, linux-virt for VM)
    chroot $MOUNT_ROOT apk add linux-lts linux-firmware-none mkinitfs
    
    # Install bootloader
    chroot $MOUNT_ROOT apk add syslinux
    
    # Configure bootloader
    cat > $MOUNT_ROOT/boot/extlinux.conf << EOF
DEFAULT kioskbook
PROMPT 0
TIMEOUT 10

LABEL kioskbook
    LINUX vmlinuz-lts
    INITRD initramfs-lts
    APPEND root=${TARGET_DISK}1 rw modules=sd-mod,usb-storage,ext4 quiet
EOF
    
    # Install bootloader to disk
    extlinux --install $MOUNT_ROOT/boot
    dd if=/usr/share/syslinux/mbr.bin of=$TARGET_DISK bs=440 count=1
    
    # Generate initramfs
    chroot $MOUNT_ROOT mkinitfs -F "ata base ide scsi usb virtio ext4" $(ls $MOUNT_ROOT/lib/modules/)
    
    log_success "Kernel and bootloader installed"
}

# Configure base system
configure_base() {
    log "Configuring base system..."
    
    # Set hostname
    echo "$HOSTNAME" > $MOUNT_ROOT/etc/hostname
    
    # Configure networking
    cat > $MOUNT_ROOT/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Enable essential services
    chroot $MOUNT_ROOT rc-update add networking boot
    chroot $MOUNT_ROOT rc-update add urandom boot
    chroot $MOUNT_ROOT rc-update add bootmisc boot
    chroot $MOUNT_ROOT rc-update add hostname boot
    chroot $MOUNT_ROOT rc-update add syslog boot
    chroot $MOUNT_ROOT rc-update add klogd boot
    
    # Set root password
    log "Setting root password..."
    echo -e "\n${CYAN}Enter root password:${NC}"
    chroot $MOUNT_ROOT passwd
    
    # Create setup script marker
    touch $MOUNT_ROOT/root/.needs_kiosk_setup
    
    # Copy setup.sh if it exists
    if [ -f "setup.sh" ]; then
        cp setup.sh $MOUNT_ROOT/root/
        chmod +x $MOUNT_ROOT/root/setup.sh
        log_success "Copied setup.sh to /root/"
    fi
    
    log_success "Base system configured"
}

# Cleanup
cleanup() {
    log "Cleaning up..."
    
    # Unmount filesystems
    umount $MOUNT_ROOT/dev 2>/dev/null || true
    umount $MOUNT_ROOT/proc 2>/dev/null || true
    umount $MOUNT_ROOT/sys 2>/dev/null || true
    umount $MOUNT_ROOT 2>/dev/null || true
    
    log_success "Cleanup complete"
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
    echo -e "  ✓ EXTLINUX bootloader"
    echo -e "  ✓ Basic networking"
    echo -e "  ✓ Root access configured"
}

# Main execution
main() {
    show_banner
    check_prerequisites
    partition_disk
    install_base
    install_kernel
    configure_base
    cleanup
    show_completion
}

# Run
main "$@"