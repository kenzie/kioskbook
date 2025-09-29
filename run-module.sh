#!/bin/bash
#
# KioskBook Module Runner
#
# Safely run individual installation modules on a live system.
# This allows for updating specific components without affecting others.
#
# Usage: ./run-module.sh <module-name> [args...]
#        ./run-module.sh --list
#        ./run-module.sh --help
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIOSKBOOK_DIR="/opt/kioskbook"
MODULES_DIR="$KIOSKBOOK_DIR/modules"
LOG_DIR="/var/log/kioskbook-modules"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

log_step() {
    echo -e "\n${BLUE}===${NC} ${CYAN}$1${NC} ${BLUE}===${NC}\n"
}

show_help() {
    echo "KioskBook Module Runner"
    echo
    echo "Usage: $0 <module-name> [args...]"
    echo "       $0 --list"
    echo "       $0 --help"
    echo
    echo "Commands:"
    echo "  <module-name>  - Run specific module"
    echo "  --list         - List available modules"
    echo "  --help         - Show this help"
    echo
    echo "Available modules:"
    list_modules
}

list_modules() {
    if [ -d "$MODULES_DIR" ]; then
        echo
        for module in "$MODULES_DIR"/*.sh; do
            if [ -f "$module" ]; then
                basename "$module" .sh
            fi
        done | sort
    else
        echo "  No modules directory found at $MODULES_DIR"
    fi
}

# Check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root"
    fi
}

# Verify module exists
verify_module() {
    local module_name="$1"
    local module_script="$MODULES_DIR/$module_name.sh"
    
    if [ ! -f "$module_script" ]; then
        log_error "Module '$module_name' not found at $module_script"
    fi
    
    if [ ! -x "$module_script" ]; then
        log_warn "Making module script executable..."
        chmod +x "$module_script"
    fi
}

# Run module with logging
run_module() {
    local module_name="$1"
    local module_script="$MODULES_DIR/$module_name.sh"
    local log_file="$LOG_DIR/$module_name-$(date +%Y%m%d-%H%M%S).log"
    shift # Remove module name from args
    
    log_step "Running Module: $module_name"
    
    # Create backup of current state if this is a config module
    if [[ "$module_name" =~ ^(50-kiosk-services|60-boot-splash|70-health-monitoring|80-auto-updates|90-screensaver|100-kiosk-cli)$ ]]; then
        log_info "Creating backup before running config module..."
        backup_dir="/var/backups/kioskbook/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Backup systemd services
        if [ -d "/etc/systemd/system" ]; then
            cp -r /etc/systemd/system/kiosk* "$backup_dir/" 2>/dev/null || true
        fi
        
        # Backup kioskbook config
        if [ -d "$KIOSKBOOK_DIR" ]; then
            cp -r "$KIOSKBOOK_DIR" "$backup_dir/" 2>/dev/null || true
        fi
        
        log_info "Backup created at $backup_dir"
    fi
    
    # Run the module
    log_info "Executing: $module_script $*"
    log_info "Logging to: $log_file"
    
    if bash "$module_script" "$@" 2>&1 | tee "$log_file"; then
        log_info "Module $module_name completed successfully"
        echo "SUCCESS" >> "$log_file"
        return 0
    else
        log_error "Module $module_name failed - check log: $log_file"
    fi
}

# Show module status
show_status() {
    log_step "Module Status"
    
    if [ ! -d "$MODULES_DIR" ]; then
        log_error "KioskBook not installed - modules directory not found"
    fi
    
    echo -e "${CYAN}Available modules:${NC}"
    for module in "$MODULES_DIR"/*.sh; do
        if [ -f "$module" ]; then
            module_name=$(basename "$module" .sh)
            echo -e "  ${GREEN}✓${NC} $module_name"
        fi
    done
    
    echo -e "\n${CYAN}Recent module runs:${NC}"
    if [ -d "$LOG_DIR" ]; then
        ls -la "$LOG_DIR"/*.log 2>/dev/null | tail -5 || echo "  No recent runs"
    else
        echo "  No log directory found"
    fi
}

# Main function
main() {
    case "${1:-}" in
        "--help"|"-h")
            show_help
            ;;
        "--list"|"-l")
            list_modules
            ;;
        "--status"|"-s")
            check_root
            show_status
            ;;
        "")
            show_help
            ;;
        *)
            check_root
            verify_module "$1"
            run_module "$@"
            ;;
    esac
}

main "$@"
