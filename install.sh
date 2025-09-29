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

# Install minimal Alpine system manually
install_minimal_alpine() {
    log_step "Installing Minimal Alpine Linux"
    
    # Mount the partitions we already created
    log_info "Mounting target partitions..."
    mount "$ROOT_PARTITION" /mnt/root
    mount "$EFI_PARTITION" /mnt/root/boot
    
    # Copy minimal Alpine system from the running environment
    log_info "Installing minimal Alpine system..."
    
    # Create basic directory structure
    mkdir -p /mnt/root/{dev,proc,sys,run,tmp,var,home,opt,usr,etc}
    mkdir -p /mnt/root/var/{log,lib,cache,lock,tmp}
    mkdir -p /mnt/root/usr/{bin,sbin,lib,share}
    mkdir -p /mnt/root/etc/{init.d,conf.d,runlevels,network,apk}
    mkdir -p /mnt/root/etc/runlevels/{default,boot,sysinit,shutdown}
    
    # Copy essential system files
    log_info "Copying system files..."
    cp -a /bin /mnt/root/
    cp -a /sbin /mnt/root/
    cp -a /lib /mnt/root/
    cp -a /usr/bin /mnt/root/usr/
    cp -a /usr/sbin /mnt/root/usr/
    cp -a /usr/lib /mnt/root/usr/
    cp -a /usr/share /mnt/root/usr/
    
    # Copy essential configuration
    cp /etc/passwd /mnt/root/etc/
    cp /etc/group /mnt/root/etc/
    cp /etc/shadow /mnt/root/etc/
    cp /etc/hosts /mnt/root/etc/
    cp /etc/resolv.conf /mnt/root/etc/
    cp /etc/fstab /mnt/root/etc/ 2>/dev/null || true
    
    # Copy OpenRC configuration
    if [ -d /etc/init.d ]; then
        cp -a /etc/init.d/* /mnt/root/etc/init.d/ 2>/dev/null || true
    fi
    if [ -d /etc/conf.d ]; then
        cp -a /etc/conf.d/* /mnt/root/etc/conf.d/ 2>/dev/null || true
    fi
    
    # Set up package management
    log_info "Setting up package management..."
    mkdir -p /mnt/root/etc/apk
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/main" > /mnt/root/etc/apk/repositories
    echo "https://dl-cdn.alpinelinux.org/alpine/v3.22/community" >> /mnt/root/etc/apk/repositories
    
    # Copy apk cache if available
    if [ -d /var/cache/apk ]; then
        mkdir -p /mnt/root/var/cache/apk
        cp -a /var/cache/apk/* /mnt/root/var/cache/apk/ 2>/dev/null || true
    fi
    
    # Create basic fstab
    cat > /mnt/root/etc/fstab << EOF
$ROOT_PARTITION / ext4 rw,relatime 0 1
$EFI_PARTITION /boot vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro 0 2
tmpfs /tmp tmpfs nosuid,nodev,noexec 0 0
EOF
    
    # Set hostname
    echo "kioskbook" > /mnt/root/etc/hostname
    
    # Create network configuration
    cat > /mnt/root/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    # Set root password
    log_info "Setting passwords..."
    echo "root:$ROOT_PASSWORD" | chroot /mnt/root chpasswd 2>/dev/null || {
        # Manual password setting if chpasswd fails
        ENCRYPTED_PASS=$(openssl passwd -1 "$ROOT_PASSWORD")
        sed -i "s|^root:[^:]*:|root:$ENCRYPTED_PASS:|" /mnt/root/etc/shadow
    }
    
    # Create kiosk user
    log_info "Creating kiosk user..."
    echo "kiosk:x:1000:1000:Kiosk User:/home/kiosk:/bin/sh" >> /mnt/root/etc/passwd
    echo "kiosk:x:1000:" >> /mnt/root/etc/group
    mkdir -p /mnt/root/home/kiosk
    echo "kiosk:$ROOT_PASSWORD" | chroot /mnt/root chpasswd 2>/dev/null || {
        ENCRYPTED_PASS=$(openssl passwd -1 "$ROOT_PASSWORD")
        echo "kiosk:$ENCRYPTED_PASS:1::99999:7:::" >> /mnt/root/etc/shadow
    }
    
    # Add kiosk to wheel group for sudo
    sed -i 's/^wheel:.*/&kiosk/' /mnt/root/etc/group
    
    # Enable essential services
    log_info "Configuring services..."
    for service in hostname networking sshd local; do
        if [ -f "/mnt/root/etc/init.d/$service" ]; then
            chroot /mnt/root rc-update add "$service" default 2>/dev/null || true
        fi
    done
    
    # Create a simple bootloader
    log_info "Setting up basic bootloader..."
    mkdir -p /mnt/root/boot/EFI/BOOT
    
    # Copy kernel and initramfs if they exist
    if [ -f /boot/vmlinuz-lts ]; then
        cp /boot/vmlinuz-lts /mnt/root/boot/
    fi
    if [ -f /boot/initramfs-lts ]; then
        cp /boot/initramfs-lts /mnt/root/boot/
    fi
    
    log_info "Minimal Alpine installation completed"
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

# Setup boot (simplified - use what's available on ISO)
setup_boot() {
    log_step "Setting Up Boot Configuration"
    
    # Check if we have a bootloader already installed by setup-alpine
    if [ -f "/mnt/root/boot/vmlinuz-lts" ]; then
        log_info "Bootloader already configured by setup-alpine"
        return 0
    fi
    
    # Simple EFI boot setup using available tools
    log_info "Setting up minimal EFI boot..."
    
    # Create EFI directory structure
    mkdir -p /mnt/root/boot/EFI/BOOT
    
    # Try to install bootloader if syslinux is available
    if chroot /mnt/root which syslinux >/dev/null 2>&1; then
        # Use syslinux if available
        cp /mnt/root/usr/share/syslinux/efi64/syslinux.efi /mnt/root/boot/EFI/BOOT/BOOTX64.EFI 2>/dev/null || {
            log_warning "Could not copy syslinux EFI bootloader"
        }
    else
        log_warning "No bootloader available - system may not boot properly"
        log_info "You may need to install a bootloader manually after the system boots"
    fi
    
    # Create basic boot configuration if kernel exists
    if [ -f "/mnt/root/boot/vmlinuz-lts" ]; then
        mkdir -p /mnt/root/boot/syslinux
        cat > /mnt/root/boot/syslinux/syslinux.cfg << EOF
DEFAULT linux
LABEL linux
  KERNEL /vmlinuz-lts
  APPEND initrd=/initramfs-lts root=$ROOT_PARTITION rw quiet
EOF
    fi
    
    log_info "Boot configuration completed (minimal)"
}

# Setup post-install script
setup_post_install_script() {
    log_step "Setting Up Post-Install Script"
    
    # Download and place post-install script
    log_info "Creating post-install script..."
    
    cat > /mnt/root/root/post-install.sh << 'EOF'
#!/bin/sh
# KioskBook Post-Install Configuration
# Run this after first boot to complete kiosk setup

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

echo -e "${CYAN}KioskBook Post-Install Configuration${NC}"
echo "===================================="
echo

# Update package repositories
log_step "Updating package repositories"
apk update

# Install kiosk packages
log_step "Installing kiosk packages"
apk add nodejs npm chromium xorg-server xf86-video-fbdev xf86-input-evdev xset git curl wget

# Install Tailscale
log_step "Installing Tailscale"
curl -fsSL https://tailscale.com/install.sh | sh
rc-update add tailscaled default

# Clone kiosk application
log_step "Setting up kiosk application"
mkdir -p /opt/kiosk-app
cd /opt/kiosk-app

# Get GitHub repo from install time (will be replaced)
GITHUB_URL="GITHUB_URL_PLACEHOLDER"
if [ "$GITHUB_URL" != "GITHUB_URL_PLACEHOLDER" ]; then
    git clone "$GITHUB_URL" .
    if [ -f package.json ]; then
        npm install
    fi
fi

# Create kiosk startup service
cat > /etc/init.d/kiosk-app << 'EOFSERVICE'
#!/sbin/openrc-run

name="kiosk-app"
description="KioskBook Application"
command="/opt/kiosk-app/start.sh"
command_user="kiosk"
pidfile="/var/run/kiosk-app.pid"
command_background="yes"

depend() {
    need net
    after networking
}
EOFSERVICE

chmod +x /etc/init.d/kiosk-app
rc-update add kiosk-app default

# Create startup script
cat > /opt/kiosk-app/start.sh << 'EOFSTART'
#!/bin/sh
export DISPLAY=:0
cd /opt/kiosk-app
if [ -f package.json ]; then
    npm start
else
    echo "No package.json found - manual configuration needed"
fi
EOFSTART

chmod +x /opt/kiosk-app/start.sh
chown -R kiosk:kiosk /opt/kiosk-app

log_info "Post-install configuration completed!"
log_info "System is ready for kiosk operation"
EOF

    chmod +x /mnt/root/root/post-install.sh
    
    # Replace GitHub URL placeholder
    sed -i "s|GITHUB_URL_PLACEHOLDER|$GITHUB_URL|g" /mnt/root/root/post-install.sh
    
    # Create autorun script for first boot
    cat > /mnt/root/etc/local.d/post-install.start << 'EOF'
#!/bin/sh
# Auto-run post-install script on first boot
if [ -f /root/post-install.sh ] && [ ! -f /root/.post-install-complete ]; then
    /root/post-install.sh
    touch /root/.post-install-complete
fi
EOF
    
    chmod +x /mnt/root/etc/local.d/post-install.start
    
    log_info "Post-install script configured"
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
    install_minimal_alpine
    setup_post_install_script
    
    log_info "KioskBook base installation completed successfully!"
    echo
    echo -e "${GREEN}KIOSKBOOK BASE INSTALLATION SUCCESSFUL!${NC}"
    echo
    echo "Base Alpine Linux system installed:"
    echo "- Hostname: kioskbook"
    echo "- Root and kiosk users created"
    echo "- SSH enabled"
    echo "- Post-install script ready"
    echo
    echo "The system will reboot and complete kiosk setup automatically."
    echo "Kiosk app: $GITHUB_REPO"
    echo
    echo -e "${YELLOW}IMPORTANT: Remove the USB installer before reboot!${NC}"
    echo
    echo -n "Remove USB drive and press Enter to reboot..."
    read
    reboot
}

# Run main function
main "$@"