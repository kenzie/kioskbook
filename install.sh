#!/bin/bash
# KioskBook Modular Installation Script

# Error handling
set -e
trap 'handle_error $LINENO' ERR

# Global variables for cleanup
MOUNTED_PARTITIONS=""
INSTALLATION_STARTED=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
HOSTNAME="kioskbook"
DISK=""
GITHUB_REPO=""
GITHUB_URL=""
TAILSCALE_KEY=""

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
    echo "  _  __ _           _    ____             _    _"
    echo " | |/ /(_) ___  ___| | _| __ )  __ _  ___| | __| |"
    echo " | ' / | |/ _ \/ __| |/ /  _ \ / _\` |/ __| |/ /| |"
    echo " | . \ | |  __/ (__|   <| |_) | (_| | (__|   < |_|"
    echo " |_|\_\_|\___|\___|_|\_\____/ \__,_|\___|_|\_\(_)"
    echo -e "${NC}"
    echo -e "${CYAN}Professional Kiosk Deployment Platform${NC}"
    echo -e "${CYAN}Alpine Linux + Tailscale Ready${NC}"
    echo
}

# Get configuration from user
get_configuration() {
    echo -e "${CYAN}KioskBook Configuration${NC}"
    echo "=========================="
    echo
    
    # Auto-detect target disk
    echo -e "${CYAN}Available disks:${NC}"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo
    
    # Auto-detect NVMe drive (primary target for Lenovo M75q-1)
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
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
    
    # Get GitHub repository
    echo -n -e "${CYAN}Kiosk display git repo${NC}: "
    read GITHUB_REPO
    
    if [ -z "$GITHUB_REPO" ]; then
        log_error "GitHub repository is required!"
        exit 1
    fi
    
    # Convert to GitHub URL
    if [[ "$GITHUB_REPO" == *"github.com"* ]]; then
        GITHUB_URL="$GITHUB_REPO"
    else
        GITHUB_URL="https://github.com/$GITHUB_REPO.git"
    fi
    
    # Get Tailscale auth key
    echo -n -e "${CYAN}Tailscale auth key (required)${NC}: "
    read TAILSCALE_KEY
    
    if [ -z "$TAILSCALE_KEY" ]; then
        log_error "Tailscale auth key is required for installation!"
        exit 1
    fi
    
    echo
    echo -e "${CYAN}Installation Summary:${NC}"
    echo "Target Disk: $DISK"
    echo "Kiosk App: $GITHUB_REPO"
    echo "Tailscale: Enabled (Required)"
    echo
    echo -n "Proceed with installation? (y/N): "
    read confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Installation cancelled"
        exit 0
    fi
}

# Source all modules in order
source_modules() {
    log_step "Loading installation modules"
    
    # Check if modules directory exists
    if [ ! -d "modules" ]; then
        log_error "Modules directory not found!"
        exit 1
    fi
    
    # Source all module files in numerical order
    for module in modules/*.sh; do
        if [ -f "$module" ]; then
            log_info "Loading $(basename "$module")"
            source "$module"
        fi
    done
    
    log_info "All modules loaded successfully"
}

# Run all installation steps automatically
run_installation_steps() {
    log_step "Running Installation Steps"
    
    # Define the installation steps in order
    local steps=(
        "prepare_disk"
        "setup_network"
        "setup_minimal_boot" 
        "setup_fstab"
        "install_kiosk_system"
        "setup_kiosk_user"
        "setup_kiosk_app"
        "setup_kiosk_watchdog"
        "setup_auto_update"
        "setup_screensaver"
        "setup_kiosk_cli"
        "setup_resource_management"
        "setup_escalating_recovery"
        "setup_logging_debugging"
        "setup_boot_logo"
        "setup_hardware_optimizations"
        "setup_tailscale"
        "apply_optimizations"
        "create_tools"
    )
    
    # Run each step
    for step in "${steps[@]}"; do
        if declare -f "$step" > /dev/null; then
            log_info "Running: $step"
            "$step"
        else
            log_warning "Function $step not found, skipping"
        fi
    done
    
    log_info "All installation steps completed"
}

# Validate installation environment
validate_environment() {
    log_step "Validating Installation Environment"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check if running on Alpine Linux
    if [ ! -f /etc/alpine_release ]; then
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
    
    # Check for required tools
    local required_tools=("parted" "mkfs.ext4" "mkfs.fat" "mount" "chroot")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool '$tool' not found"
            log_error "Please install missing tools: apk add parted e2fsprogs dosfstools util-linux"
            exit 1
        fi
    done
    
    # Check if we're in a live environment (not installed system)
    if [ -f /etc/hostname ] && [ "$(cat /etc/hostname)" != "alpine" ]; then
        log_warning "This appears to be an installed system, not a live Alpine environment"
        log_warning "Please boot from Alpine Linux ISO for installation"
        read -p "Continue anyway? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            exit 1
        fi
    fi
    
    log_info "Environment validation passed"
}

# Error handling function
handle_error() {
    local line_number=$1
    log_error "Installation failed at line $line_number"
    
    if [ "$INSTALLATION_STARTED" = true ]; then
        log_info "Attempting to cleanup..."
        
        # Unmount partitions in reverse order
        if [ -n "$MOUNTED_PARTITIONS" ]; then
            for partition in $MOUNTED_PARTITIONS; do
                if mount | grep -q "$partition"; then
                    log_info "Unmounting $partition"
                    umount "$partition" 2>/dev/null || true
                fi
            done
        fi
        
        # Remove mount points
        umount /mnt/root/boot 2>/dev/null || true
        umount /mnt/root 2>/dev/null || true
        umount /mnt/boot 2>/dev/null || true
        
        log_info "Cleanup completed"
    fi
    
    log_error "Installation failed. Please check the error messages above."
    exit 1
}

# Cleanup function for successful completion
cleanup_on_success() {
    log_info "Finalizing installation..."
    
    # Unmount bind mount
    umount /mnt/root/boot 2>/dev/null || true
    
    # Unmount partitions
    umount /mnt/root 2>/dev/null || true
    umount /mnt/boot 2>/dev/null || true
    
    log_info "Installation cleanup completed"
}

# Main installation function
main() {
    show_banner
    validate_environment
    get_configuration
    source_modules
    
    log_step "Starting KioskBook Installation"
    
    # Run installation steps automatically
    run_installation_steps
    
    # Cleanup on success
    cleanup_on_success
    
    log_info "KioskBook installation completed successfully!"
    echo
    echo -e "${GREEN}KIOSKBOOK INSTALLATION SUCCESSFUL!${NC}"
    echo
    echo "Your kiosk is ready to use:"
    echo "- Hostname: $HOSTNAME"
    echo "- Kiosk App: $GITHUB_REPO"
    echo "- Tailscale: Enabled (Required)"
    echo
    echo "The system will reboot in 10 seconds..."
    sleep 10
    reboot
}

# Run main function
main "$@"
