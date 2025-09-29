#!/bin/sh
# KioskBook Phase 1: Brutal Alpine Installation
# Lenovo M75q-1 + Alpine Linux 3.22.1 USB ISO
# Goal: Fast, reliable Alpine installation that boots

set -e

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
    fuser -km "$DISK"* 2>/dev/null || true
    
    # Unmount everything
    log_info "Unmounting all partitions on $DISK"
    for partition in $(ls ${DISK}* 2>/dev/null); do
        umount "$partition" 2>/dev/null || true
    done
    
    # Wait for unmounts
    sleep 2
    
    # Wipe partition table and first few MB
    log_info "Wiping partition table and boot sectors"
    dd if=/dev/zero of="$DISK" bs=1M count=100 2>/dev/null || true
    
    # Clear any remaining filesystem signatures
    wipefs -af "$DISK" 2>/dev/null || true
    
    # Force kernel to re-read partition table
    partprobe "$DISK" 2>/dev/null || true
    
    log_info "Disk wipe completed - $DISK is now clean"
}

# Install Alpine using setup-alpine
install_alpine() {
    log_step "Installing Alpine Linux"
    
    # Let Alpine handle everything
    log_info "Running Alpine's automated installation"
    
    # Set up answers for setup-alpine
    export KEYMAPOPTS="us us"
    export HOSTNAMEOPTS="-n kioskbook"
    export INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0  
iface eth0 inet dhcp"
    export DNSOPTS="8.8.8.8 8.8.4.4"
    export TIMEZONEOPTS="-z UTC"
    export PROXYOPTS="none"
    export APKREPOSOPTS="-r"
    export USEROPTS="-a -u -g wheel kiosk"
    export SSHDOPTS="-c openssh"
    export NTPOPTS="-c chrony"
    export DISKOPTS="-m sys $DISK"
    
    # Create answer file for completely automated installation
    cat > /tmp/answers << EOF
us
us
kioskbook
eth0
dhcp
none
8.8.8.8 8.8.4.4
UTC
-r
kiosk
openssh
chrony
sys
$DISK
y
EOF
    
    # Run setup-alpine with answers
    setup-alpine -f /tmp/answers
    
    log_info "Alpine Linux installation completed"
}

# Configure for phases 2-3
setup_phases() {
    log_step "Setting Up Phase 2 & 3 Scripts"
    
    # Mount the installed system  
    mount "${DISK}p2" /mnt 2>/dev/null || mount "${DISK}2" /mnt
    
    # Set root password on installed system
    echo "root:$ROOT_PASSWORD" | chroot /mnt chpasswd
    
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
    
    # Unmount
    umount /mnt
    
    log_info "Phase scripts configured"
}

# Main installation function
main() {
    show_banner
    validate_environment
    get_configuration
    
    log_step "Starting BRUTAL Alpine Installation"
    
    brutal_disk_wipe
    install_alpine
    setup_phases
    
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

# Run main function
main "$@"