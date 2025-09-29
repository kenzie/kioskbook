#!/bin/bash
#
# KioskBook Phase 1: Brutal Debian Installation
# 
# Establishes a clean, bootable Debian system on Lenovo M75q-1
# NVMe drive will be COMPLETELY ERASED
#
# Usage:
# 1. Boot from Debian netinst USB
# 2. Select "Advanced options > Rescue mode"
# 3. Drop to shell, run: bash install.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
HOSTNAME="kioskbook"
INSTALL_DISK="/dev/nvme0n1"
TIMEZONE="America/Halifax"

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║                                                       ║"
    echo "║              KIOSKBOOK PHASE 1                        ║"
    echo "║         Brutal Debian Installation                    ║"
    echo "║                                                       ║"
    echo "║    Lenovo M75q-1 | Debian 12 | NVMe Install          ║"
    echo "║                                                       ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_step() {
    echo -e "\n${BLUE}===${NC} ${CYAN}$1${NC} ${BLUE}===${NC}\n"
}

# Get user configuration
get_configuration() {
    log_step "Configuration"
    
    # GitHub repo for Vue.js application
    echo -n -e "${CYAN}Vue.js application git repository${NC}: "
    read GITHUB_REPO
    if [ -z "$GITHUB_REPO" ]; then
        log_error "GitHub repository is required"
    fi
    
    # Root password
    echo -n -e "${CYAN}Root password for SSH access${NC}: "
    read -s ROOT_PASSWORD
    echo
    echo -n -e "${CYAN}Confirm password${NC}: "
    read -s ROOT_PASSWORD_CONFIRM
    echo
    
    if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
        log_error "Passwords don't match"
    fi
    
    if [ ${#ROOT_PASSWORD} -lt 8 ]; then
        log_error "Password must be at least 8 characters"
    fi
}

# Show summary and get brutal confirmation
show_summary() {
    log_step "Installation Summary"
    
    echo -e "${CYAN}Hostname:${NC}         $HOSTNAME"
    echo -e "${CYAN}Target Disk:${NC}      $INSTALL_DISK"
    echo -e "${CYAN}Timezone:${NC}         $TIMEZONE"
    echo -e "${CYAN}Application:${NC}      $GITHUB_REPO"
    echo -e "${CYAN}SSH Access:${NC}       Enabled with root password"
    
    echo -e "\n${RED}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                       ║${NC}"
    echo -e "${RED}║  WARNING: ALL DATA ON $INSTALL_DISK WILL BE DESTROYED  ║${NC}"
    echo -e "${RED}║                                                       ║${NC}"
    echo -e "${RED}║  This action is IRREVERSIBLE and IMMEDIATE            ║${NC}"
    echo -e "${RED}║                                                       ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${YELLOW}To confirm, type exactly:${NC} ${RED}DESTROY${NC}"
    echo -n "> "
    read CONFIRM
    
    if [ "$CONFIRM" != "DESTROY" ]; then
        log_error "Installation cancelled - confirmation failed"
    fi
}

# Verify hardware
verify_hardware() {
    log_step "Hardware Verification"
    
    # Check if NVMe drive exists
    if [ ! -b "$INSTALL_DISK" ]; then
        log_error "NVMe drive $INSTALL_DISK not found!"
    fi
    
    DISK_SIZE=$(lsblk -dno SIZE $INSTALL_DISK)
    log_info "Found NVMe drive: $INSTALL_DISK ($DISK_SIZE)"
    
    # Check for AMD GPU
    if lspci | grep -i amd | grep -i vga >/dev/null 2>&1; then
        GPU_INFO=$(lspci | grep -i amd | grep -i vga | head -1)
        log_info "Detected AMD GPU: $GPU_INFO"
    fi
    
    # Check network
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No network connectivity - ethernet required"
    fi
    log_info "Network connectivity verified"
}

# Brutally wipe and partition disk
partition_disk() {
    log_step "Disk Partitioning"
    
    log_warn "Wiping $INSTALL_DISK..."
    
    # Unmount anything mounted
    umount ${INSTALL_DISK}* 2>/dev/null || true
    
    # Zero out partition table
    dd if=/dev/zero of=$INSTALL_DISK bs=512 count=1 conv=notrunc
    
    # Create GPT partition table with optimal alignment
    parted -s $INSTALL_DISK mklabel gpt
    parted -s $INSTALL_DISK mkpart primary fat32 1MiB 513MiB
    parted -s $INSTALL_DISK set 1 esp on
    parted -s $INSTALL_DISK mkpart primary ext4 513MiB 100%
    
    # Wait for kernel to recognize partitions
    sleep 2
    partprobe $INSTALL_DISK
    sleep 2
    
    # Format partitions
    log_info "Formatting partitions..."
    mkfs.fat -F32 -n BOOT ${INSTALL_DISK}p1
    mkfs.ext4 -F -L debian-root -O ^metadata_csum,^64bit ${INSTALL_DISK}p2
    
    log_info "Disk partitioning complete"
}

# Mount filesystems
mount_filesystems() {
    log_step "Mounting Filesystems"
    
    # Create mount point
    mkdir -p /mnt/debian
    
    # Mount root partition with optimal options
    mount -o noatime,nodiratime ${INSTALL_DISK}p2 /mnt/debian
    
    # Create and mount boot partition
    mkdir -p /mnt/debian/boot/efi
    mount ${INSTALL_DISK}p1 /mnt/debian/boot/efi
    
    log_info "Filesystems mounted at /mnt/debian"
}

# Install base Debian system
install_base_system() {
    log_step "Installing Debian Base System"
    
    # Install debootstrap if needed
    if ! command -v debootstrap &> /dev/null; then
        log_info "Installing debootstrap..."
        apt-get update
        apt-get install -y debootstrap
    fi
    
    # Bootstrap minimal Debian system
    log_info "Bootstrapping Debian 12 (bookworm)..."
    debootstrap --arch=amd64 --variant=minbase bookworm /mnt/debian http://deb.debian.org/debian
    
    log_info "Debian base system installed"
}

# Configure base system
configure_system() {
    log_step "Configuring Base System"
    
    # Set hostname
    echo "$HOSTNAME" > /mnt/debian/etc/hostname
    
    # Configure hosts
    cat > /mnt/debian/etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       $HOSTNAME
::1             localhost ip6-localhost ip6-loopback
EOF
    
    # Configure fstab
    cat > /mnt/debian/etc/fstab << EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
${INSTALL_DISK}p2  /               ext4    noatime,nodiratime,errors=remount-ro 0 1
${INSTALL_DISK}p1  /boot/efi       vfat    defaults        0 2
tmpfs              /tmp            tmpfs   defaults,noatime,mode=1777 0 0
EOF
    
    # Configure network
    cat > /mnt/debian/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

allow-hotplug enp*
iface enp* inet dhcp
EOF
    
    # Set timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /mnt/debian/etc/localtime
    
    # Configure apt sources
    cat > /mnt/debian/etc/apt/sources.list << EOF
deb http://deb.debian.org/debian bookworm main non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main non-free-firmware
EOF
    
    log_info "Base system configured"
}

# Install essential packages
install_essential_packages() {
    log_step "Installing Essential Packages"
    
    # Mount necessary filesystems for chroot
    mount --bind /dev /mnt/debian/dev
    mount --bind /dev/pts /mnt/debian/dev/pts
    mount --bind /proc /mnt/debian/proc
    mount --bind /sys /mnt/debian/sys
    
    # Update package database
    chroot /mnt/debian apt-get update
    
    # Install essential packages
    log_info "Installing kernel and essential packages..."
    chroot /mnt/debian apt-get install -y --no-install-recommends \
        linux-image-amd64 \
        grub-efi-amd64 \
        firmware-linux \
        firmware-amd-graphics \
        openssh-server \
        ca-certificates \
        curl \
        wget \
        git \
        sudo \
        systemd-timesyncd
    
    log_info "Essential packages installed"
}

# Configure SSH
configure_ssh() {
    log_step "Configuring SSH"
    
    # Set root password
    echo "root:$ROOT_PASSWORD" | chroot /mnt/debian chpasswd
    
    # Enable SSH
    chroot /mnt/debian systemctl enable ssh
    
    # Configure SSH for security
    cat >> /mnt/debian/etc/ssh/sshd_config << EOF

# KioskBook security settings
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
EOF
    
    log_info "SSH configured with root access"
}

# Install and configure GRUB
install_bootloader() {
    log_step "Installing GRUB Bootloader"
    
    # Install GRUB to EFI partition
    chroot /mnt/debian grub-install --target=x86_64-efi \
        --efi-directory=/boot/efi \
        --bootloader-id=debian \
        --recheck
    
    # Configure GRUB for fast boot
    cat > /mnt/debian/etc/default/grub << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="KioskBook"
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 vga=current"
GRUB_CMDLINE_LINUX=""
EOF
    
    # Generate GRUB configuration
    chroot /mnt/debian update-grub
    
    log_info "GRUB bootloader installed"
}

# Prepare phase 2 and 3 scripts
prepare_next_phases() {
    log_step "Preparing Phase 2 and 3 Scripts"
    
    # Store configuration for next phases
    cat > /mnt/debian/root/kioskbook.conf << EOF
GITHUB_REPO="$GITHUB_REPO"
HOSTNAME="$HOSTNAME"
TIMEZONE="$TIMEZONE"
EOF
    
    # Create placeholder scripts
    cat > /mnt/debian/root/phase2-harden.sh << 'EOF'
#!/bin/bash
# Phase 2: System Hardening
# To be implemented
echo "Phase 2 script ready - will implement Tailscale + monitoring"
EOF
    
    cat > /mnt/debian/root/phase3-kiosk.sh << 'EOF'
#!/bin/bash
# Phase 3: Kiosk Setup
# To be implemented
echo "Phase 3 script ready - will implement X11 + Chromium + Vue.js"
EOF
    
    chmod +x /mnt/debian/root/phase2-harden.sh
    chmod +x /mnt/debian/root/phase3-kiosk.sh
    
    log_info "Phase 2 and 3 scripts prepared in /root/"
}

# Cleanup and finish
cleanup_and_finish() {
    log_step "Finalizing Installation"
    
    # Unmount chroot filesystems
    umount /mnt/debian/dev/pts
    umount /mnt/debian/dev
    umount /mnt/debian/proc
    umount /mnt/debian/sys
    
    # Unmount main filesystems
    umount /mnt/debian/boot/efi
    umount /mnt/debian
    
    # Sync
    sync
    
    log_info "Installation complete!"
}

# Show completion message
show_completion() {
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}║       PHASE 1 INSTALLATION COMPLETE!                  ║${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${CYAN}System Configuration:${NC}"
    echo -e "  Hostname: $HOSTNAME"
    echo -e "  Disk: $INSTALL_DISK"
    echo -e "  SSH: Enabled (root access)"
    echo -e "  Application: $GITHUB_REPO"
    
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo -e "  1. Remove installation media"
    echo -e "  2. Reboot the system"
    echo -e "  3. SSH into $HOSTNAME"
    echo -e "  4. Run: ./phase2-harden.sh"
    echo -e "  5. Then run: ./phase3-kiosk.sh"
    
    echo -e "\n${BLUE}Rebooting in 10 seconds...${NC}"
    for i in {10..1}; do
        echo -n "$i "
        sleep 1
    done
    
    echo -e "\n${GREEN}Rebooting now!${NC}"
    reboot
}

# Main execution
main() {
    show_banner
    
    # Verify running as root
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root"
    fi
    
    get_configuration
    show_summary
    verify_hardware
    partition_disk
    mount_filesystems
    install_base_system
    configure_system
    install_essential_packages
    configure_ssh
    install_bootloader
    prepare_next_phases
    cleanup_and_finish
    show_completion
}

# Run installation
main "$@"
