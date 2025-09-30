#!/bin/bash
#
# KioskBook Alpine Linux Main Installer
#
# Transforms Alpine Linux into a bulletproof kiosk deployment platform.
# This script orchestrates the complete installation process using modular components.
#
# Usage: ./main.sh [github_repo] [tailscale_key]
#
# Arguments:
#   github_repo    - GitHub repository for kiosk application (default: kenzie/lobby-display)
#   tailscale_key  - Tailscale authentication key (optional, will prompt if not provided)
#

set -e
set -o pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Script directory and paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MODULES_DIR="${SCRIPT_DIR}/modules"
readonly CONFIG_DIR="${SCRIPT_DIR}/../config"
readonly SCRIPTS_DIR="${SCRIPT_DIR}/../scripts"
readonly TOOLS_DIR="${SCRIPT_DIR}/../tools"

# Installation configuration
GITHUB_REPO="${1:-kenzie/lobby-display}"
TAILSCALE_KEY="${2:-}"
TARGET_DISK=""
HOSTNAME="kioskbook"
TIMEZONE="America/Halifax"

# Installation state
MODULES_EXECUTED=()
ROLLBACK_ACTIONS=()

# Logging functions
log() {
    echo -e "${BLUE}[INSTALLER]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_progress() {
    echo -e "${PURPLE}[PROGRESS]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Installation failed. Starting rollback procedure..."
    perform_rollback
    exit 1
}

# Add rollback action
add_rollback() {
    ROLLBACK_ACTIONS+=("$1")
}

# Perform rollback
perform_rollback() {
    if [ ${#ROLLBACK_ACTIONS[@]} -eq 0 ]; then
        log_info "No rollback actions to perform"
        return 0
    fi
    
    log_warning "Performing rollback operations..."
    
    # Execute rollback actions in reverse order
    for ((i=${#ROLLBACK_ACTIONS[@]}-1; i>=0; i--)); do
        local action="${ROLLBACK_ACTIONS[i]}"
        log_info "Rollback: $action"
        eval "$action" || log_warning "Rollback action failed: $action"
    done
    
    log_warning "Rollback completed"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Use 'sudo bash $0' or run as root."
    fi
}

# Detect target disk
detect_target_disk() {
    log "Detecting target storage device..."
    
    # Primary target: NVMe drive
    if [[ -b "/dev/nvme0n1" ]]; then
        TARGET_DISK="/dev/nvme0n1"
        log_success "Found NVMe drive: $TARGET_DISK"
        return 0
    fi
    
    # Fallback: First SATA/SCSI drive
    for disk in /dev/sd[a-z]; do
        if [[ -b "$disk" ]]; then
            TARGET_DISK="$disk"
            log_warning "NVMe not found, using SATA/SCSI drive: $TARGET_DISK"
            return 0
        fi
    done
    
    error_exit "No suitable storage device found. Ensure NVMe or SATA drive is connected."
}

# Get disk information
get_disk_info() {
    local disk="$1"
    local size_bytes
    local size_gb
    
    if [[ -b "$disk" ]]; then
        size_bytes=$(blockdev --getsize64 "$disk" 2>/dev/null || echo "0")
        size_gb=$((size_bytes / 1024 / 1024 / 1024))
        echo "${size_gb}GB"
    else
        echo "Unknown"
    fi
}

# Skip Tailscale key prompt - install and configure later via SSH
prompt_tailscale_key() {
    log_info "Tailscale will be installed but not authenticated during installation"
    log_info "Configure Tailscale after installation via SSH:"
    log_info "  sudo tailscale up --auth-key=<your-key>"
    TAILSCALE_KEY=""  # Always empty, handled post-install
}

# Show installation summary
show_installation_summary() {
    local disk_size
    disk_size=$(get_disk_info "$TARGET_DISK")
    
    echo ""
    echo -e "${WHITE}================================================${NC}"
    echo -e "${WHITE}         KioskBook Installation Summary${NC}"
    echo -e "${WHITE}================================================${NC}"
    echo ""
    echo -e "${CYAN}Target Hardware:${NC}"
    echo -e "  Disk: ${YELLOW}$TARGET_DISK${NC} (${disk_size})"
    echo -e "  Hostname: ${YELLOW}$HOSTNAME${NC}"
    echo -e "  Timezone: ${YELLOW}$TIMEZONE${NC}"
    echo ""
    echo -e "${CYAN}Application Configuration:${NC}"
    echo -e "  GitHub Repository: ${YELLOW}$GITHUB_REPO${NC}"
    echo -e "  Tailscale: ${YELLOW}Install Only (configure via SSH)${NC}"
    echo ""
    echo -e "${CYAN}Installation Modules:${NC}"
    
    local modules=($(find "$MODULES_DIR" -name "*.sh" | sort))
    for module in "${modules[@]}"; do
        local module_name=$(basename "$module" .sh)
        local module_desc=""
        
        case "$module_name" in
            "00-partition") module_desc="Disk partitioning and filesystem setup" ;;
            "10-base-system") module_desc="Core Alpine Linux system configuration" ;;
            "20-boot-optimization") module_desc="Boot time optimization (<10s)" ;;
            "30-display-stack") module_desc="X11, Chromium, AMD drivers" ;;
            "40-kiosk-user") module_desc="Kiosk user with auto-login" ;;
            "50-application") module_desc="Node.js application setup" ;;
            "60-networking") module_desc="Tailscale VPN and SSH" ;;
            "70-monitoring") module_desc="OpenRC services and health checks" ;;
            *) module_desc="Custom module" ;;
        esac
        
        echo -e "  ${YELLOW}$module_name${NC}: $module_desc"
    done
    
    echo ""
    echo -e "${RED}WARNING: This will ERASE all data on $TARGET_DISK${NC}"
    echo ""
}

# Confirm installation
confirm_installation() {
    read -p "Proceed with installation? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
    echo ""
}

# Execute installation module
execute_module() {
    local module_path="$1"
    local module_name=$(basename "$module_path" .sh)
    
    log_progress "Executing module: $module_name"
    
    # Check if module file exists and is executable
    if [[ ! -f "$module_path" ]]; then
        error_exit "Module not found: $module_path"
    fi
    
    if [[ ! -x "$module_path" ]]; then
        chmod +x "$module_path"
    fi
    
    # Export configuration variables for modules
    export GITHUB_REPO TAILSCALE_KEY TARGET_DISK HOSTNAME TIMEZONE
    export CONFIG_DIR SCRIPTS_DIR TOOLS_DIR
    
    # Export mount points if they exist (set by partition module)
    if [[ -n "$MOUNT_ROOT" ]]; then
        export MOUNT_ROOT MOUNT_BOOT MOUNT_DATA
        export ROOT_PARTITION BOOT_PARTITION DATA_PARTITION
    fi
    
    # Source and execute module
    if source "$module_path"; then
        MODULES_EXECUTED+=("$module_name")
        log_success "Module completed: $module_name"
    else
        error_exit "Module failed: $module_name"
    fi
}

# Execute all modules
execute_modules() {
    log "Starting module execution..."
    
    local modules=($(find "$MODULES_DIR" -name "*.sh" | sort))
    local total_modules=${#modules[@]}
    local current_module=0
    
    for module in "${modules[@]}"; do
        current_module=$((current_module + 1))
        
        echo ""
        echo -e "${WHITE}[${current_module}/${total_modules}]${NC} $(basename "$module" .sh)"
        echo -e "${WHITE}=====================================${NC}"
        
        execute_module "$module"
        
        # Add a small delay for readability
        sleep 1
    done
}

# Validate installation
validate_installation() {
    log "Validating installation..."
    
    # Check if validation script exists
    local validation_script="$TOOLS_DIR/validate-install.sh"
    if [[ -f "$validation_script" && -x "$validation_script" ]]; then
        if "$validation_script"; then
            log_success "Installation validation passed"
        else
            log_warning "Installation validation failed, but continuing..."
        fi
    else
        log_info "No validation script found, skipping validation"
    fi
}

# Installation complete
installation_complete() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}    KioskBook Installation Completed!${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    
    log_success "Installation completed successfully!"
    
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  1. ${YELLOW}Reboot the system${NC}"
    echo -e "  2. ${YELLOW}System will boot in <5 seconds with Route 19 splash${NC}"
    echo -e "  3. ${YELLOW}Kiosk application will start automatically${NC}"
    echo ""
    
    echo -e "${CYAN}Remote management setup:${NC}"
    echo -e "  1. ${YELLOW}SSH to system via local network first${NC}"
    echo -e "  2. ${YELLOW}sudo tailscale up --auth-key=<your-key>${NC}"
    echo -e "  3. ${YELLOW}Then SSH via Tailscale network${NC}"
    echo -e "  Get auth key: https://login.tailscale.com/admin/settings/keys"
    echo ""
    
    echo -e "${CYAN}Management commands:${NC}"
    echo -e "  - ${YELLOW}rc-status${NC} - View service status"
    echo -e "  - ${YELLOW}rc-service kiosk-app restart${NC} - Restart application"
    echo -e "  - ${YELLOW}rc-service kiosk-display restart${NC} - Restart display"
    echo -e "  - ${YELLOW}system-status${NC} - System dashboard"
    echo -e "  - ${YELLOW}font-status${NC} - Font configuration status"
    echo -e "  - ${YELLOW}validate-installation${NC} - Verify system setup"
    echo ""
    
    read -p "Reboot now? (Y/n): " reboot_confirm
    if [[ ! "$reboot_confirm" =~ ^[Nn]$ ]]; then
        log "Rebooting system..."
        sleep 2
        reboot
    else
        log_info "Reboot skipped. Please reboot manually to complete installation."
    fi
}

# Main installation process
main() {
    # Trap for cleanup on exit
    trap 'perform_rollback' EXIT
    
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}      KioskBook Alpine Linux Installer${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
    
    log "Starting KioskBook installation..."
    
    # Pre-installation checks
    check_root
    detect_target_disk
    prompt_tailscale_key
    
    # Show summary and confirm
    show_installation_summary
    confirm_installation
    
    # Execute installation
    execute_modules
    validate_installation
    
    # Clear trap - installation successful
    trap - EXIT
    
    # Complete installation
    installation_complete
}

# Execute main function with all arguments
main "$@"