#!/bin/bash
#
# 00-partition.sh - Disk Partitioning Module
#
# Handles disk partitioning and filesystem setup for Alpine Linux kiosk.
# Creates optimized partition layout for fast boot and reliable operation.
#
# Partition Layout:
# - 100MB boot partition (ext4) - BOOT
# - 2GB root partition (ext4) - ROOT  
# - Remainder data partition (ext4) - DATA
#

set -e
set -o pipefail

# Import logging functions from main installer
source /dev/stdin <<< "$(declare -f log log_success log_warning log_error log_info)"

# Module configuration
MODULE_NAME="00-partition"
BOOT_SIZE="100MiB"
ROOT_SIZE="2GiB"

# Partition device paths (will be set based on TARGET_DISK)
BOOT_PARTITION=""
ROOT_PARTITION="" 
DATA_PARTITION=""

# Mount points
MOUNT_ROOT="/mnt"
MOUNT_BOOT="/mnt/boot"
MOUNT_DATA="/mnt/data"

log_info "Starting disk partitioning module..."

# Validate required variables
validate_environment() {
    if [[ -z "$TARGET_DISK" ]]; then
        log_error "TARGET_DISK not set. Module must be called from main installer."
        exit 1
    fi
    
    if [[ ! -b "$TARGET_DISK" ]]; then
        log_error "Target disk $TARGET_DISK is not a valid block device"
        exit 1
    fi
    
    log_info "Target disk: $TARGET_DISK"
}

# Set partition device paths based on disk type
set_partition_paths() {
    if [[ "$TARGET_DISK" == *"nvme"* ]]; then
        # NVMe devices use p prefix (e.g., /dev/nvme0n1p1)
        BOOT_PARTITION="${TARGET_DISK}p1"
        ROOT_PARTITION="${TARGET_DISK}p2"
        DATA_PARTITION="${TARGET_DISK}p3"
    else
        # SATA/SCSI devices use direct numbering (e.g., /dev/sda1)
        BOOT_PARTITION="${TARGET_DISK}1"
        ROOT_PARTITION="${TARGET_DISK}2"
        DATA_PARTITION="${TARGET_DISK}3"
    fi
    
    log_info "Partition layout:"
    log_info "  Boot: $BOOT_PARTITION ($BOOT_SIZE)"
    log_info "  Root: $ROOT_PARTITION ($ROOT_SIZE)"
    log_info "  Data: $DATA_PARTITION (remainder)"
}

# Check if required tools are available
check_required_tools() {
    local tools=("parted" "mkfs.ext4" "blkid" "wipefs")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            log_info "Installing missing tools..."
            apk add --no-cache parted e2fsprogs util-linux || {
                log_error "Failed to install required tools"
                exit 1
            }
            break
        fi
    done
    
    log_success "All required tools available"
}

# Get disk information for safety checks
get_disk_info() {
    local disk="$1"
    local size_bytes size_gb model serial
    
    size_bytes=$(blockdev --getsize64 "$disk" 2>/dev/null || echo "0")
    size_gb=$((size_bytes / 1024 / 1024 / 1024))
    
    # Try to get disk model and serial for identification
    model=$(lsblk -no MODEL "$disk" 2>/dev/null | tr -d ' ' || echo "Unknown")
    serial=$(lsblk -no SERIAL "$disk" 2>/dev/null | tr -d ' ' || echo "Unknown")
    
    echo "Disk: $disk"
    echo "Size: ${size_gb}GB"
    echo "Model: $model"
    echo "Serial: $serial"
}

# Safety confirmation before wiping disk
confirm_disk_wipe() {
    local disk_info
    disk_info=$(get_disk_info "$TARGET_DISK")
    
    echo ""
    log_warning "DANGER: About to completely wipe disk!"
    echo ""
    echo "$disk_info"
    echo ""
    log_error "ALL DATA ON $TARGET_DISK WILL BE PERMANENTLY LOST!"
    echo ""
    
    # Double confirmation for safety
    read -p "Type 'WIPE' to confirm disk destruction: " confirm1
    if [[ "$confirm1" != "WIPE" ]]; then
        log_info "Disk wipe cancelled by user"
        exit 1
    fi
    
    read -p "Type 'YES' to proceed with partitioning: " confirm2
    if [[ "$confirm2" != "YES" ]]; then
        log_info "Disk wipe cancelled by user"
        exit 1
    fi
    
    log_warning "Proceeding with disk wipe in 3 seconds..."
    sleep 3
}

# Wipe disk and existing partition table
wipe_disk() {
    log_info "Wiping existing partition table and filesystem signatures..."
    
    # Unmount any existing partitions
    for part in "${TARGET_DISK}"*; do
        if [[ -b "$part" ]] && mountpoint -q "$part" 2>/dev/null; then
            log_info "Unmounting $part"
            umount "$part" || log_warning "Failed to unmount $part"
        fi
    done
    
    # Wipe filesystem signatures
    wipefs -af "$TARGET_DISK" || {
        log_error "Failed to wipe filesystem signatures"
        exit 1
    }
    
    # Zero out the first and last few MB to ensure clean slate
    log_info "Zeroing disk headers..."
    dd if=/dev/zero of="$TARGET_DISK" bs=1M count=10 status=none || {
        log_error "Failed to zero disk beginning"
        exit 1
    }
    
    # Get disk size for zeroing the end
    local disk_size_sectors
    disk_size_sectors=$(blockdev --getsz "$TARGET_DISK")
    local end_sectors=$((disk_size_sectors - 2048))  # Leave 1MB at end
    
    if [[ $end_sectors -gt 2048 ]]; then
        dd if=/dev/zero of="$TARGET_DISK" bs=512 count=2048 seek=$end_sectors status=none || {
            log_warning "Failed to zero disk end (non-critical)"
        }
    fi
    
    # Force kernel to re-read partition table
    partprobe "$TARGET_DISK" 2>/dev/null || true
    sleep 2
    
    log_success "Disk wiped successfully"
    
    # Add rollback action
    add_rollback "log_warning 'Disk wipe completed - no rollback possible'"
}

# Create GPT partition table
create_partition_table() {
    log_info "Creating GPT partition table..."
    
    parted -s "$TARGET_DISK" mklabel gpt || {
        log_error "Failed to create GPT partition table"
        exit 1
    }
    
    log_success "GPT partition table created"
}

# Create partitions
create_partitions() {
    log_info "Creating partitions..."
    
    # Create boot partition (100MB)
    log_info "Creating boot partition ($BOOT_SIZE)..."
    parted -s "$TARGET_DISK" mkpart primary ext4 1MiB $BOOT_SIZE || {
        log_error "Failed to create boot partition"
        exit 1
    }
    
    # Create root partition (2GB) 
    log_info "Creating root partition ($ROOT_SIZE)..."
    local root_end=$((100 + 2048))  # 100MB + 2048MB
    parted -s "$TARGET_DISK" mkpart primary ext4 $BOOT_SIZE ${root_end}MiB || {
        log_error "Failed to create root partition"
        exit 1
    }
    
    # Create data partition (remainder)
    log_info "Creating data partition (remainder)..."
    parted -s "$TARGET_DISK" mkpart primary ext4 ${root_end}MiB 100% || {
        log_error "Failed to create data partition"
        exit 1
    }
    
    # Set boot flag on first partition
    parted -s "$TARGET_DISK" set 1 boot on || {
        log_warning "Failed to set boot flag (non-critical)"
    }
    
    # Force kernel to re-read partition table
    partprobe "$TARGET_DISK" || {
        log_error "Failed to re-read partition table"
        exit 1
    }
    
    # Wait for device nodes to appear
    local retries=0
    while [[ $retries -lt 10 ]]; do
        if [[ -b "$BOOT_PARTITION" && -b "$ROOT_PARTITION" && -b "$DATA_PARTITION" ]]; then
            break
        fi
        log_info "Waiting for partition devices to appear..."
        sleep 1
        retries=$((retries + 1))
    done
    
    if [[ ! -b "$BOOT_PARTITION" || ! -b "$ROOT_PARTITION" || ! -b "$DATA_PARTITION" ]]; then
        log_error "Partition devices did not appear after creation"
        exit 1
    fi
    
    log_success "Partitions created successfully"
    
    # Show partition layout
    log_info "Partition layout:"
    parted -s "$TARGET_DISK" print || log_warning "Failed to display partition table"
}

# Format partitions
format_partitions() {
    log_info "Formatting partitions..."
    
    # Format boot partition
    log_info "Formatting boot partition as ext4..."
    mkfs.ext4 -F -L "BOOT" "$BOOT_PARTITION" || {
        log_error "Failed to format boot partition"
        exit 1
    }
    
    # Format root partition
    log_info "Formatting root partition as ext4..."
    mkfs.ext4 -F -L "ROOT" "$ROOT_PARTITION" || {
        log_error "Failed to format root partition"
        exit 1
    }
    
    # Format data partition
    log_info "Formatting data partition as ext4..."
    mkfs.ext4 -F -L "DATA" "$DATA_PARTITION" || {
        log_error "Failed to format data partition"
        exit 1
    }
    
    log_success "All partitions formatted successfully"
    
    # Show filesystem labels
    log_info "Filesystem labels:"
    blkid "$BOOT_PARTITION" "$ROOT_PARTITION" "$DATA_PARTITION" || {
        log_warning "Failed to display filesystem labels"
    }
}

# Create mount points and mount partitions
mount_partitions() {
    log_info "Creating mount points and mounting partitions..."
    
    # Unmount any existing mounts at our target directories
    for mount_point in "$MOUNT_DATA" "$MOUNT_BOOT" "$MOUNT_ROOT"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_info "Unmounting existing mount at $mount_point"
            umount "$mount_point" || {
                log_error "Failed to unmount $mount_point"
                exit 1
            }
        fi
    done
    
    # Create mount point directories
    mkdir -p "$MOUNT_ROOT" "$MOUNT_BOOT" "$MOUNT_DATA" || {
        log_error "Failed to create mount point directories"
        exit 1
    }
    
    # Mount root partition first
    log_info "Mounting root partition at $MOUNT_ROOT..."
    mount "$ROOT_PARTITION" "$MOUNT_ROOT" || {
        log_error "Failed to mount root partition"
        exit 1
    }
    
    # Create boot directory in root mount
    mkdir -p "$MOUNT_BOOT" || {
        log_error "Failed to create boot directory"
        exit 1
    }
    
    # Mount boot partition
    log_info "Mounting boot partition at $MOUNT_BOOT..."
    mount "$BOOT_PARTITION" "$MOUNT_BOOT" || {
        log_error "Failed to mount boot partition"
        exit 1
    }
    
    # Create data directory in root mount
    mkdir -p "$MOUNT_DATA" || {
        log_error "Failed to create data directory"
        exit 1
    }
    
    # Mount data partition
    log_info "Mounting data partition at $MOUNT_DATA..."
    mount "$DATA_PARTITION" "$MOUNT_DATA" || {
        log_error "Failed to mount data partition"
        exit 1
    }
    
    log_success "All partitions mounted successfully"
    
    # Add rollback actions for unmounting
    add_rollback "umount '$MOUNT_DATA' 2>/dev/null || true"
    add_rollback "umount '$MOUNT_BOOT' 2>/dev/null || true" 
    add_rollback "umount '$MOUNT_ROOT' 2>/dev/null || true"
}

# Validate mounting
validate_mounting() {
    log_info "Validating partition mounting..."
    
    # Check that all mount points are properly mounted
    local mount_checks=(
        "$MOUNT_ROOT:$ROOT_PARTITION"
        "$MOUNT_BOOT:$BOOT_PARTITION"
        "$MOUNT_DATA:$DATA_PARTITION"
    )
    
    for check in "${mount_checks[@]}"; do
        local mount_point="${check%:*}"
        local expected_device="${check#*:}"
        
        if ! mountpoint -q "$mount_point"; then
            log_error "Mount point $mount_point is not mounted"
            exit 1
        fi
        
        local actual_device
        actual_device=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null || echo "unknown")
        
        if [[ "$actual_device" != "$expected_device" ]]; then
            log_warning "Mount point $mount_point has unexpected device: $actual_device (expected: $expected_device)"
        fi
        
        # Test write access
        local test_file="$mount_point/.kioskbook_test"
        if echo "test" > "$test_file" 2>/dev/null && rm -f "$test_file" 2>/dev/null; then
            log_success "Mount point $mount_point is writable"
        else
            log_error "Mount point $mount_point is not writable"
            exit 1
        fi
    done
    
    # Display mount information
    log_info "Current mount layout:"
    df -h "$MOUNT_ROOT" "$MOUNT_BOOT" "$MOUNT_DATA" || {
        log_warning "Failed to display mount information"
    }
    
    log_success "Partition mounting validation completed"
}

# Export partition information for other modules
export_partition_info() {
    # Export partition device paths
    export BOOT_PARTITION ROOT_PARTITION DATA_PARTITION
    export MOUNT_ROOT MOUNT_BOOT MOUNT_DATA
    
    log_info "Partition information exported to environment"
}

# Main partition module execution
main() {
    log_info "=========================================="
    log_info "Module: Disk Partitioning"
    log_info "=========================================="
    
    validate_environment
    set_partition_paths
    check_required_tools
    confirm_disk_wipe
    wipe_disk
    create_partition_table
    create_partitions
    format_partitions
    mount_partitions
    validate_mounting
    export_partition_info
    
    log_success "Disk partitioning module completed successfully"
    log_info "Partitions ready for Alpine Linux installation"
}

# Execute main function
main "$@"