#!/bin/bash
# KioskBook One-Shot Debian Installer
# Complete kiosk installation from bare metal to running kiosk

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
DISK="/dev/nvme0n1"
GITHUB_REPO=""
GITHUB_URL=""
ROOT_PASSWORD=""

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
    # clear command may not be available in minimal environment
    printf "\033c" 2>/dev/null || true
    echo -e "${CYAN}"
    echo "┌─────────────────────────────────────┐"
    echo "│                                     │"
    echo "│          KioskBook Installer        │"
    echo "│       One-Shot Debian Kiosk        │"
    echo "│                                     │"
    echo "└─────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "${CYAN}Lenovo M75q-1 + Debian Stable${NC}"
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
    
    # Check for NVMe drive
    if [ ! -b "$DISK" ]; then
        log_error "NVMe drive $DISK not found"
        log_error "This installer is designed for Lenovo M75q-1"
        exit 1
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connection - ensure ethernet is connected"
        exit 1
    fi
    
    # Check for required tools and try to install missing ones
    log_info "Checking for required tools..."
    
    # Core tools that should be available
    MISSING_TOOLS=""
    for tool in debootstrap parted mkfs.ext4 mkfs.fat; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            MISSING_TOOLS="$MISSING_TOOLS $tool"
        fi
    done
    
    # Try to install missing tools
    if [ -n "$MISSING_TOOLS" ]; then
        log_warning "Missing tools:$MISSING_TOOLS"
        log_info "Attempting to install missing tools..."
        
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update >/dev/null 2>&1
            apt-get install -y debootstrap parted e2fsprogs dosfstools util-linux >/dev/null 2>&1
        else
            log_error "Cannot install missing tools - please use Debian Live ISO"
            exit 1
        fi
        
        # Check again
        for tool in debootstrap parted mkfs.ext4 mkfs.fat; do
            if ! command -v "$tool" >/dev/null 2>&1; then
                log_error "Still missing required tool: $tool"
                log_error "Please use Debian Live ISO instead of installer environment"
                exit 1
            fi
        done
    fi
    
    log_info "Environment validation passed"
}

# Get configuration from user
get_configuration() {
    echo -e "${CYAN}KioskBook Configuration${NC}"
    echo "======================="
    echo
    
    # Disk warning
    echo -e "${YELLOW}WARNING: This will completely erase $DISK${NC}"
    echo -e "${RED}All data on this NVMe drive will be permanently lost!${NC}"
    echo
    echo -n -e "${CYAN}Continue? (y/N)${NC}: "
    read confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Installation cancelled"
        exit 0
    fi
    printf "\033c" 2>/dev/null || true
    
    # Get GitHub repository
    echo -n -e "${CYAN}Kiosk application repository${NC} [kenzie/lobby-display]: "
    read GITHUB_REPO
    
    if [ -z "$GITHUB_REPO" ]; then
        GITHUB_REPO="kenzie/lobby-display"
        log_info "Using default repository: $GITHUB_REPO"
    fi
    
    # Convert to GitHub URL
    if echo "$GITHUB_REPO" | grep -q "github.com"; then
        GITHUB_URL="$GITHUB_REPO"
    else
        GITHUB_URL="https://github.com/$GITHUB_REPO.git"
    fi
    printf "\033c" 2>/dev/null || true
    
    # Set root password
    echo -e "${CYAN}Set root password for remote access${NC}"
    while true; do
        echo -n "Enter root password: "
        read -s ROOT_PASSWORD
        echo
        echo -n "Confirm root password: "
        read -s ROOT_PASSWORD_CONFIRM
        echo
        
        if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]; then
            if [ -n "$ROOT_PASSWORD" ]; then
                break
            else
                log_error "Password cannot be empty!"
            fi
        else
            log_error "Passwords do not match!"
        fi
    done
    printf "\033c" 2>/dev/null || true
    
    # Final confirmation
    echo -e "${CYAN}Installation Summary:${NC}"
    echo "Target: $DISK (will be erased)"
    echo "Kiosk App: $GITHUB_REPO"
    echo "OS: Debian Stable (minimal)"
    echo "Boot: Fast, no boot menu"
    echo "Features: SSH, Tailscale, offline operation"
    echo
    echo -n "Proceed with installation? (y/N): "
    read final_confirm
    printf "\033c" 2>/dev/null || true
    
    if [ "$final_confirm" != "y" ] && [ "$final_confirm" != "Y" ]; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# Prepare disk with partitions
prepare_disk() {
    log_step "Preparing Disk: $DISK"
    
    # Unmount any existing mounts
    log_info "Unmounting any existing partitions"
    for partition in $(lsblk -ln -o NAME "$DISK" | tail -n +2); do
        umount "/dev/$partition" 2>/dev/null || true
    done
    
    # Wipe disk
    log_info "Wiping disk and partition table"
    if command -v wipefs >/dev/null 2>&1; then
        wipefs -af "$DISK"
    else
        log_warning "wipefs not available, using dd only"
    fi
    dd if=/dev/zero of="$DISK" bs=1M count=100 status=none 2>/dev/null || dd if=/dev/zero of="$DISK" bs=1M count=100
    
    # Create GPT partition table
    log_info "Creating partition table"
    parted "$DISK" --script mklabel gpt
    
    # Create EFI partition (512MB)
    log_info "Creating EFI partition (512MB)"
    parted "$DISK" --script mkpart primary fat32 1MiB 513MiB
    parted "$DISK" --script set 1 esp on
    
    # Create root partition (remaining space)
    log_info "Creating root partition (remaining space)"
    parted "$DISK" --script mkpart primary ext4 513MiB 100%
    
    # Wait for partition creation
    sleep 2
    partprobe "$DISK"
    sleep 2
    
    # Format partitions
    log_info "Formatting partitions"
    mkfs.fat -F32 "${DISK}p1"
    mkfs.ext4 -F "${DISK}p2"
    
    log_info "Disk preparation completed"
}

# Install minimal Debian base system
install_debian_base() {
    log_step "Installing Debian Base System"
    
    # Mount root partition
    log_info "Mounting target filesystem"
    mount "${DISK}p2" /mnt
    
    # Install Debian base system using debootstrap
    log_info "Installing Debian base system (this may take several minutes)"
    debootstrap --arch=amd64 --variant=minbase stable /mnt http://deb.debian.org/debian
    
    # Mount special filesystems
    log_info "Setting up chroot environment"
    mount "${DISK}p1" /mnt/boot
    mount --bind /dev /mnt/dev
    mount --bind /proc /mnt/proc
    mount --bind /sys /mnt/sys
    
    # Configure basic system files
    log_info "Configuring base system"
    
    # Set hostname
    echo "kioskbook" > /mnt/etc/hostname
    
    # Configure hosts
    cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
127.0.1.1   kioskbook
::1         localhost ip6-localhost ip6-loopback
EOF
    
    # Configure network
    cat > /mnt/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Configure fstab
    ROOT_UUID=$(blkid -s UUID -o value "${DISK}p2")
    EFI_UUID=$(blkid -s UUID -o value "${DISK}p1")
    
    cat > /mnt/etc/fstab << EOF
UUID=$ROOT_UUID / ext4 defaults 0 1
UUID=$EFI_UUID /boot vfat defaults 0 2
tmpfs /tmp tmpfs defaults,nodev,nosuid,noexec 0 0
EOF
    
    log_info "Debian base system installed"
}

# Install and configure packages
install_packages() {
    log_step "Installing Kiosk Packages"
    
    # Copy DNS configuration
    cp /etc/resolv.conf /mnt/etc/resolv.conf
    
    # Update package list
    log_info "Updating package repositories"
    chroot /mnt apt-get update
    
    # Install essential packages
    log_info "Installing essential packages"
    DEBIAN_FRONTEND=noninteractive chroot /mnt apt-get install -y \
        systemd-boot \
        linux-image-amd64 \
        firmware-linux \
        openssh-server \
        sudo \
        curl \
        wget \
        git \
        ca-certificates \
        apt-transport-https \
        gnupg \
        lsb-release
    
    # Install X11 and desktop packages
    log_info "Installing X11 and display packages"
    DEBIAN_FRONTEND=noninteractive chroot /mnt apt-get install -y \
        xorg \
        xserver-xorg-video-intel \
        xserver-xorg-video-amdgpu \
        chromium \
        openbox \
        lightdm \
        plymouth \
        plymouth-themes
    
    # Install Node.js
    log_info "Installing Node.js"
    chroot /mnt curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    DEBIAN_FRONTEND=noninteractive chroot /mnt apt-get install -y nodejs
    
    # Install Tailscale
    log_info "Installing Tailscale"
    chroot /mnt curl -fsSL https://tailscale.com/install.sh | sh
    
    # Clean up
    chroot /mnt apt-get clean
    
    log_info "Package installation completed"
}

# Configure kiosk user and auto-login
configure_kiosk_user() {
    log_step "Configuring Kiosk User"
    
    # Set root password
    log_info "Setting root password"
    echo "root:$ROOT_PASSWORD" | chroot /mnt chpasswd
    
    # Create kiosk user
    log_info "Creating kiosk user"
    chroot /mnt useradd -m -s /bin/bash -G sudo,video,audio kiosk
    echo "kiosk:kiosk123" | chroot /mnt chpasswd
    
    # Configure auto-login
    log_info "Configuring auto-login"
    cat > /mnt/etc/lightdm/lightdm.conf << EOF
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
EOF
    
    # Enable lightdm
    chroot /mnt systemctl enable lightdm
    
    log_info "Kiosk user configuration completed"
}

# Setup kiosk application
setup_kiosk_application() {
    log_step "Setting Up Kiosk Application"
    
    # Create application directory
    log_info "Creating application directory"
    mkdir -p /mnt/home/kiosk/kiosk-app
    
    # Clone repository
    log_info "Cloning application repository: $GITHUB_URL"
    chroot /mnt git clone "$GITHUB_URL" /home/kiosk/kiosk-app
    chroot /mnt chown -R kiosk:kiosk /home/kiosk/kiosk-app
    
    # Install application dependencies
    if [ -f "/mnt/home/kiosk/kiosk-app/package.json" ]; then
        log_info "Installing application dependencies"
        chroot /mnt sudo -u kiosk sh -c "cd /home/kiosk/kiosk-app && npm install"
        
        # Build if needed
        if chroot /mnt sudo -u kiosk sh -c "cd /home/kiosk/kiosk-app && npm run --silent 2>/dev/null" | grep -q "build"; then
            log_info "Building application"
            chroot /mnt sudo -u kiosk sh -c "cd /home/kiosk/kiosk-app && npm run build"
        fi
    fi
    
    # Create kiosk startup script
    log_info "Creating kiosk startup configuration"
    cat > /mnt/home/kiosk/.config/openbox/autostart << 'EOF'
#!/bin/bash

# Disable screensaver and power management
xset s off
xset -dpms
xset s noblank

# Set background
hsetroot -solid "#000000" &

# Start application server
cd /home/kiosk/kiosk-app
if [ -f package.json ] && npm run --silent 2>/dev/null | grep -q "start"; then
    npm start &
    sleep 5
fi

# Start Chromium in kiosk mode
chromium \
    --kiosk \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --disable-extensions \
    --disable-plugins \
    --disable-translate \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-renderer-backgrounding \
    --start-fullscreen \
    --window-size=1920,1080 \
    --app=http://localhost:3000
EOF
    
    mkdir -p /mnt/home/kiosk/.config/openbox
    chroot /mnt chown -R kiosk:kiosk /home/kiosk/.config
    chmod +x /mnt/home/kiosk/.config/openbox/autostart
    
    log_info "Kiosk application setup completed"
}

# Configure fast boot
configure_boot() {
    log_step "Configuring Fast Boot"
    
    # Install systemd-boot
    log_info "Installing systemd-boot bootloader"
    chroot /mnt bootctl install
    
    # Configure systemd-boot
    cat > /mnt/boot/loader/loader.conf << EOF
default debian
timeout 0
console-mode max
editor no
EOF
    
    # Create boot entry
    KERNEL_VERSION=$(chroot /mnt ls /boot | grep vmlinuz | head -1 | sed 's/vmlinuz-//')
    ROOT_UUID=$(blkid -s UUID -o value "${DISK}p2")
    
    cat > /mnt/boot/loader/entries/debian.conf << EOF
title Debian
linux /vmlinuz-$KERNEL_VERSION
initrd /initrd.img-$KERNEL_VERSION
options root=UUID=$ROOT_UUID rw quiet splash plymouth.ignore-serial-consoles
EOF
    
    # Configure Plymouth for minimal boot splash
    log_info "Configuring minimal boot splash"
    chroot /mnt plymouth-set-default-theme spinner
    chroot /mnt update-initramfs -u
    
    # Optimize boot services
    log_info "Optimizing boot services"
    chroot /mnt systemctl disable apt-daily.timer
    chroot /mnt systemctl disable apt-daily-upgrade.timer
    chroot /mnt systemctl disable man-db.timer
    chroot /mnt systemctl enable ssh
    
    log_info "Boot configuration completed"
}

# Final system configuration
final_configuration() {
    log_step "Final System Configuration"
    
    # Configure SSH
    log_info "Configuring SSH access"
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /mnt/etc/ssh/sshd_config
    
    # Set timezone
    chroot /mnt timedatectl set-timezone UTC
    
    # Clean up
    log_info "Cleaning up installation"
    rm -f /mnt/etc/resolv.conf
    
    # Unmount filesystems
    log_info "Unmounting filesystems"
    umount /mnt/sys
    umount /mnt/proc  
    umount /mnt/dev
    umount /mnt/boot
    umount /mnt
    
    log_info "Final configuration completed"
}

# Main installation function
main() {
    show_banner
    validate_environment
    get_configuration
    
    log_step "Starting KioskBook Installation"
    
    prepare_disk
    install_debian_base
    install_packages
    configure_kiosk_user
    setup_kiosk_application
    configure_boot
    final_configuration
    
    echo
    echo -e "${GREEN}KIOSKBOOK INSTALLATION COMPLETED!${NC}"
    echo
    echo "Installation Summary:"
    echo "• OS: Debian Stable (minimal)"
    echo "• Hostname: kioskbook"
    echo "• Kiosk App: $GITHUB_REPO"
    echo "• Boot: Fast (<10 seconds)"
    echo "• Access: SSH enabled, Tailscale installed"
    echo "• User: kiosk (auto-login)"
    echo
    echo "The system will reboot into your kiosk application."
    echo "For remote access, run: tailscale up"
    echo
    echo "Rebooting in 10 seconds..."
    sleep 10
    reboot
}

# Run main function
main "$@"