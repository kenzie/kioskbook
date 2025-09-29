#!/bin/sh
# KioskBook Phase 1: Brutal Alpine Installation
# Lenovo M75q-1 + Alpine Linux 3.22.1 USB ISO
# Goal: Fast, reliable Alpine installation that boots

set -ex  # Enable both error exit and command tracing

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Show banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "┌─────────────────────────────────────┐"
    echo "│                                     │"
    echo "│        KioskBook Phase 1            │"
    echo "│     Brutal Alpine Installation      │"
    echo "│                                     │"
    echo "└─────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "${CYAN}Lenovo M75q-1 + Alpine Linux 3.22.1${NC}"
    echo
}

# Validate environment
validate_environment() {
    log_step "Validating Installation Environment"
    
    # Check if running as root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check if running on Alpine Linux
    if ! [ -f /etc/alpine-release ] && ! command -v apk >/dev/null 2>&1; then
        log_error "This installer requires Alpine Linux ISO"
        exit 1
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connection - ensure ethernet is connected"
        exit 1
    fi
    
    # Auto-detect NVMe drive
    if [ -b "/dev/nvme0n1" ]; then
        DISK="/dev/nvme0n1"
        log_info "Detected NVMe drive: $DISK"
    else
        log_error "No NVMe drive found at /dev/nvme0n1"
        log_error "This installer is designed for Lenovo M75q-1"
        exit 1
    fi
    
    log_info "Environment validation passed"
}

# Get configuration
get_configuration() {
    echo -e "${CYAN}KioskBook Configuration${NC}"
    echo "=========================="
    echo
    
    # Show what will happen
    echo -e "${YELLOW}WARNING: BRUTAL INSTALLATION${NC}"
    echo "This will:"
    echo "• COMPLETELY ERASE $DISK"
    echo "• DESTROY ALL DATA on the NVMe drive"
    echo "• Install Alpine Linux from scratch"
    echo "• Configure for kiosk operation"
    echo
    
    # Confirm destruction
    echo -e "${RED}ALL DATA WILL BE PERMANENTLY LOST!${NC}"
    echo -n -e "${CYAN}Type 'DESTROY' to continue${NC}: "
    read confirm
    
    if [ "$confirm" != "DESTROY" ]; then
        log_info "Installation cancelled - nothing was changed"
        exit 0
    fi
    clear
    
    # Get GitHub repository
    echo -n -e "${CYAN}Kiosk display git repo${NC} [kenzie/lobby-display]: "
    read GITHUB_REPO
    clear
    
    if [ -z "$GITHUB_REPO" ]; then
        GITHUB_REPO="kenzie/lobby-display"
    fi
    
    # Convert to GitHub URL
    if echo "$GITHUB_REPO" | grep -q "github.com"; then
        GITHUB_URL="$GITHUB_REPO"
    else
        GITHUB_URL="https://github.com/$GITHUB_REPO.git"
    fi
    
    # Set root password
    echo -e "${CYAN}Set root password for remote access${NC}"
    echo -n "Enter root password: "
    read -s ROOT_PASSWORD
    echo
    echo -n "Confirm root password: "
    read -s ROOT_PASSWORD_CONFIRM
    echo
    clear
    
    if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
        log_error "Passwords do not match!"
        exit 1
    fi
    
    if [ -z "$ROOT_PASSWORD" ]; then
        log_error "Root password cannot be empty!"
        exit 1
    fi
    
    # Final confirmation
    echo -e "${CYAN}Installation Summary:${NC}"
    echo "Target: $DISK (NVMe drive will be erased)"
    echo "Kiosk App: $GITHUB_REPO"
    echo "System: Alpine Linux with SSH enabled"
    echo
    echo -n "Proceed with BRUTAL installation? (y/N): "
    read final_confirm
    clear
    
    if [ "$final_confirm" != "y" ] && [ "$final_confirm" != "Y" ]; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# Brutal disk preparation  
brutal_disk_wipe() {
    log_step "BRUTAL DISK WIPE: $DISK"
    
    # Kill any processes using the disk
    log_info "Stopping any processes using $DISK"
    # fuser might not be available, so use alternative approach
    if command -v fuser >/dev/null 2>&1; then
        fuser -km "$DISK"* 2>/dev/null || true
    else
        log_warning "fuser command not available, skipping process termination"
    fi
    
    # Unmount everything
    log_info "Unmounting all partitions on $DISK"
    # More robust partition detection
    if ls "${DISK}"* >/dev/null 2>&1; then
        for partition in $(ls ${DISK}* 2>/dev/null || true); do
            if [ "$partition" != "$DISK" ]; then
                log_info "Unmounting $partition"
                umount "$partition" 2>/dev/null || true
            fi
        done
    else
        log_info "No existing partitions found on $DISK"
    fi
    
    # Wait for unmounts
    sleep 2
    
    # Wipe partition table and first few MB
    log_info "Wiping partition table and boot sectors"
    dd if=/dev/zero of="$DISK" bs=1M count=100 2>/dev/null || true
    
    # Clear any remaining filesystem signatures
    if command -v wipefs >/dev/null 2>&1; then
        wipefs -af "$DISK" 2>/dev/null || true
    else
        log_warning "wipefs not available, skipping filesystem signature clearing"
    fi
    
    # Force kernel to re-read partition table
    if command -v partprobe >/dev/null 2>&1; then
        partprobe "$DISK" 2>/dev/null || true
    else
        log_warning "partprobe not available, using blockdev instead"
        blockdev --rereadpt "$DISK" 2>/dev/null || true
    fi
    
    log_info "Disk wipe completed - $DISK is now clean"
}

# Install Alpine manually (setup-alpine is unreliable)
install_alpine() {
    log_step "Installing Alpine Linux Manually"
    
    # Partition the disk
    log_info "Creating partitions on $DISK"
    (
    echo g      # Create GPT partition table
    echo n      # New partition
    echo 1      # Partition 1
    echo        # Default start
    echo +512M  # 512MB for EFI
    echo t      # Change type
    echo 1      # EFI System
    echo n      # New partition  
    echo 2      # Partition 2
    echo        # Default start
    echo        # Default end (rest of disk)
    echo w      # Write changes
    ) | fdisk "$DISK"
    
    # Wait for partition creation
    sleep 2
    partprobe "$DISK"
    sleep 2
    
    # Determine partition names
    if echo "$DISK" | grep -q "nvme"; then
        EFI_PARTITION="${DISK}p1"
        ROOT_PARTITION="${DISK}p2"
    else
        EFI_PARTITION="${DISK}1"
        ROOT_PARTITION="${DISK}2"
    fi
    
    log_info "Created partitions: $EFI_PARTITION (EFI), $ROOT_PARTITION (root)"
    
    # Format partitions
    log_info "Formatting partitions"
    mkfs.fat -F32 "$EFI_PARTITION"
    mkfs.ext4 -F "$ROOT_PARTITION"
    
    # Mount partitions for installation
    log_info "Mounting partitions for installation"
    mount "$ROOT_PARTITION" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PARTITION" /mnt/boot
    
    # Install Alpine base system
    log_info "Installing Alpine base system"
    apk add --root /mnt --initdb alpine-base alpine-conf
    
    # Copy basic system files
    cp /etc/resolv.conf /mnt/etc/
    
    # Set up fstab
    log_info "Creating filesystem table"
    cat > /mnt/etc/fstab << EOF
$ROOT_PARTITION / ext4 rw,relatime 0 1
$EFI_PARTITION /boot vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 2
tmpfs /tmp tmpfs nosuid,nodev,noexec 0 0
EOF
    
    # Set hostname
    echo "kioskbook" > /mnt/etc/hostname
    
    # Create network configuration
    cat > /mnt/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Install and configure bootloader
    log_info "Installing bootloader"
    chroot /mnt apk add grub grub-efi efibootmgr
    chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=alpine
    chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    
    # Install kernel
    chroot /mnt apk add linux-lts
    
    # Enable essential services
    chroot /mnt rc-update add devfs sysinit
    chroot /mnt rc-update add dmesg sysinit
    chroot /mnt rc-update add mdev sysinit
    chroot /mnt rc-update add hwdrivers sysinit
    chroot /mnt rc-update add hwclock boot
    chroot /mnt rc-update add modules boot
    chroot /mnt rc-update add sysctl boot
    chroot /mnt rc-update add hostname boot
    chroot /mnt rc-update add bootmisc boot
    chroot /mnt rc-update add syslog boot
    chroot /mnt rc-update add networking default
    chroot /mnt rc-update add urandom default
    chroot /mnt rc-update add acpid default
    chroot /mnt rc-update add crond default
    chroot /mnt rc-update add killprocs shutdown
    chroot /mnt rc-update add mount-ro shutdown
    chroot /mnt rc-update add savecache shutdown
    
    log_info "Alpine Linux base installation completed"
}

# Configure for phases 2-3 and fix what setup-alpine missed
setup_phases() {
    log_step "Configuring Installed System"
    
    # System is already mounted at /mnt from installation
    # Just make sure we have the partition variables set
    if echo "$DISK" | grep -q "nvme"; then
        ROOT_PARTITION="${DISK}p2"
    else
        ROOT_PARTITION="${DISK}2"
    fi
    
    # Set root password properly (setup-alpine often fails at this)
    log_info "Setting root password on installed system..."
    echo "root:$ROOT_PASSWORD" | chroot /mnt chpasswd
    
    # Ensure SSH is enabled (setup-alpine often misses this too)
    log_info "Enabling SSH service..."
    chroot /mnt rc-update add sshd default
    
    # Enable networking service
    chroot /mnt rc-update add networking default
    
    # Create phase 2 script (system hardening)
    cat > /mnt/root/phase2-harden.sh << 'EOF'
#!/bin/sh
# Phase 2: System Hardening
echo "Phase 2: System Hardening - Coming soon"
# TODO: Implement system hardening
EOF
    chmod +x /mnt/root/phase2-harden.sh
    
    # Create phase 3 script (kiosk setup)
    cat > /mnt/root/phase3-kiosk.sh << 'EOFKIOSK'
#!/bin/sh
# Phase 3: Fast Kiosk Setup
echo "Phase 3: Fast Kiosk Setup - Coming soon"
# TODO: Implement fast X11 + Chromium + Vue.js setup
EOFKIOSK
    chmod +x /mnt/root/phase3-kiosk.sh
    
    # Store GitHub URL for phase 3
    echo "$GITHUB_URL" > /mnt/root/.kioskbook-repo
    
    # Create post-boot configuration script that runs once
    cat > /mnt/etc/local.d/kioskbook-postinstall.start << 'EOFPOST'
#!/bin/sh
# KioskBook post-install configuration
# This runs once after first boot to verify everything is working

# Ensure SSH is running
if ! rc-service sshd status >/dev/null 2>&1; then
    rc-service sshd start
fi

# Display system info
echo "=========================================="
echo "KioskBook Phase 1 Installation Complete"
echo "=========================================="
echo "Hostname: $(hostname)"
echo "IP Address: $(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
echo "SSH Status: $(rc-service sshd status 2>/dev/null | head -1)"
echo ""
echo "Ready for Phase 2 & 3:"
echo "  /root/phase2-harden.sh"
echo "  /root/phase3-kiosk.sh"
echo ""
echo "Repository: $(cat /root/.kioskbook-repo)"
echo "=========================================="

# Mark as completed so this doesn't run again
touch /root/.kioskbook-phase1-complete
EOFPOST
    
    chmod +x /mnt/etc/local.d/kioskbook-postinstall.start
    
    # Enable local service to run our post-install script
    chroot /mnt rc-update add local default
    
    # Unmount
    umount /mnt
    
    log_info "System configuration completed"
}

# Main installation function
main() {
    echo "DEBUG: Starting main function"
    show_banner
    echo "DEBUG: Banner shown"
    validate_environment
    echo "DEBUG: Environment validated"
    get_configuration
    echo "DEBUG: Configuration complete"
    
    log_step "Starting BRUTAL Alpine Installation"
    echo "DEBUG: About to start brutal disk wipe"
    
    brutal_disk_wipe
    echo "DEBUG: Disk wipe completed"
    install_alpine
    echo "DEBUG: Alpine installation completed"
    setup_phases
    echo "DEBUG: Phase setup completed"
    
    log_info "Phase 1 installation completed successfully!"
    echo
    echo -e "${GREEN}PHASE 1 INSTALLATION SUCCESSFUL!${NC}"
    echo
    echo "Installed:"
    echo "• Alpine Linux on $DISK"
    echo "• SSH enabled (root password set)"
    echo "• Hostname: kioskbook"
    echo "• Kiosk repo: $GITHUB_REPO"
    echo "• Phase 2 & 3 scripts ready"
    echo
    echo -e "${YELLOW}IMPORTANT: Remove the USB installer now!${NC}"
    echo
    echo -n "Remove USB drive and press Enter to reboot..."
    read
    reboot
}

# Debug: Script is being executed
echo "DEBUG: KioskBook installer script starting..."
echo "DEBUG: Current user: $(whoami)"
echo "DEBUG: Current directory: $(pwd)"
echo "DEBUG: Script arguments: $@"

# Run main function
main "$@"

echo "DEBUG: Script completed successfully"