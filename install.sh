#!/bin/sh
# KioskBook Professional Kiosk Deployment Platform
# Alpine Linux + Tailscale Ready
# Compatible with ash shell

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
DISK=""
GITHUB_REPO=""
GITHUB_URL=""
TAILSCALE_KEY=""
EFI_PARTITION=""
ROOT_PARTITION=""

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
    echo "│        Route 19 KioskBook           │"
    echo "│                                     │"
    echo "└─────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "${CYAN}Professional Kiosk Deployment Platform${NC}"
    echo -e "${CYAN}Alpine Linux + Tailscale Ready${NC}"
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
    alpine_detected=false
    
    # Debug: Show what files exist
    log_info "Checking Alpine Linux detection..."
    log_info "Files found:"
    ls -la /etc/ | grep -E "(alpine|os-release)" || log_info "No Alpine files found"
    
    # Check for Alpine release file
    if [ -f /etc/alpine-release ]; then
        alpine_detected=true
        log_info "Found /etc/alpine-release"
    fi
    
    # Check for Alpine in os-release
    if [ -f /etc/os-release ]; then
        log_info "Found /etc/os-release, checking contents:"
        cat /etc/os-release
        if grep -q "Alpine" /etc/os-release; then
            alpine_detected=true
            log_info "Alpine found in os-release"
        fi
    fi
    
    # Check for apk package manager
    if command -v apk >/dev/null 2>&1; then
        alpine_detected=true
        log_info "Found apk package manager"
    else
        log_info "apk package manager not found"
    fi
    
    log_info "Alpine detection result: $alpine_detected"
    
    if [ "$alpine_detected" = "false" ]; then
        log_error "This installer is designed for Alpine Linux"
        log_error "Please boot from Alpine Linux ISO and try again"
        exit 1
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connection detected"
        log_error "Please ensure ethernet is connected and working"
        exit 1
    fi
    
    # Check what tools are actually available
    log_info "Checking available tools..."
    
    # List what's actually available
    log_info "Available commands:"
    which fdisk || log_info "fdisk not found"
    which mkfs.ext4 || log_info "mkfs.ext4 not found" 
    which mount || log_info "mount not found"
    which chroot || log_info "chroot not found"
    which lsblk || log_info "lsblk not found"
    which setup-disk || log_info "setup-disk not found"
    
    # Try to install basic tools if missing
    log_info "Attempting to install basic tools..."
    apk update || log_warning "apk update failed"
    
    # Try common package names
    apk add util-linux 2>/dev/null || log_warning "util-linux not available"
    apk add e2fsprogs 2>/dev/null || log_warning "e2fsprogs not available"
    
    # Check again after attempted installation
    log_info "Tools after installation attempt:"
    which fdisk || log_info "fdisk still not found"
    which mkfs.ext4 || log_info "mkfs.ext4 still not found"
    
    log_info "Environment validation passed"
}

# Get configuration
get_configuration() {
    echo -e "${CYAN}KioskBook Configuration${NC}"
    echo "=========================="
    echo
    
    # Auto-detect target disk
    echo -e "${CYAN}Available disks:${NC}"
    fdisk -l 2>/dev/null | grep "Disk /dev/" | grep -v "loop"
    echo
    
    # Auto-detect NVMe drive
    if [ -b "/dev/nvme0n1" ]; then
        DISK="/dev/nvme0n1"
        echo -e "${GREEN}Auto-detected NVMe drive: $DISK${NC}"
    elif [ -b "/dev/sda" ]; then
        DISK="/dev/sda"
        echo -e "${YELLOW}Auto-detected SATA drive: $DISK${NC}"
    else
        log_error "No suitable disk found (looking for /dev/nvme0n1 or /dev/sda)"
        exit 1
    fi
    
    # Confirm disk overwrite
    echo
    echo -e "${RED}WARNING: This will completely erase $DISK${NC}"
    echo -e "${RED}All data on this disk will be permanently lost!${NC}"
    echo
    echo -n -e "${CYAN}Continue with $DISK? (y/N)${NC}: "
    read confirm
    clear
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
    
    # Get GitHub repository
    echo -n -e "${CYAN}Kiosk display git repo${NC} [kenzie/lobby-display]: "
    read GITHUB_REPO
    clear
    
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
    
    # Tailscale will be installed but not authenticated
    log_info "Tailscale will be installed but not authenticated"
    log_info "You can authenticate it later via SSH"
    TAILSCALE_KEY=""
    
    echo
    echo -e "${CYAN}Installation Summary:${NC}"
    echo "Target Disk: $DISK"
    echo "Kiosk App: $GITHUB_REPO"
    echo "Tailscale: Installed (Authenticate later via SSH)"
    echo
    echo -n "Proceed with installation? (y/N): "
    read confirm
    clear
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    # Set root password
    echo -e "${CYAN}Setting root password${NC}"
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
}

# Prepare disk
prepare_disk() {
    log_step "Preparing Target Disk: $DISK"
    
    # Validate disk exists
    if [ ! -b "$DISK" ]; then
        log_error "Invalid disk: $DISK"
        exit 1
    fi
    
    # Clean up any previous failed installation
    log_info "Cleaning up any previous installation..."
    
    # Unmount any existing mounts
    umount /mnt/root/boot 2>/dev/null || true
    umount /mnt/root 2>/dev/null || true
    umount /mnt/boot 2>/dev/null || true
    
    # Unmount any partitions on this disk
    for partition in $(ls ${DISK}* 2>/dev/null); do
        umount "$partition" 2>/dev/null || true
    done
    
    # Wait for unmount to complete
    sleep 2
    
    # Create partition table and partitions
    log_info "Creating partition table and partitions on $DISK"
    
    # Create GPT partition table and partitions using fdisk
    # EFI boot partition (512MB) and root partition (remaining space)
    echo -e "g\nn\n\n\n+512M\nt\n1\nn\n\n\n\nw" | fdisk "$DISK"
    
    # Wait for partitions to be created
    sleep 2
    
    # Determine partition names based on disk type
    if echo "$DISK" | grep -q "nvme"; then
        # NVMe partitions: nvme0n1p1, nvme0n1p2
        EFI_PARTITION="${DISK}p1"
        ROOT_PARTITION="${DISK}p2"
    else
        # SATA partitions: sda1, sda2
        EFI_PARTITION="${DISK}1"
        ROOT_PARTITION="${DISK}2"
    fi
    
    # Create filesystems
    log_info "Creating filesystems"
    
    # Format EFI partition (try different FAT tools)
    if command -v mkfs.fat >/dev/null 2>&1; then
        mkfs.fat -F32 "$EFI_PARTITION"
    elif command -v mkfs.vfat >/dev/null 2>&1; then
        mkfs.vfat -F32 "$EFI_PARTITION"
    else
        log_error "No FAT filesystem tool found"
        exit 1
    fi
    
    # Format root partition
    mkfs.ext4 -F "$ROOT_PARTITION"
    
    # Mount partitions
    log_info "Mounting partitions"
    
    # Create mount points
    mkdir -p /mnt/boot
    mkdir -p /mnt/root
    
    # Mount root partition
    mount "$ROOT_PARTITION" /mnt/root
    
    # Mount EFI partition
    mount "$EFI_PARTITION" /mnt/boot
    
    # Create boot directory in root
    mkdir -p /mnt/root/boot
    
    # Bind mount EFI to root/boot
    mount --bind /mnt/boot /mnt/root/boot
    
    log_info "Disk preparation completed"
}

# Install basic system
install_system() {
    log_step "Installing Alpine Linux System"
    
    # Unmount partitions before using setup-disk
    log_info "Unmounting partitions for setup-disk..."
    umount /mnt/root/boot 2>/dev/null || true
    umount /mnt/root 2>/dev/null || true
    umount /mnt/boot 2>/dev/null || true
    
    # Mount root partition
    log_info "Mounting root partition..."
    mount "$ROOT_PARTITION" /mnt/root
    mount "$EFI_PARTITION" /mnt/boot
    mount --bind /mnt/boot /mnt/root/boot
    
    # Verify mount points
    if ! mountpoint -q /mnt/root; then
        log_error "/mnt/root is not properly mounted"
        exit 1
    fi
    
    # Install Alpine Linux base system manually
    log_info "Installing Alpine Linux base system..."
    
    # Download and extract Alpine rootfs
    cd /tmp
    wget https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.1-x86_64.tar.gz
    tar -xzf alpine-minirootfs-3.22.1-x86_64.tar.gz -C /mnt/root
    
    # Setup apk with reliable mirror
    setup-apkcache /mnt/root/cache
    
    # Configure reliable Alpine mirror
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/main" > /mnt/root/etc/apk/repositories
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /mnt/root/etc/apk/repositories
    
    # Update package index with retry
    log_info "Updating package index..."
    for i in 1 2 3; do
        if chroot /mnt/root apk update; then
            log_info "Package index updated successfully"
            break
        else
            log_warning "Package index update failed, attempt $i/3"
            if [ $i -eq 3 ]; then
                log_error "Failed to update package index after 3 attempts"
                exit 1
            fi
            sleep 5
        fi
    done
    
    # Install essential packages
    chroot /mnt/root apk add \
        linux-lts \
        linux-firmware \
        e2fsprogs \
        util-linux \
        coreutils \
        curl \
        wget \
        git \
        nodejs \
        npm \
        chromium \
        xorg-server \
        xf86-video-fbdev \
        xf86-video-vesa \
        xf86-video-intel \
        xf86-video-amdgpu \
        xf86-video-nouveau \
        xf86-input-evdev \
        xf86-input-keyboard \
        xf86-input-mouse \
        xset \
        xrandr \
        xdotool \
        openrc \
        supervisor \
        tzdata \
        openssh \
        sudo \
        nano \
        htop \
        bc \
        jq \
        efibootmgr \
        imagemagick \
        fbi \
        tailscale
    
    log_info "System packages installed"
}

# Setup network
setup_network() {
    log_step "Setting Up Network Configuration"
    
    # Configure hostname
    echo "kioskbook" > /mnt/root/etc/hostname
    
    # Copy hosts file
    cp config/hosts /mnt/root/etc/hosts
    
    # Copy network interfaces
    mkdir -p /mnt/root/etc/network
    cp config/interfaces /mnt/root/etc/network/interfaces
    
    log_info "Network configuration completed"
}

# Setup fstab
setup_fstab() {
    log_step "Setting Up Filesystem Table"
    
    # Copy fstab template and replace variables
    cp config/fstab /mnt/root/etc/fstab
    sed -i "s/ROOT_PARTITION/$ROOT_PARTITION/g" /mnt/root/etc/fstab
    sed -i "s/EFI_PARTITION/$EFI_PARTITION/g" /mnt/root/etc/fstab
    
    log_info "Filesystem table configured"
}

# Setup boot
setup_boot() {
    log_step "Setting Up Direct EFI Boot Configuration"
    
    # Install syslinux for EFI boot
    chroot /mnt/root syslinux-install_update -i -a -m
    
    # Create syslinux configuration for direct boot
    cat > /mnt/root/boot/syslinux/syslinux.cfg << 'EOF'
DEFAULT linux
LABEL linux
  KERNEL vmlinuz-lts
  APPEND initrd=initramfs-lts root=ROOT_PARTITION quiet
EOF
    
    # Replace ROOT_PARTITION placeholder
    sed -i "s/ROOT_PARTITION/$ROOT_PARTITION/g" /mnt/root/boot/syslinux/syslinux.cfg
    
    # Create EFI boot entry
    chroot /mnt/root efibootmgr --create \
        --disk "$DISK" \
        --part 1 \
        --label "KioskBook" \
        --loader /EFI/BOOT/BOOTX64.EFI
    
    log_info "Direct EFI boot configuration completed"
}

# Setup kiosk user
setup_kiosk_user() {
    log_step "Setting Up Kiosk User"
    
    # Create kiosk user
    chroot /mnt/root adduser -D -s /bin/sh kiosk
    
    # Set root password
    echo "root:$ROOT_PASSWORD" | chroot /mnt/root chpasswd
    
    # Set kiosk password (same as root for simplicity)
    echo "kiosk:$ROOT_PASSWORD" | chroot /mnt/root chpasswd
    
    # Add to sudo group
    chroot /mnt/root adduser kiosk wheel
    
    # Copy sudoers configuration
    cp config/sudoers.wheel /mnt/root/etc/sudoers.d/wheel
    
    log_info "Kiosk user created"
}

# Setup kiosk app
setup_kiosk_app() {
    log_step "Setting Up Kiosk Display Application"
    
    # Create app directory
    mkdir -p /mnt/root/opt/kiosk-app
    
    # Copy clone script and replace GitHub URL
    cp config/clone-app.start /mnt/root/etc/local.d/clone-app.start
    sed -i "s/GITHUB_URL/$GITHUB_URL/g" /mnt/root/etc/local.d/clone-app.start
    chmod +x /mnt/root/etc/local.d/clone-app.start
    
    # Copy app startup script
    cp config/kiosk-app.start /mnt/root/opt/kiosk-app/start.sh
    chmod +x /mnt/root/opt/kiosk-app/start.sh
    chroot /mnt/root chown kiosk:kiosk /mnt/root/opt/kiosk-app/start.sh
    
    # Copy app service
    cp config/kiosk-app.service /mnt/root/etc/init.d/kiosk-app
    chmod +x /mnt/root/etc/init.d/kiosk-app
    
    # Enable service
    chroot /mnt/root rc-update add kiosk-app default
    
    log_info "Kiosk app service configured"
}

# Setup watchdog
setup_watchdog() {
    log_step "Setting Up Kiosk Watchdog"
    
    # Copy browser service
    cp config/kiosk-browser.service /mnt/root/etc/init.d/kiosk-browser
    chmod +x /mnt/root/etc/init.d/kiosk-browser
    
    # Copy browser script
    cp config/kiosk-browser.sh /mnt/root/opt/kiosk-browser.sh
    chmod +x /mnt/root/opt/kiosk-browser.sh
    
    # Copy health check script
    cp config/kiosk-health-check.sh /mnt/root/opt/kiosk-health-check.sh
    chmod +x /mnt/root/opt/kiosk-health-check.sh
    
    # Enable browser service
    chroot /mnt/root rc-update add kiosk-browser default
    
    # Add health check to crontab
    echo "*/2 * * * * /opt/kiosk-health-check.sh" | chroot /mnt/root crontab -
    
    log_info "Watchdog service configured"
}

# Setup auto-update
setup_auto_update() {
    log_step "Setting Up Auto Update Service"
    
    # Copy auto-update service
    cp config/auto-update.service /mnt/root/etc/init.d/auto-update
    chmod +x /mnt/root/etc/init.d/auto-update
    
    # Copy auto-update script
    cp config/auto-update.sh /mnt/root/opt/auto-update.sh
    chmod +x /mnt/root/opt/auto-update.sh
    
    # Enable auto-update service
    chroot /mnt/root rc-update add auto-update default
    
    # Add auto-update to crontab (daily at 3 AM)
    echo "0 3 * * * /opt/auto-update.sh" | chroot /mnt/root crontab -
    
    log_info "Auto-update service configured"
}

# Setup screensaver
setup_screensaver() {
    log_step "Setting Up Screensaver Service"
    
    # Copy screensaver service
    cp config/screensaver.service /mnt/root/etc/init.d/screensaver
    chmod +x /mnt/root/etc/init.d/screensaver
    
    # Copy screensaver HTML
    cp config/screensaver.html /mnt/root/opt/screensaver.html
    
    # Copy screensaver control script
    cp config/screensaver-control.sh /mnt/root/opt/screensaver-control.sh
    chmod +x /mnt/root/opt/screensaver-control.sh
    
    # Enable screensaver service
    chroot /mnt/root rc-update add screensaver default
    
    # Add screensaver check to crontab (every 5 minutes)
    echo "*/5 * * * * /opt/screensaver-control.sh" | chroot /mnt/root crontab -
    
    log_info "Screensaver service configured"
}

# Setup kiosk CLI
setup_kiosk_cli() {
    log_step "Setting Up Kiosk Management CLI"
    
    # Copy kiosk CLI script
    cp config/kiosk-cli.sh /mnt/root/usr/local/bin/kiosk
    chmod +x /mnt/root/usr/local/bin/kiosk
    
    log_info "Kiosk CLI configured"
}

# Setup boot logo
setup_boot_logo() {
    log_step "Setting Up Route 19 Boot Logo"
    
    # Create boot logo directory
    mkdir -p /mnt/root/usr/share/kioskbook
    
    # Copy Route 19 logo if available
    if [ -f "route19-logo.png" ]; then
        cp route19-logo.png /mnt/root/usr/share/kioskbook/route19-logo.png
        log_info "Route 19 logo copied to system"
    else
        log_warning "Route 19 logo not found, creating placeholder"
        # Create a simple placeholder logo
        chroot /mnt/root convert -size 200x200 xc:blue -pointsize 24 -fill white -gravity center -annotate +0+0 "Route 19" /usr/share/kioskbook/route19-logo.png
    fi
    
    # Create boot logo with Route 19 on black background
    chroot /mnt/root convert /usr/share/kioskbook/route19-logo.png \
        -resize 800x600 \
        -background black \
        -gravity center \
        -extent 1024x768 \
        /usr/share/kioskbook/route19-boot-logo.png
    
    # Create simple boot logo for framebuffer display
    chroot /mnt/root convert /usr/share/kioskbook/route19-logo.png \
        -resize 640x480 \
        -background black \
        -gravity center \
        -extent 640x480 \
        /usr/share/kioskbook/route19-fb-logo.png
    
    # Copy boot splash script
    cp config/boot-splash.sh /mnt/root/usr/share/kioskbook/boot-splash.sh
    chmod +x /mnt/root/usr/share/kioskbook/boot-splash.sh
    
    # Copy startup script
    cp config/route19-startup.start /mnt/root/etc/local.d/route19-startup.start
    chmod +x /mnt/root/etc/local.d/route19-startup.start
    
    log_info "Route 19 boot logo configured"
}

# Setup Tailscale
setup_tailscale() {
    log_step "Setting Up Tailscale"
    
    # Copy Tailscale configuration
    cp config/tailscaled.conf /mnt/root/etc/conf.d/tailscaled
    
    # Copy Tailscale auth script (only if auth key provided)
    if [ -n "$TAILSCALE_KEY" ]; then
        cp config/tailscale-auth.start /mnt/root/etc/local.d/tailscale-auth.start
        sed -i "s/TAILSCALE_KEY/$TAILSCALE_KEY/g" /mnt/root/etc/local.d/tailscale-auth.start
        chmod +x /mnt/root/etc/local.d/tailscale-auth.start
    else
        log_info "Tailscale auth script not created - authenticate manually later"
    fi
    
    # Enable Tailscale
    chroot /mnt/root rc-update add tailscaled default
    
    log_info "Tailscale configured"
}

# Setup services
setup_services() {
    log_step "Setting Up Services"
    
    # Enable essential services
    chroot /mnt/root rc-update add networking default
    chroot /mnt/root rc-update add sshd default
    chroot /mnt/root rc-update add local default
    
    log_info "Services configured"
}

# Main installation function
main() {
    show_banner
    validate_environment
    get_configuration
    
    log_step "Starting KioskBook Installation"
    
    prepare_disk
    install_system
    setup_network
    setup_fstab
    setup_boot
    setup_kiosk_user
    setup_kiosk_app
    setup_watchdog
    setup_auto_update
    setup_screensaver
    setup_kiosk_cli
    setup_boot_logo
    setup_tailscale
    setup_services
    
    log_info "KioskBook installation completed successfully!"
    echo
    echo -e "${GREEN}KIOSKBOOK INSTALLATION SUCCESSFUL!${NC}"
    echo
    echo "Your kiosk is ready to use:"
    echo "- Hostname: kioskbook"
    echo "- Kiosk App: $GITHUB_REPO"
    echo "- Tailscale: Enabled (Required)"
    echo "- Watchdog: Enabled"
    echo "- Auto-update: Enabled"
    echo "- Screensaver: Enabled (11 PM - 7 AM)"
    echo "- Management CLI: kiosk command"
    echo
    echo "The system will reboot in 10 seconds..."
    sleep 10
    reboot
}

# Run main function
main "$@"