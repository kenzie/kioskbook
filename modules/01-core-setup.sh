#!/bin/bash
# KioskBook Core System Setup Module

# Prepare target disk
prepare_disk() {
    log_step "Preparing Target Disk: $DISK"
    
    # Validate disk exists and is not in use
    if [ ! -b "$DISK" ]; then
        log_error "Invalid disk: $DISK"
        exit 1
    fi
    
    # Check if disk is mounted
    if mount | grep -q "$DISK"; then
        log_error "Disk $DISK is currently mounted. Please unmount it first."
        exit 1
    fi
    
    # Create partition table and partitions
    log_info "Creating partition table and partitions on $DISK"
    
    # Create GPT partition table
    parted -s "$DISK" mklabel gpt
    
    # Create EFI boot partition (512MB)
    parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    
    # Create root partition (remaining space)
    parted -s "$DISK" mkpart primary ext4 513MiB 100%
    
    # Wait for partitions to be created
    sleep 2
    
    # Determine partition names based on disk type
    if [[ "$DISK" == *"nvme"* ]]; then
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
    
    # Format EFI partition
    mkfs.fat -F32 "$EFI_PARTITION"
    
    # Format root partition
    mkfs.ext4 -F "$ROOT_PARTITION"
    
    # Mount partitions
    log_info "Mounting partitions"
    
    # Create mount points
    mkdir -p /mnt/boot
    mkdir -p /mnt/root
    
    # Mount root partition
    mount "$ROOT_PARTITION" /mnt/root
    MOUNTED_PARTITIONS="$MOUNTED_PARTITIONS $ROOT_PARTITION"
    
    # Mount EFI partition
    mount "$EFI_PARTITION" /mnt/boot
    MOUNTED_PARTITIONS="$MOUNTED_PARTITIONS $EFI_PARTITION"
    
    # Create boot directory in root
    mkdir -p /mnt/root/boot
    
    # Bind mount EFI to root/boot
    mount --bind /mnt/boot /mnt/root/boot
    
    # Mark installation as started
    INSTALLATION_STARTED=true
    
    log_info "Disk preparation completed"
}

# Setup network configuration
setup_network() {
    log_step "Setting Up Network Configuration"
    
    # Configure hostname
    echo "$HOSTNAME" > /mnt/root/etc/hostname
    
    # Configure hosts file
    cat > /mnt/root/etc/hosts << EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
    
    # Configure network interfaces
    cat > /mnt/root/etc/network/interfaces << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    log_info "Network configuration completed"
}

# Setup minimal boot (no bootloader menu for kiosk)
setup_minimal_boot() {
    log_step "Setting Up Minimal Boot"
    
    # Determine partition names based on disk type
    if [[ "$DISK" == *"nvme"* ]]; then
        ROOT_PARTITION="${DISK}p2"
    else
        ROOT_PARTITION="${DISK}2"
    fi
    
    # Install minimal boot tools
    chroot /mnt/root apk add efibootmgr
    
    # Create EFI boot entry for direct boot
    chroot /mnt/root efibootmgr --create \
        --disk "$DISK" \
        --part 1 \
        --label "KioskBook" \
        --loader /EFI/BOOT/BOOTX64.EFI
    
    # Copy kernel and initramfs to EFI partition for direct boot
    cp /mnt/root/boot/vmlinuz-lts /mnt/boot/
    cp /mnt/root/boot/initramfs-lts /mnt/boot/
    
    # Create simple boot configuration
    cat > /mnt/boot/boot.cfg << EOF
# KioskBook Direct Boot Configuration
# Boots directly into Alpine Linux without menu

set timeout=0
set default=0

menuentry "KioskBook" {
    linux /vmlinuz-lts root=$ROOT_PARTITION rw quiet
    initrd /initramfs-lts
}
EOF
    
    log_info "Minimal boot configured (no boot menu)"
}

# Setup fstab
setup_fstab() {
    log_step "Setting Up Filesystem Table"
    
    # Determine partition names based on disk type
    if [[ "$DISK" == *"nvme"* ]]; then
        # NVMe partitions: nvme0n1p1, nvme0n1p2
        EFI_PARTITION="${DISK}p1"
        ROOT_PARTITION="${DISK}p2"
    else
        # SATA partitions: sda1, sda2
        EFI_PARTITION="${DISK}1"
        ROOT_PARTITION="${DISK}2"
    fi
    
    cat > /mnt/root/etc/fstab << EOF
# /etc/fstab: static file system information
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
$ROOT_PARTITION /               ext4    defaults        0       1
$EFI_PARTITION  /boot           vfat    defaults        0       2
tmpfs           /tmp            tmpfs   defaults        0       0
tmpfs           /var/tmp        tmpfs   defaults        0       0
EOF
    
    log_info "Filesystem table configured"
}

# Install kiosk system packages
install_kiosk_system() {
    log_step "Installing Kiosk System Packages"
    
    # Update package index
    chroot /mnt/root apk update
    
    # Install essential packages
    chroot /mnt/root apk add \
        linux-lts \
        linux-firmware \
        e2fsprogs \
        util-linux \
        coreutils \
        bash \
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
        jq
    
    log_info "Kiosk system packages installed"
}

# Setup kiosk user
setup_kiosk_user() {
    log_step "Setting Up Kiosk User"
    
    # Create kiosk user
    chroot /mnt/root adduser -D -s /bin/bash kiosk
    
    # Add kiosk to video group for display access
    chroot /mnt/root adduser kiosk video
    
    # Configure kiosk user home directory
    chroot /mnt/root mkdir -p /home/kiosk/.config
    chroot /mnt/root chown -R kiosk:kiosk /home/kiosk
    
    # Setup auto-login for kiosk user
    cat > /mnt/root/etc/inittab << EOF
# /etc/inittab
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
tty1::respawn:/bin/login -f kiosk
tty2::respawn:/bin/login -f kiosk
tty3::respawn:/bin/login -f kiosk
tty4::respawn:/bin/login -f kiosk
tty5::respawn:/bin/login -f kiosk
tty6::respawn:/bin/login -f kiosk
EOF
    
    # Configure kiosk user profile for auto-start X
    cat > /mnt/root/home/kiosk/.profile << EOF
# Auto-start X server for kiosk
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    startx
fi
EOF
    
    chroot /mnt/root chown kiosk:kiosk /home/kiosk/.profile
    
    log_info "Kiosk user configured"
}
