#!/bin/bash
#
# Common functions and variables for KioskBook modules
#

# Colors for output (only define if not already set)
: "${RED:=$'\033[0;31m'}"
: "${GREEN:=$'\033[0;32m'}"
: "${YELLOW:=$'\033[1;33m'}"
: "${CYAN:=$'\033[0;36m'}"
: "${BLUE:=$'\033[1;36m'}"  # Bright cyan for better visibility on black background
: "${MAGENTA:=$'\033[0;35m'}"
: "${NC:=$'\033[0m'}"

# Common configuration (only define if not already set)
: "${KIOSK_USER:=kiosk}"
: "${KIOSK_HOME:=/home/kiosk}"
: "${REPO_DIR:=/opt/kioskbook-repo}"
: "${LOG_DIR:=/var/log/kioskbook}"
: "${MIGRATION_VERSION_FILE:=/etc/kioskbook/migration-version}"
: "${DEFAULT_DISPLAY_URL:=https://kioskbook.ca/display}"

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

# Migration logging
log_migration() {
    local migration_name=$(basename "${1:-unknown}")
    local message="$2"
    printf "${MAGENTA}[MIGRATION ${migration_name}]${NC} %s\n" "$message"
}

# Get last applied migration version
get_migration_version() {
    if [[ -f "$MIGRATION_VERSION_FILE" ]]; then
        cat "$MIGRATION_VERSION_FILE"
    else
        echo "00000000"  # No migrations applied yet
    fi
}

# Get list of pending migrations
get_pending_migrations() {
    local migrations_dir="${1:-migrations}"
    local last_version=$(get_migration_version)

    # Find all migration files newer than last version
    find "$migrations_dir" -name "[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*.sh" 2>/dev/null | sort | while read migration; do
        local migration_name=$(basename "$migration")
        local migration_version="${migration_name%%_*}"

        if [[ "$migration_version" > "$last_version" ]]; then
            echo "$migration"
        fi
    done
}

# Run a single migration
run_migration() {
    local migration_path="$1"
    local migration_name=$(basename "$migration_path")
    local migration_version="${migration_name%%_*}"

    log_migration "$migration_name" "Starting migration..."

    if [[ ! -f "$migration_path" ]]; then
        log_error "Migration not found: $migration_path"
    fi

    if [[ ! -x "$migration_path" ]]; then
        chmod +x "$migration_path"
    fi

    bash "$migration_path"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "Migration $migration_name failed with exit code $exit_code"
    fi

    log_migration "$migration_name" "Migration completed successfully"

    # Update migration version
    mkdir -p "$(dirname "$MIGRATION_VERSION_FILE")"
    echo "$migration_version" > "$MIGRATION_VERSION_FILE"
}

# Run all pending migrations
run_pending_migrations() {
    local migrations_dir="${1:-migrations}"

    if [[ ! -d "$migrations_dir" ]]; then
        log_warning "No migrations directory found at $migrations_dir"
        return 0
    fi

    local pending_migrations=($(get_pending_migrations "$migrations_dir"))

    if [[ ${#pending_migrations[@]} -eq 0 ]]; then
        log "No pending migrations"
        return 0
    fi

    log "Found ${#pending_migrations[@]} pending migration(s)"

    for migration in "${pending_migrations[@]}"; do
        run_migration "$migration"
    done

    log_success "All pending migrations completed"
}

# Export functions for use in subshells
export -f log log_success log_warning log_error
export -f log_module log_module_success log_module_warning log_module_error
export -f log_migration
export -f show_banner require_root require_debian require_network ensure_log_dir
export -f get_modules run_module
export -f get_migration_version get_pending_migrations run_migration run_pending_migrations
