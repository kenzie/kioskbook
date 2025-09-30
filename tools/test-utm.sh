#!/bin/bash
#
# KioskBook UTM Testing Script
#
# Sets up UTM virtual machines for testing KioskBook installer.
# Provides automated VM management via UTM CLI for development workflow.
#
# Features:
# - Automated VM creation from JSON configuration
# - Alpine ISO download and attachment
# - VM snapshot management for testing iterations
# - Network port forwarding for SSH and HTTP access
# - Boot sequence management (USB installer -> disk boot)
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
UTM_CONFIG="$SCRIPT_DIR/utm-config.json"
VM_NAME="KioskBook-Dev"
VM_DISK_SIZE="20G"
ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-standard-3.19.0-x86_64.iso"
ALPINE_ISO_NAME="alpine-standard-3.19.0-x86_64.iso"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[UTM]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[UTM SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[UTM WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[UTM ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    # Check if UTM CLI is available
    if ! command -v utm >/dev/null 2>&1; then
        log_error "UTM CLI not found. Please install UTM and add it to PATH."
        log "Install UTM from: https://mac.getutm.app/"
        log "Add UTM CLI to PATH: export PATH=\"/Applications/UTM.app/Contents/MacOS:\$PATH\""
        exit 1
    fi
    
    # Check if wget or curl is available
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        log_error "Neither wget nor curl found. Please install one of them."
        exit 1
    fi
    
    # Check if jq is available (optional but recommended)
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq not found. JSON configuration will be created without validation."
    fi
    
    log_success "Dependencies check passed"
}

# Download Alpine ISO
download_alpine_iso() {
    local iso_path="$SCRIPT_DIR/$ALPINE_ISO_NAME"
    
    if [[ -f "$iso_path" ]]; then
        log "Alpine ISO already exists: $iso_path"
        return 0
    fi
    
    log "Downloading Alpine Linux ISO..."
    log "URL: $ALPINE_ISO_URL"
    
    if command -v wget >/dev/null 2>&1; then
        wget -O "$iso_path" "$ALPINE_ISO_URL" || {
            log_error "Failed to download Alpine ISO with wget"
            exit 1
        }
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o "$iso_path" "$ALPINE_ISO_URL" || {
            log_error "Failed to download Alpine ISO with curl"
            exit 1
        }
    fi
    
    # Verify download
    if [[ ! -f "$iso_path" ]]; then
        log_error "Alpine ISO download failed"
        exit 1
    fi
    
    local iso_size
    iso_size=$(du -h "$iso_path" | cut -f1)
    log_success "Alpine ISO downloaded successfully ($iso_size): $iso_path"
}

# Create VM from configuration
create_vm() {
    log "Creating UTM virtual machine: $VM_NAME"
    
    # Check if VM already exists
    if utm list | grep -q "$VM_NAME"; then
        log_warning "VM '$VM_NAME' already exists"
        log "Use 'delete' command to remove it first, or 'start' to run existing VM"
        return 0
    fi
    
    # Validate UTM config exists
    if [[ ! -f "$UTM_CONFIG" ]]; then
        log_error "UTM configuration file not found: $UTM_CONFIG"
        exit 1
    fi
    
    # Create VM from configuration
    log "Creating VM from configuration: $UTM_CONFIG"
    utm create --config "$UTM_CONFIG" "$VM_NAME" || {
        log_error "Failed to create VM from configuration"
        exit 1
    }
    
    log_success "VM '$VM_NAME' created successfully"
}

# Create VM using CLI parameters (alternative method)
create_vm_cli() {
    log "Creating UTM virtual machine using CLI parameters: $VM_NAME"
    
    # Check if VM already exists
    if utm list | grep -q "$VM_NAME"; then
        log_warning "VM '$VM_NAME' already exists"
        return 0
    fi
    
    # Create VM with specific parameters
    utm create \
        --name "$VM_NAME" \
        --operating-system linux \
        --architecture x86_64 \
        --memory 4096 \
        --cpu-cores 4 \
        --disk-size "$VM_DISK_SIZE" \
        --network shared \
        --display virtio-gpu \
        --sound intel-hda || {
        log_error "Failed to create VM with CLI parameters"
        exit 1
    }
    
    log_success "VM '$VM_NAME' created successfully using CLI"
}

# Attach Alpine ISO to VM
attach_iso() {
    local iso_path="$SCRIPT_DIR/$ALPINE_ISO_NAME"
    
    if [[ ! -f "$iso_path" ]]; then
        log_error "Alpine ISO not found: $iso_path"
        log "Run 'download' command first"
        exit 1
    fi
    
    log "Attaching Alpine ISO to VM..."
    utm attach --vm "$VM_NAME" --drive cdrom --image "$iso_path" || {
        log_error "Failed to attach ISO to VM"
        exit 1
    }
    
    log_success "Alpine ISO attached to VM"
}

# Start VM
start_vm() {
    log "Starting VM: $VM_NAME"
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_error "VM '$VM_NAME' not found. Create it first."
        exit 1
    fi
    
    # Check if VM is already running
    if utm status "$VM_NAME" | grep -q "running"; then
        log_warning "VM '$VM_NAME' is already running"
        return 0
    fi
    
    utm start "$VM_NAME" || {
        log_error "Failed to start VM"
        exit 1
    }
    
    log_success "VM '$VM_NAME' started"
    log "Connect via UTM GUI or VNC"
    log "SSH access: ssh -p 2222 root@localhost (after network setup)"
    log "HTTP access: http://localhost:3000 (after KioskBook installation)"
}

# Stop VM
stop_vm() {
    log "Stopping VM: $VM_NAME"
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_warning "VM '$VM_NAME' not found"
        return 0
    fi
    
    # Check if VM is running
    if ! utm status "$VM_NAME" | grep -q "running"; then
        log_warning "VM '$VM_NAME' is not running"
        return 0
    fi
    
    utm stop "$VM_NAME" || {
        log_error "Failed to stop VM"
        exit 1
    }
    
    log_success "VM '$VM_NAME' stopped"
}

# Delete VM
delete_vm() {
    log "Deleting VM: $VM_NAME"
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_warning "VM '$VM_NAME' not found"
        return 0
    fi
    
    # Stop VM if running
    if utm status "$VM_NAME" | grep -q "running"; then
        log "Stopping VM before deletion..."
        stop_vm
        sleep 2
    fi
    
    utm delete "$VM_NAME" || {
        log_error "Failed to delete VM"
        exit 1
    }
    
    log_success "VM '$VM_NAME' deleted"
}

# Create VM snapshot
create_snapshot() {
    local snapshot_name="${1:-kioskbook-pre-install}"
    
    log "Creating VM snapshot: $snapshot_name"
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_error "VM '$VM_NAME' not found"
        exit 1
    fi
    
    # Stop VM if running (required for snapshot)
    if utm status "$VM_NAME" | grep -q "running"; then
        log "Stopping VM for snapshot creation..."
        stop_vm
        sleep 2
    fi
    
    utm snapshot create "$VM_NAME" "$snapshot_name" || {
        log_error "Failed to create snapshot"
        exit 1
    }
    
    log_success "Snapshot '$snapshot_name' created for VM '$VM_NAME'"
}

# Restore VM snapshot
restore_snapshot() {
    local snapshot_name="${1:-kioskbook-pre-install}"
    
    log "Restoring VM snapshot: $snapshot_name"
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_error "VM '$VM_NAME' not found"
        exit 1
    fi
    
    # Stop VM if running
    if utm status "$VM_NAME" | grep -q "running"; then
        log "Stopping VM for snapshot restore..."
        stop_vm
        sleep 2
    fi
    
    utm snapshot restore "$VM_NAME" "$snapshot_name" || {
        log_error "Failed to restore snapshot"
        exit 1
    }
    
    log_success "Snapshot '$snapshot_name' restored for VM '$VM_NAME'"
}

# List VM snapshots
list_snapshots() {
    log "Listing snapshots for VM: $VM_NAME"
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_error "VM '$VM_NAME' not found"
        exit 1
    fi
    
    utm snapshot list "$VM_NAME" || {
        log_error "Failed to list snapshots"
        exit 1
    }
}

# Show VM status
show_status() {
    log "VM Status for: $VM_NAME"
    echo
    
    if utm list | grep -q "$VM_NAME"; then
        echo "VM Status:"
        utm status "$VM_NAME"
        echo
        
        echo "VM Configuration:"
        utm info "$VM_NAME" 2>/dev/null || echo "  (Configuration details not available)"
        echo
        
        echo "Available Snapshots:"
        utm snapshot list "$VM_NAME" 2>/dev/null || echo "  (No snapshots or snapshots not available)"
    else
        echo "VM '$VM_NAME' not found"
    fi
    
    echo
    echo "Available VMs:"
    utm list
}

# Boot from installer (set boot order to CD-ROM first)
boot_installer() {
    log "Configuring VM to boot from installer ISO..."
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_error "VM '$VM_NAME' not found"
        exit 1
    fi
    
    # This would typically require UTM config modification
    # For now, provide manual instructions
    log "To boot from installer:"
    log "1. Start the VM: $0 start"
    log "2. In UTM GUI, go to VM settings"
    log "3. Set boot order to CD-ROM first"
    log "4. Ensure Alpine ISO is attached to CD-ROM"
    log "5. Restart the VM"
    
    log_warning "Automatic boot order change not implemented in UTM CLI"
    log "Please configure boot order manually in UTM GUI"
}

# Boot from disk (set boot order to disk first)
boot_disk() {
    log "Configuring VM to boot from installed disk..."
    
    if ! utm list | grep -q "$VM_NAME"; then
        log_error "VM '$VM_NAME' not found"
        exit 1
    fi
    
    # This would typically require UTM config modification
    log "To boot from installed disk:"
    log "1. In UTM GUI, go to VM settings"
    log "2. Set boot order to Hard Disk first"
    log "3. Optionally remove Alpine ISO from CD-ROM"
    log "4. Restart the VM"
    
    log_warning "Automatic boot order change not implemented in UTM CLI"
    log "Please configure boot order manually in UTM GUI"
}

# Complete setup workflow
setup_complete() {
    log "Setting up complete KioskBook testing environment..."
    
    download_alpine_iso
    create_vm
    attach_iso
    
    log_success "KioskBook testing environment ready!"
    log ""
    log "Next steps:"
    log "1. Start VM: $0 start"
    log "2. Install Alpine Linux using setup-alpine"
    log "3. Create snapshot: $0 snapshot kioskbook-alpine-base"
    log "4. Run KioskBook installer: wget -O bootstrap.sh https://raw.githubusercontent.com/kenzie/kioskbook/alpine-rewrite/installer/bootstrap.sh && ./bootstrap.sh"
    log "5. Test installation and create final snapshot"
    log ""
    log "VM Network Access:"
    log "- SSH: ssh -p 2222 root@localhost"
    log "- HTTP: http://localhost:3000"
}

# Show help
show_help() {
    cat << 'EOF'
KioskBook UTM Testing Script

USAGE:
    ./test-utm.sh [COMMAND] [OPTIONS]

COMMANDS:
    setup           Complete setup workflow (download ISO, create VM, attach ISO)
    create          Create new VM from configuration
    create-cli      Create new VM using CLI parameters
    download        Download Alpine Linux ISO
    attach-iso      Attach Alpine ISO to VM
    start           Start the VM
    stop            Stop the VM
    delete          Delete the VM
    status          Show VM status and information
    
    # Snapshot Management
    snapshot [name] Create VM snapshot (default: kioskbook-pre-install)
    restore [name]  Restore VM snapshot (default: kioskbook-pre-install)
    snapshots       List all VM snapshots
    
    # Boot Configuration
    boot-installer  Configure VM to boot from Alpine ISO
    boot-disk       Configure VM to boot from installed disk
    
    help            Show this help message

EXAMPLES:
    # Complete setup for testing
    ./test-utm.sh setup
    
    # Start VM for Alpine installation
    ./test-utm.sh start
    
    # Create snapshot before KioskBook installation
    ./test-utm.sh snapshot alpine-installed
    
    # Restore snapshot to test installer again
    ./test-utm.sh restore alpine-installed
    
    # Check VM status
    ./test-utm.sh status

VM CONFIGURATION:
    Name: KioskBook-Dev
    Memory: 4GB RAM
    CPU: 4 cores
    Disk: 20GB NVMe (virtio-blk)
    Display: virtio-gpu-gl-pci (1920x1080)
    Network: Shared mode with port forwarding
    
NETWORK ACCESS:
    SSH: ssh -p 2222 root@localhost
    HTTP: http://localhost:3000 (after KioskBook installation)

DEVELOPMENT WORKFLOW:
    1. ./test-utm.sh setup          # Initial setup
    2. ./test-utm.sh start          # Start VM
    3. Install Alpine Linux        # In VM console
    4. ./test-utm.sh snapshot base  # Save clean Alpine
    5. Test KioskBook installer     # In VM
    6. ./test-utm.sh restore base   # Reset for next test

For UTM GUI alternative, import tools/utm-config.json manually.
EOF
}

# Main script logic
main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        "setup")
            check_dependencies
            setup_complete
            ;;
        "create")
            check_dependencies
            create_vm
            ;;
        "create-cli")
            check_dependencies
            create_vm_cli
            ;;
        "download")
            check_dependencies
            download_alpine_iso
            ;;
        "attach-iso")
            check_dependencies
            attach_iso
            ;;
        "start")
            check_dependencies
            start_vm
            ;;
        "stop")
            check_dependencies
            stop_vm
            ;;
        "delete")
            check_dependencies
            delete_vm
            ;;
        "status")
            check_dependencies
            show_status
            ;;
        "snapshot")
            check_dependencies
            create_snapshot "$1"
            ;;
        "restore")
            check_dependencies
            restore_snapshot "$1"
            ;;
        "snapshots")
            check_dependencies
            list_snapshots
            ;;
        "boot-installer")
            check_dependencies
            boot_installer
            ;;
        "boot-disk")
            check_dependencies
            boot_disk
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"