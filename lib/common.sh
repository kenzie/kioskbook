#!/bin/bash
#
# Common functions and variables for KioskBook modules
#

# Colors for output (only define if not already set)
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly CYAN='\033[0;36m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly NC='\033[0m'
fi

# Common configuration (only define if not already set)
if [[ -z "${KIOSK_USER:-}" ]]; then
    readonly KIOSK_USER="kiosk"
    readonly KIOSK_HOME="/home/kiosk"
    readonly APP_DIR="/opt/kioskbook"
    readonly REPO_DIR="/opt/kioskbook-repo"
    readonly LOG_DIR="/var/log/kioskbook"
    readonly DEFAULT_GITHUB_REPO="https://github.com/kenzie/lobby-display"
fi

# Logging functions
log() {
    printf "${CYAN}[KIOSKBOOK]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
    exit 1
}

log_module() {
    local module="$1"
    local message="$2"
    printf "${BLUE}[${module}]${NC} %s\n" "$message"
}

log_module_success() {
    local module="$1"
    local message="$2"
    printf "${GREEN}[${module}]${NC} %s\n" "$message"
}

log_module_warning() {
    local module="$1"
    local message="$2"
    printf "${YELLOW}[${module}]${NC} %s\n" "$message"
}

log_module_error() {
    local module="$1"
    local message="$2"
    printf "${RED}[${module}]${NC} %s\n" "$message" >&2
    exit 1
}

# Banner display
show_banner() {
    local title="$1"
    clear
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "     $title"
    echo "═══════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
    fi
}

# Check if this is Debian
require_debian() {
    if ! grep -q "Debian" /etc/os-release 2>/dev/null; then
        log_error "This script is designed for Debian systems"
    fi
}

# Check network connectivity
require_network() {
    if ! ping -c 1 debian.org >/dev/null 2>&1; then
        log_error "Network connectivity required. Please configure networking first."
    fi
}

# Create log directory
ensure_log_dir() {
    mkdir -p "$LOG_DIR"
}

# Get module list
get_modules() {
    local modules_dir="${1:-modules}"
    find "$modules_dir" -name "[0-9][0-9]-*.sh" | sort
}

# Run a single module
run_module() {
    local module_path="$1"
    local module_name=$(basename "$module_path")

    log "Running module: $module_name"

    if [[ ! -f "$module_path" ]]; then
        log_error "Module not found: $module_path"
    fi

    if [[ ! -x "$module_path" ]]; then
        chmod +x "$module_path"
    fi

    bash "$module_path"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "Module $module_name failed with exit code $exit_code"
    fi

    log_success "Module $module_name completed successfully"
}

# Export functions for use in subshells
export -f log log_success log_warning log_error
export -f log_module log_module_success log_module_warning log_module_error
export -f show_banner require_root require_debian require_network ensure_log_dir
export -f get_modules run_module
