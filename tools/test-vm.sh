#!/bin/bash

set -e

# KioskBook Test VM - QEMU VM for testing Lenovo M75q-1 equivalent hardware
# This script creates a virtual machine with similar specs to the target hardware

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default configuration (Lenovo M75q-1 specs)
VM_NAME="${VM_NAME:-kioskbook-test}"
VM_MEMORY="${VM_MEMORY:-8G}"
VM_CPUS="${VM_CPUS:-4}"
VM_DISK_SIZE="${VM_DISK_SIZE:-240G}"
VM_DISK_PATH="${VM_DISK_PATH:-$PROJECT_DIR/vm-disks}"
VM_NET_BRIDGE="${VM_NET_BRIDGE:-virbr0}"

# Boot options
BOOT_ISO=""
BOOT_DISK=""
BOOT_INSTALLER=""

# Display options
DISPLAY_TYPE="${DISPLAY_TYPE:-gtk}"
VNC_PORT="${VNC_PORT:-5900}"

# GPU passthrough options
GPU_PASSTHROUGH="${GPU_PASSTHROUGH:-false}"
GPU_PCI_ID=""

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

COMMANDS:
    create      Create new VM disk image
    start       Start the VM
    install     Boot from Debian installer ISO
    test        Boot from existing disk image
    clean       Remove VM disk image

OPTIONS:
    --name NAME         VM name (default: kioskbook-test)
    --memory SIZE       Memory size (default: 8G)
    --cpus COUNT        CPU count (default: 4)
    --disk-size SIZE    Disk size for new VMs (default: 240G)
    --disk-path PATH    Directory for VM disks (default: ./vm-disks)
    --iso PATH          Boot from ISO file
    --disk PATH         Boot from existing disk image
    --display TYPE      Display type: gtk, vnc, none (default: gtk)
    --vnc-port PORT     VNC port when using VNC display (default: 5900)
    --gpu-passthrough   Enable AMD GPU passthrough (requires setup)
    --gpu-pci-id ID     PCI ID for GPU passthrough (e.g., 1002:15dd)
    --bridge NAME       Network bridge (default: virbr0)
    --help              Show this help

EXAMPLES:
    # Create new VM and boot Debian installer
    $0 --iso debian-13-amd64-netinst.iso create install

    # Test existing installation
    $0 test

    # Start VM with VNC access
    $0 --display vnc --vnc-port 5901 start

    # Test with GPU passthrough
    $0 --gpu-passthrough --gpu-pci-id 1002:15dd test

TARGET HARDWARE (Lenovo M75q-1):
    - AMD Ryzen 5 PRO 3400GE (4 cores, 8 threads)
    - 8-16GB DDR4 RAM
    - AMD Radeon Vega 11 integrated graphics
    - 238GB+ NVMe SSD
    - Gigabit Ethernet
EOF
}

check_requirements() {
    echo "Checking requirements..."
    
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        echo "Error: qemu-system-x86_64 not found. Install QEMU first."
        echo "  Ubuntu/Debian: sudo apt install qemu-system-x86"
        echo "  macOS: brew install qemu"
        exit 1
    fi
    
    if ! command -v qemu-img &> /dev/null; then
        echo "Error: qemu-img not found. Install QEMU tools."
        exit 1
    fi
    
    # Check for KVM support on Linux
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -c /dev/kvm ]]; then
            echo "✓ KVM acceleration available"
            KVM_ACCEL="-enable-kvm"
        else
            echo "⚠ KVM not available, using software emulation"
            KVM_ACCEL=""
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "✓ Using macOS hypervisor acceleration"
        KVM_ACCEL="-accel hvf"
    else
        echo "⚠ No hardware acceleration available"
        KVM_ACCEL=""
    fi
}

create_disk() {
    mkdir -p "$VM_DISK_PATH"
    local disk_file="$VM_DISK_PATH/${VM_NAME}.qcow2"
    
    if [[ -f "$disk_file" ]]; then
        echo "Error: Disk image already exists: $disk_file"
        echo "Use 'clean' command to remove it first."
        exit 1
    fi
    
    echo "Creating VM disk image: $disk_file"
    qemu-img create -f qcow2 "$disk_file" "$VM_DISK_SIZE"
    echo "✓ Created $VM_DISK_SIZE disk image"
}

build_qemu_command() {
    local boot_mode="$1"
    local disk_file="$VM_DISK_PATH/${VM_NAME}.qcow2"
    
    # Base QEMU command with Lenovo M75q-1 equivalent specs
    QEMU_CMD=(
        qemu-system-x86_64
        $KVM_ACCEL
        -machine q35
        -cpu host
        -smp "$VM_CPUS"
        -m "$VM_MEMORY"
        -device virtio-scsi-pci,id=scsi0
        -device scsi-hd,bus=scsi0.0,drive=disk0
        -drive if=none,id=disk0,file="$disk_file",format=qcow2,cache=writeback
        -device virtio-net-pci,netdev=net0
        -netdev bridge,id=net0,br="$VM_NET_BRIDGE" 2>/dev/null || 
        -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000
        -device ich9-intel-hda
        -device hda-duplex
        -rtc base=utc,clock=host
        -no-reboot
    )
    
    # Display configuration
    case "$DISPLAY_TYPE" in
        gtk)
            QEMU_CMD+=(-display gtk,gl=on)
            ;;
        vnc)
            QEMU_CMD+=(-display vnc=:"$((VNC_PORT - 5900))")
            echo "VNC access: localhost:$VNC_PORT"
            ;;
        none)
            QEMU_CMD+=(-nographic)
            ;;
    esac
    
    # AMD GPU simulation (closest to Radeon Vega 11)
    if [[ "$GPU_PASSTHROUGH" == "true" && -n "$GPU_PCI_ID" ]]; then
        echo "Configuring GPU passthrough for PCI ID: $GPU_PCI_ID"
        QEMU_CMD+=(-device vfio-pci,host="$GPU_PCI_ID")
    else
        # Use virtio-gpu for better performance than default VGA
        QEMU_CMD+=(-device virtio-gpu-pci,virgl=on)
    fi
    
    # Boot configuration
    case "$boot_mode" in
        iso)
            if [[ -z "$BOOT_ISO" ]]; then
                echo "Error: No ISO file specified for installation"
                exit 1
            fi
            if [[ ! -f "$BOOT_ISO" ]]; then
                echo "Error: ISO file not found: $BOOT_ISO"
                exit 1
            fi
            QEMU_CMD+=(-cdrom "$BOOT_ISO" -boot d)
            echo "Booting from ISO: $BOOT_ISO"
            ;;
        disk)
            if [[ ! -f "$disk_file" ]]; then
                echo "Error: Disk image not found: $disk_file"
                echo "Use 'create' command first."
                exit 1
            fi
            QEMU_CMD+=(-boot c)
            echo "Booting from disk: $disk_file"
            ;;
        *)
            echo "Error: Invalid boot mode: $boot_mode"
            exit 1
            ;;
    esac
}

start_vm() {
    local boot_mode="$1"
    
    build_qemu_command "$boot_mode"
    
    echo "Starting KioskBook test VM..."
    echo "VM specs: $VM_CPUS CPUs, $VM_MEMORY RAM, Virtio storage"
    echo "Command: ${QEMU_CMD[*]}"
    echo ""
    echo "Press Ctrl+Alt+G to release mouse (if using GTK)"
    echo "SSH access (if configured): ssh -p 2222 user@localhost"
    echo "Web access (if app running): http://localhost:3000"
    echo ""
    
    exec "${QEMU_CMD[@]}"
}

clean_vm() {
    local disk_file="$VM_DISK_PATH/${VM_NAME}.qcow2"
    
    if [[ -f "$disk_file" ]]; then
        echo "Removing VM disk: $disk_file"
        rm -f "$disk_file"
        echo "✓ VM disk removed"
    else
        echo "No VM disk found at: $disk_file"
    fi
    
    # Clean up empty directory
    if [[ -d "$VM_DISK_PATH" ]] && [[ -z "$(ls -A "$VM_DISK_PATH")" ]]; then
        rmdir "$VM_DISK_PATH"
        echo "✓ Cleaned up empty disk directory"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            VM_NAME="$2"
            shift 2
            ;;
        --memory)
            VM_MEMORY="$2"
            shift 2
            ;;
        --cpus)
            VM_CPUS="$2"
            shift 2
            ;;
        --disk-size)
            VM_DISK_SIZE="$2"
            shift 2
            ;;
        --disk-path)
            VM_DISK_PATH="$2"
            shift 2
            ;;
        --iso)
            BOOT_ISO="$2"
            shift 2
            ;;
        --disk)
            BOOT_DISK="$2"
            shift 2
            ;;
        --display)
            DISPLAY_TYPE="$2"
            shift 2
            ;;
        --vnc-port)
            VNC_PORT="$2"
            shift 2
            ;;
        --gpu-passthrough)
            GPU_PASSTHROUGH="true"
            shift
            ;;
        --gpu-pci-id)
            GPU_PCI_ID="$2"
            shift 2
            ;;
        --bridge)
            VM_NET_BRIDGE="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        create|start|install|test|clean)
            COMMAND="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default command if none specified
if [[ -z "$COMMAND" ]]; then
    COMMAND="start"
fi

# Main execution
check_requirements

case "$COMMAND" in
    create)
        create_disk
        ;;
    start)
        start_vm "disk"
        ;;
    install)
        if [[ -z "$BOOT_ISO" ]]; then
            echo "Error: --iso required for install command"
            exit 1
        fi
        start_vm "iso"
        ;;
    test)
        start_vm "disk"
        ;;
    clean)
        clean_vm
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac