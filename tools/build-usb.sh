#!/bin/bash

set -e

# KioskBook USB Builder - Creates bootable installer USB drives
# This script creates a bootable USB drive with Debian and KioskBook installer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default configuration
USB_DEVICE=""
DEBIAN_ISO=""
AUTO_DOWNLOAD="${AUTO_DOWNLOAD:-true}"
DEBIAN_VERSION="${DEBIAN_VERSION:-13}"
DEBIAN_ARCH="${DEBIAN_ARCH:-amd64}"
WORK_DIR="${WORK_DIR:-$PROJECT_DIR/usb-build}"
FORCE="${FORCE:-false}"

# URLs for Debian images
DEBIAN_MIRROR="https://cdimage.debian.org/debian-cd/current"
DEBIAN_ISO_NAME="debian-${DEBIAN_VERSION}.0.0-${DEBIAN_ARCH}-netinst.iso"
DEBIAN_ISO_URL="${DEBIAN_MIRROR}/${DEBIAN_ARCH}/iso-cd/${DEBIAN_ISO_NAME}"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] USB_DEVICE

Creates a bootable USB drive with Debian installer and KioskBook automation.

ARGUMENTS:
    USB_DEVICE          USB device path (e.g., /dev/sdb, /dev/disk2)

OPTIONS:
    --iso PATH          Use specific Debian ISO file
    --no-download       Don't auto-download Debian ISO
    --debian-version N  Debian version (default: 13)
    --arch ARCH         Architecture (default: amd64)
    --work-dir PATH     Working directory (default: ./usb-build)
    --force             Overwrite USB device without confirmation
    --help              Show this help

EXAMPLES:
    # Auto-download and create USB (will prompt for device confirmation)
    $0 /dev/sdb

    # Use existing ISO file
    $0 --iso debian-13-amd64-netinst.iso /dev/sdb

    # Force overwrite without confirmation
    $0 --force /dev/sdb

PREREQUISITES:
    Linux: Install syslinux, dosfstools, parted
        Ubuntu/Debian: sudo apt install syslinux dosfstools parted
        RHEL/CentOS: sudo yum install syslinux dosfstools parted

    macOS: Install GNU coreutils, dosfstools via Homebrew
        brew install coreutils dosfstools

WARNING:
    This will COMPLETELY ERASE the target USB device!
    Double-check the device path before proceeding.

FEATURES:
    - Debian 13 (trixie) netinst installer
    - Automated preseed configuration for minimal install
    - Node.js 22.x pre-installation
    - KioskBook installer auto-launch post-install
    - UEFI and BIOS boot support
EOF
}

check_requirements() {
    echo "Checking requirements..."
    
    local missing_tools=()
    
    # Check for required tools
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        command -v syslinux >/dev/null 2>&1 || missing_tools+=("syslinux")
        command -v mkfs.fat >/dev/null 2>&1 || missing_tools+=("dosfstools")
        command -v parted >/dev/null 2>&1 || missing_tools+=("parted")
        command -v mount >/dev/null 2>&1 || missing_tools+=("mount")
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        command -v mkfs.fat >/dev/null 2>&1 || missing_tools+=("dosfstools")
        command -v gdisk >/dev/null 2>&1 || missing_tools+=("gdisk")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing_tools[*]}"
        echo ""
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "Install with: sudo apt install ${missing_tools[*]}"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Install with: brew install ${missing_tools[*]}"
        fi
        exit 1
    fi
    
    # Check for root privileges
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script requires root privileges to write to USB devices."
        echo "Run with: sudo $0 $*"
        exit 1
    fi
    
    echo "✓ All requirements met"
}

validate_usb_device() {
    if [[ -z "$USB_DEVICE" ]]; then
        echo "Error: No USB device specified"
        usage
        exit 1
    fi
    
    if [[ ! -b "$USB_DEVICE" ]]; then
        echo "Error: $USB_DEVICE is not a block device"
        echo ""
        echo "Available devices:"
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            lsblk -d -o NAME,SIZE,MODEL | grep -E "(sd[b-z]|nvme)"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            diskutil list | grep -E "disk[1-9]"
        fi
        exit 1
    fi
    
    # Get device info
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        local device_info=$(lsblk -n -o SIZE,MODEL "$USB_DEVICE" 2>/dev/null || echo "Unknown Unknown")
        local device_size=$(echo "$device_info" | awk '{print $1}')
        local device_model=$(echo "$device_info" | cut -d' ' -f2-)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        local device_info=$(diskutil info "$USB_DEVICE" 2>/dev/null || echo "")
        local device_size=$(echo "$device_info" | grep "Disk Size" | awk '{print $3 $4}')
        local device_model=$(echo "$device_info" | grep "Device / Media Name" | cut -d: -f2- | xargs)
    fi
    
    echo "Target USB device: $USB_DEVICE"
    echo "Size: ${device_size:-Unknown}"
    echo "Model: ${device_model:-Unknown}"
    echo ""
    
    if [[ "$FORCE" != "true" ]]; then
        echo "WARNING: This will COMPLETELY ERASE all data on $USB_DEVICE!"
        echo "Are you sure you want to continue? (yes/no)"
        read -r response
        if [[ "$response" != "yes" ]]; then
            echo "Aborted."
            exit 1
        fi
    fi
}

download_debian_iso() {
    if [[ -n "$DEBIAN_ISO" ]]; then
        if [[ ! -f "$DEBIAN_ISO" ]]; then
            echo "Error: Specified ISO file not found: $DEBIAN_ISO"
            exit 1
        fi
        echo "Using specified ISO: $DEBIAN_ISO"
        return
    fi
    
    DEBIAN_ISO="$WORK_DIR/$DEBIAN_ISO_NAME"
    
    if [[ -f "$DEBIAN_ISO" ]]; then
        echo "Using existing ISO: $DEBIAN_ISO"
        return
    fi
    
    if [[ "$AUTO_DOWNLOAD" != "true" ]]; then
        echo "Error: No ISO specified and auto-download disabled"
        echo "Either specify --iso or enable auto-download"
        exit 1
    fi
    
    echo "Downloading Debian $DEBIAN_VERSION $DEBIAN_ARCH installer..."
    mkdir -p "$WORK_DIR"
    
    if command -v wget >/dev/null 2>&1; then
        wget -O "$DEBIAN_ISO" "$DEBIAN_ISO_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o "$DEBIAN_ISO" "$DEBIAN_ISO_URL"
    else
        echo "Error: Neither wget nor curl available for downloading"
        exit 1
    fi
    
    echo "✓ Downloaded: $DEBIAN_ISO"
}

create_preseed_config() {
    local preseed_file="$1"
    
    cat > "$preseed_file" << 'EOF'
# KioskBook Preseed Configuration
# Automated installation for minimal Debian system

# Localization
d-i debian-installer/language string en
d-i debian-installer/country string US
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

# Network configuration
d-i netcfg/choose_interface select auto
d-i netcfg/dhcp_timeout string 60
d-i netcfg/get_hostname string kioskbook
d-i netcfg/get_domain string local

# Mirror settings
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# Account setup
d-i passwd/root-login boolean true
d-i passwd/root-password password kioskbook
d-i passwd/root-password-again password kioskbook
d-i passwd/user-fullname string Kiosk User
d-i passwd/username string kiosk
d-i passwd/user-password password kioskbook
d-i passwd/user-password-again password kioskbook

# Clock and time zone setup
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i clock-setup/ntp boolean true

# Partitioning
d-i partman-auto/method string regular
d-i partman-auto/disk string /dev/sda
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# Package selection
tasksel tasksel/first multiselect
d-i pkgsel/include string openssh-server sudo curl wget git build-essential
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false

# GRUB bootloader
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default

# Finish installation
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/poweroff boolean true

# Late command to install Node.js and prepare for KioskBook
d-i preseed/late_command string \
    in-target curl -fsSL https://deb.nodesource.com/setup_22.x | bash - ; \
    in-target apt-get install -y nodejs ; \
    in-target wget -O /root/kioskbook-install.sh https://raw.githubusercontent.com/kenzie/kioskbook/main/install.sh ; \
    in-target chmod +x /root/kioskbook-install.sh
EOF
}

create_usb_installer() {
    echo "Creating bootable USB installer..."
    
    # Unmount any existing partitions
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        umount "${USB_DEVICE}"* 2>/dev/null || true
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        diskutil unmountDisk "$USB_DEVICE" 2>/dev/null || true
    fi
    
    # Create partition table and boot partition
    echo "Creating partition table..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        parted -s "$USB_DEVICE" mklabel gpt
        parted -s "$USB_DEVICE" mkpart primary fat32 1MiB 100%
        parted -s "$USB_DEVICE" set 1 boot on
        parted -s "$USB_DEVICE" set 1 esp on
        
        # Wait for device to be ready
        sleep 2
        partprobe "$USB_DEVICE"
        sleep 2
        
        local usb_partition="${USB_DEVICE}1"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        diskutil partitionDisk "$USB_DEVICE" GPT FAT32 "KIOSKBOOK" 100%
        local usb_partition="${USB_DEVICE}s1"
    fi
    
    # Format partition
    echo "Formatting USB partition..."
    mkfs.fat -F32 -n "KIOSKBOOK" "$usb_partition"
    
    # Mount partition
    local mount_point="/tmp/kioskbook-usb-$$"
    mkdir -p "$mount_point"
    mount "$usb_partition" "$mount_point"
    
    # Extract ISO contents
    echo "Extracting Debian ISO..."
    local iso_mount="/tmp/kioskbook-iso-$$"
    mkdir -p "$iso_mount"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        mount -o loop "$DEBIAN_ISO" "$iso_mount"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        hdiutil attach "$DEBIAN_ISO" -mountpoint "$iso_mount" -quiet
    fi
    
    # Copy ISO contents to USB
    cp -R "$iso_mount"/* "$mount_point"/
    
    # Create preseed configuration
    echo "Adding KioskBook preseed configuration..."
    mkdir -p "$mount_point/preseed"
    create_preseed_config "$mount_point/preseed/kioskbook.cfg"
    
    # Modify isolinux/syslinux for auto-boot
    if [[ -f "$mount_point/isolinux/isolinux.cfg" ]]; then
        sed -i.bak 's/timeout 0/timeout 30/' "$mount_point/isolinux/isolinux.cfg"
        echo "" >> "$mount_point/isolinux/isolinux.cfg"
        echo "label kioskbook" >> "$mount_point/isolinux/isolinux.cfg"
        echo "  menu label ^KioskBook Automated Install" >> "$mount_point/isolinux/isolinux.cfg"
        echo "  kernel /install.amd/vmlinuz" >> "$mount_point/isolinux/isolinux.cfg"
        echo "  append initrd=/install.amd/initrd.gz preseed/file=/cdrom/preseed/kioskbook.cfg debian-installer/allow_unauthenticated_ssl=true" >> "$mount_point/isolinux/isolinux.cfg"
    fi
    
    # Add UEFI boot configuration
    if [[ -d "$mount_point/EFI/boot" ]]; then
        cat >> "$mount_point/boot/grub/grub.cfg" << 'EOF'

menuentry "KioskBook Automated Install" {
    linux /install.amd/vmlinuz preseed/file=/cdrom/preseed/kioskbook.cfg debian-installer/allow_unauthenticated_ssl=true
    initrd /install.amd/initrd.gz
}
EOF
    fi
    
    # Install bootloader
    echo "Installing bootloader..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Install syslinux for BIOS boot
        syslinux "$usb_partition"
        dd if=/usr/lib/syslinux/mbr/gptmbr.bin of="$USB_DEVICE" bs=440 count=1 conv=notrunc
    fi
    
    # Cleanup
    sync
    umount "$mount_point"
    rmdir "$mount_point"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        umount "$iso_mount"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        hdiutil detach "$iso_mount" -quiet
    fi
    rmdir "$iso_mount"
    
    echo "✓ Bootable USB created successfully!"
    echo ""
    echo "USB device: $USB_DEVICE"
    echo "Boot options:"
    echo "  - Standard Debian installer"
    echo "  - KioskBook Automated Install (with preseed)"
    echo ""
    echo "Default credentials:"
    echo "  - Root password: kioskbook"
    echo "  - User: kiosk / Password: kioskbook"
    echo ""
    echo "After installation, run: /root/kioskbook-install.sh"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --iso)
            DEBIAN_ISO="$2"
            shift 2
            ;;
        --no-download)
            AUTO_DOWNLOAD="false"
            shift
            ;;
        --debian-version)
            DEBIAN_VERSION="$2"
            shift 2
            ;;
        --arch)
            DEBIAN_ARCH="$2"
            shift 2
            ;;
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$USB_DEVICE" ]]; then
                USB_DEVICE="$1"
            else
                echo "Extra argument: $1"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Main execution
echo "KioskBook USB Builder"
echo "===================="
echo ""

check_requirements
validate_usb_device
download_debian_iso
create_usb_installer

echo ""
echo "USB installer creation complete!"
echo "You can now boot from this USB to install Debian with KioskBook automation."