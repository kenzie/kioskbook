#!/bin/bash
#
# content-sync.sh - Content Synchronization Script
#
# Runtime script that synchronizes application content and data from remote sources.
# Handles atomic updates, validation, retry logic, and bandwidth limiting.
#
# Features:
# - Atomic updates using staging directory
# - Manifest-based content synchronization
# - Network failure retry logic with exponential backoff
# - Bandwidth limiting for large files
# - Comprehensive logging and validation
# - Cron-friendly with proper exit codes
#
# Usage:
#   content-sync.sh [options]
#
# Options:
#   --manifest-url URL    Override manifest URL
#   --bandwidth LIMIT     Set bandwidth limit (e.g., 1M, 500K)
#   --max-retries NUM     Maximum retry attempts (default: 3)
#   --timeout SEC         Download timeout in seconds (default: 300)
#   --dry-run            Show what would be downloaded without doing it
#   --force              Force download even if content is up to date
#   --verbose            Enable verbose logging
#   --quiet              Suppress all output except errors
#

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_PID="$$"
readonly CONTENT_DIR="/data/content"
readonly CURRENT_DIR="$CONTENT_DIR/current"
readonly STAGING_DIR="$CONTENT_DIR/staging"
readonly CACHE_DIR="$CONTENT_DIR/cache"
readonly TEMP_DIR="$CONTENT_DIR/temp"
readonly LOG_DIR="/var/log"
readonly LOG_FILE="$LOG_DIR/content-sync.log"
readonly LOCK_FILE="/var/run/content-sync.lock"
readonly CONFIG_FILE="/etc/kioskbook/content-sync.conf"

# Default configuration
DEFAULT_MANIFEST_URL=""
DEFAULT_BANDWIDTH_LIMIT=""
DEFAULT_MAX_RETRIES=3
DEFAULT_TIMEOUT=300
DEFAULT_USER_AGENT="KioskBook-ContentSync/1.0"

# Runtime configuration (can be overridden by arguments)
MANIFEST_URL="$DEFAULT_MANIFEST_URL"
BANDWIDTH_LIMIT="$DEFAULT_BANDWIDTH_LIMIT"
MAX_RETRIES="$DEFAULT_MAX_RETRIES"
TIMEOUT="$DEFAULT_TIMEOUT"
USER_AGENT="$DEFAULT_USER_AGENT"
DRY_RUN=false
FORCE_UPDATE=false
VERBOSE=false
QUIET=false

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_NETWORK_ERROR=2
readonly EXIT_VALIDATION_ERROR=3
readonly EXIT_LOCK_ERROR=4
readonly EXIT_CONFIG_ERROR=5

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="$timestamp [$level] [PID:$SCRIPT_PID] $message"
    
    # Always log to file if possible
    if [[ -w "$LOG_DIR" ]]; then
        echo "$log_line" >> "$LOG_FILE" 2>/dev/null || true
    fi
    
    # Console output based on verbosity settings
    case "$level" in
        "ERROR")
            echo "$log_line" >&2
            ;;
        "WARN")
            [[ "$QUIET" != "true" ]] && echo "$log_line" >&2
            ;;
        "INFO")
            [[ "$QUIET" != "true" ]] && echo "$log_line"
            ;;
        "DEBUG")
            [[ "$VERBOSE" == "true" ]] && echo "$log_line"
            ;;
    esac
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Error handling
error_exit() {
    local exit_code="${2:-$EXIT_GENERAL_ERROR}"
    log_error "$1"
    cleanup
    exit "$exit_code"
}

# Cleanup function
cleanup() {
    log_debug "Cleaning up temporary files and locks..."
    
    # Remove lock file
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE" 2>/dev/null || true
    
    # Clean up temporary directory
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
    
    log_debug "Cleanup completed"
}

# Signal handlers
trap 'error_exit "Script interrupted by signal" $EXIT_GENERAL_ERROR' INT TERM
trap 'cleanup' EXIT

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

Content synchronization script for KioskBook kiosk systems.

Options:
  --manifest-url URL     Override manifest URL
  --bandwidth LIMIT      Set bandwidth limit (e.g., 1M, 500K)
  --max-retries NUM      Maximum retry attempts (default: $DEFAULT_MAX_RETRIES)
  --timeout SEC          Download timeout in seconds (default: $DEFAULT_TIMEOUT)
  --dry-run             Show what would be downloaded without doing it
  --force               Force download even if content is up to date
  --verbose             Enable verbose logging
  --quiet               Suppress all output except errors
  --help                Show this help message

Examples:
  $SCRIPT_NAME --manifest-url https://example.com/manifest.json
  $SCRIPT_NAME --bandwidth 500K --max-retries 5
  $SCRIPT_NAME --dry-run --verbose

Configuration file: $CONFIG_FILE
Log file: $LOG_FILE

Exit codes:
  $EXIT_SUCCESS - Success
  $EXIT_GENERAL_ERROR - General error
  $EXIT_NETWORK_ERROR - Network error
  $EXIT_VALIDATION_ERROR - Validation error
  $EXIT_LOCK_ERROR - Lock file error
  $EXIT_CONFIG_ERROR - Configuration error
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --manifest-url)
                MANIFEST_URL="$2"
                shift 2
                ;;
            --bandwidth)
                BANDWIDTH_LIMIT="$2"
                shift 2
                ;;
            --max-retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_UPDATE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --help)
                usage
                exit $EXIT_SUCCESS
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit $EXIT_CONFIG_ERROR
                ;;
        esac
    done
}

# Load configuration file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_debug "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE" || {
            log_warn "Failed to load configuration file: $CONFIG_FILE"
        }
        
        # Override defaults with config file values
        MANIFEST_URL="${MANIFEST_URL:-${CONFIG_MANIFEST_URL:-}}"
        BANDWIDTH_LIMIT="${BANDWIDTH_LIMIT:-${CONFIG_BANDWIDTH_LIMIT:-}}"
        MAX_RETRIES="${MAX_RETRIES:-${CONFIG_MAX_RETRIES:-$DEFAULT_MAX_RETRIES}}"
        TIMEOUT="${TIMEOUT:-${CONFIG_TIMEOUT:-$DEFAULT_TIMEOUT}}"
        USER_AGENT="${USER_AGENT:-${CONFIG_USER_AGENT:-$DEFAULT_USER_AGENT}}"
    else
        log_debug "No configuration file found at $CONFIG_FILE"
    fi
}

# Validate configuration
validate_config() {
    # Check required configuration
    if [[ -z "$MANIFEST_URL" ]]; then
        error_exit "Manifest URL not configured. Use --manifest-url or set CONFIG_MANIFEST_URL in $CONFIG_FILE" $EXIT_CONFIG_ERROR
    fi
    
    # Validate numeric values
    if ! [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]] || [[ "$MAX_RETRIES" -lt 0 ]]; then
        error_exit "Invalid max retries value: $MAX_RETRIES" $EXIT_CONFIG_ERROR
    fi
    
    if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -lt 1 ]]; then
        error_exit "Invalid timeout value: $TIMEOUT" $EXIT_CONFIG_ERROR
    fi
    
    log_debug "Configuration validated successfully"
    log_debug "Manifest URL: $MANIFEST_URL"
    log_debug "Max retries: $MAX_RETRIES"
    log_debug "Timeout: $TIMEOUT seconds"
    [[ -n "$BANDWIDTH_LIMIT" ]] && log_debug "Bandwidth limit: $BANDWIDTH_LIMIT"
}

# Create lock file
create_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
        
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            error_exit "Another instance is already running (PID: $lock_pid)" $EXIT_LOCK_ERROR
        else
            log_warn "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo "$SCRIPT_PID" > "$LOCK_FILE" || {
        error_exit "Failed to create lock file: $LOCK_FILE" $EXIT_LOCK_ERROR
    }
    
    log_debug "Lock file created: $LOCK_FILE"
}

# Setup directories
setup_directories() {
    log_debug "Setting up directories..."
    
    local dirs=("$CONTENT_DIR" "$CURRENT_DIR" "$STAGING_DIR" "$CACHE_DIR" "$TEMP_DIR")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || {
                error_exit "Failed to create directory: $dir" $EXIT_GENERAL_ERROR
            }
            log_debug "Created directory: $dir"
        fi
    done
    
    # Set appropriate permissions
    chmod 755 "$CONTENT_DIR" "$STAGING_DIR" "$CACHE_DIR" "$TEMP_DIR" 2>/dev/null || true
    
    log_debug "Directories setup completed"
}

# Check network connectivity
check_connectivity() {
    log_debug "Checking network connectivity..."
    
    # Extract host from manifest URL
    local host
    host="$(echo "$MANIFEST_URL" | sed -E 's|^https?://([^/]+).*|\1|')"
    
    if [[ -z "$host" ]]; then
        error_exit "Invalid manifest URL: $MANIFEST_URL" $EXIT_CONFIG_ERROR
    fi
    
    # Try to resolve hostname and ping
    if ! nslookup "$host" >/dev/null 2>&1; then
        error_exit "DNS resolution failed for host: $host" $EXIT_NETWORK_ERROR
    fi
    
    log_debug "Network connectivity verified for host: $host"
}

# Download file with retry logic
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local file_type="${3:-file}"
    local attempt=1
    local max_attempts=$((MAX_RETRIES + 1))
    
    log_debug "Downloading $file_type: $url -> $output_file"
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Download attempt $attempt/$max_attempts"
        
        # Build curl command
        local curl_cmd=(
            "curl"
            "--silent"
            "--show-error"
            "--fail"
            "--location"
            "--user-agent" "$USER_AGENT"
            "--connect-timeout" "30"
            "--max-time" "$TIMEOUT"
            "--retry" "0"  # We handle retries ourselves
            "--output" "$output_file"
        )
        
        # Add bandwidth limiting for large files
        if [[ -n "$BANDWIDTH_LIMIT" && "$file_type" == "media" ]]; then
            curl_cmd+=("--limit-rate" "$BANDWIDTH_LIMIT")
            log_debug "Applying bandwidth limit: $BANDWIDTH_LIMIT"
        fi
        
        # Add resume support for large files
        if [[ "$file_type" == "media" && -f "$output_file" ]]; then
            curl_cmd+=("--continue-at" "-")
            log_debug "Attempting to resume download"
        fi
        
        curl_cmd+=("$url")
        
        # Execute download
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would download: $url"
            return 0
        fi
        
        local start_time
        start_time="$(date +%s)"
        
        if "${curl_cmd[@]}" 2>/dev/null; then
            local end_time
            end_time="$(date +%s)"
            local duration=$((end_time - start_time))
            
            # Verify file was downloaded
            if [[ -f "$output_file" && -s "$output_file" ]]; then
                local file_size
                file_size="$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null || echo "0")"
                log_info "Downloaded $file_type successfully: $(basename "$output_file") (${file_size} bytes, ${duration}s)"
                return 0
            else
                log_warn "Download completed but file is empty or missing: $output_file"
            fi
        else
            local curl_exit_code=$?
            log_warn "Download attempt $attempt failed (curl exit code: $curl_exit_code)"
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            local backoff_time=$((2 ** (attempt - 1)))
            log_info "Retrying in $backoff_time seconds..."
            sleep "$backoff_time"
        fi
        
        ((attempt++))
    done
    
    error_exit "Failed to download after $MAX_RETRIES retries: $url" $EXIT_NETWORK_ERROR
}

# Download and parse manifest
download_manifest() {
    log_info "Downloading manifest from: $MANIFEST_URL"
    
    local manifest_file="$TEMP_DIR/manifest.json"
    
    download_with_retry "$MANIFEST_URL" "$manifest_file" "manifest"
    
    # Validate JSON syntax
    if ! jq . "$manifest_file" >/dev/null 2>&1; then
        error_exit "Invalid JSON in manifest file" $EXIT_VALIDATION_ERROR
    fi
    
    # Check required manifest fields
    local required_fields=("version" "files")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$manifest_file" >/dev/null 2>&1; then
            error_exit "Missing required field in manifest: $field" $EXIT_VALIDATION_ERROR
        fi
    done
    
    echo "$manifest_file"
}

# Get file checksum
get_file_checksum() {
    local file="$1"
    
    if [[ -f "$file" ]]; then
        sha256sum "$file" 2>/dev/null | cut -d' ' -f1 || echo ""
    else
        echo ""
    fi
}

# Validate downloaded file
validate_file() {
    local file="$1"
    local expected_checksum="$2"
    local file_type="${3:-file}"
    
    if [[ ! -f "$file" ]]; then
        log_error "File does not exist: $file"
        return 1
    fi
    
    if [[ ! -s "$file" ]]; then
        log_error "File is empty: $file"
        return 1
    fi
    
    # Validate checksum if provided
    if [[ -n "$expected_checksum" ]]; then
        local actual_checksum
        actual_checksum="$(get_file_checksum "$file")"
        
        if [[ "$actual_checksum" != "$expected_checksum" ]]; then
            log_error "Checksum mismatch for $file_type: $file"
            log_error "Expected: $expected_checksum"
            log_error "Actual: $actual_checksum"
            return 1
        fi
        
        log_debug "Checksum validated for $file_type: $(basename "$file")"
    fi
    
    # Additional validation based on file type
    case "$file_type" in
        "json")
            if ! jq . "$file" >/dev/null 2>&1; then
                log_error "Invalid JSON file: $file"
                return 1
            fi
            ;;
        "image")
            # Basic image validation (check for common headers)
            local file_header
            file_header="$(head -c 16 "$file" 2>/dev/null | xxd -p 2>/dev/null || echo "")"
            
            if [[ ! "$file_header" =~ ^(ffd8ff|89504e47|47494638|424d|52494646) ]]; then
                log_warn "File may not be a valid image: $file"
            fi
            ;;
        "video")
            # Basic video validation (check file size)
            local file_size
            file_size="$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")"
            
            if [[ "$file_size" -lt 1024 ]]; then
                log_error "Video file appears to be too small: $file ($file_size bytes)"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# Download all files from manifest
download_files() {
    local manifest_file="$1"
    local files_downloaded=0
    local files_skipped=0
    local files_failed=0
    
    log_info "Processing files from manifest..."
    
    # Read files array from manifest
    local files_count
    files_count="$(jq '.files | length' "$manifest_file")"
    
    if [[ "$files_count" -eq 0 ]]; then
        log_warn "No files listed in manifest"
        return 0
    fi
    
    log_info "Found $files_count files in manifest"
    
    # Process each file
    for ((i = 0; i < files_count; i++)); do
        local file_info
        file_info="$(jq -r ".files[$i]" "$manifest_file")"
        
        local url
        local filename
        local checksum
        local file_type
        
        url="$(echo "$file_info" | jq -r '.url')"
        filename="$(echo "$file_info" | jq -r '.filename')"
        checksum="$(echo "$file_info" | jq -r '.checksum // empty')"
        file_type="$(echo "$file_info" | jq -r '.type // "file"')"
        
        if [[ "$url" == "null" || "$filename" == "null" ]]; then
            log_error "Invalid file entry in manifest at index $i"
            ((files_failed++))
            continue
        fi
        
        local staging_file="$STAGING_DIR/$filename"
        local current_file="$CURRENT_DIR/$filename"
        
        # Create subdirectories if needed
        local staging_dir
        staging_dir="$(dirname "$staging_file")"
        [[ ! -d "$staging_dir" ]] && mkdir -p "$staging_dir"
        
        # Check if file needs updating
        local needs_update=true
        
        if [[ "$FORCE_UPDATE" != "true" && -f "$current_file" && -n "$checksum" ]]; then
            local current_checksum
            current_checksum="$(get_file_checksum "$current_file")"
            
            if [[ "$current_checksum" == "$checksum" ]]; then
                log_debug "File up to date, copying to staging: $filename"
                cp "$current_file" "$staging_file" 2>/dev/null || {
                    log_warn "Failed to copy current file to staging: $filename"
                    needs_update=true
                }
                needs_update=false
                ((files_skipped++))
            fi
        fi
        
        if [[ "$needs_update" == "true" ]]; then
            log_info "Downloading file ($((i + 1))/$files_count): $filename"
            
            if download_with_retry "$url" "$staging_file" "$file_type"; then
                if validate_file "$staging_file" "$checksum" "$file_type"; then
                    ((files_downloaded++))
                else
                    log_error "Validation failed for file: $filename"
                    rm -f "$staging_file" 2>/dev/null || true
                    ((files_failed++))
                fi
            else
                ((files_failed++))
            fi
        fi
    done
    
    log_info "File processing summary:"
    log_info "  Downloaded: $files_downloaded"
    log_info "  Skipped (up to date): $files_skipped"
    log_info "  Failed: $files_failed"
    
    if [[ "$files_failed" -gt 0 ]]; then
        error_exit "Some files failed to download" $EXIT_NETWORK_ERROR
    fi
    
    # Copy manifest to staging
    cp "$manifest_file" "$STAGING_DIR/manifest.json" || {
        error_exit "Failed to copy manifest to staging" $EXIT_GENERAL_ERROR
    }
}

# Validate staging directory
validate_staging() {
    log_info "Validating staging directory..."
    
    local manifest_file="$STAGING_DIR/manifest.json"
    
    if [[ ! -f "$manifest_file" ]]; then
        error_exit "Manifest not found in staging directory" $EXIT_VALIDATION_ERROR
    fi
    
    # Verify all files from manifest exist in staging
    local files_count
    files_count="$(jq '.files | length' "$manifest_file")"
    
    for ((i = 0; i < files_count; i++)); do
        local filename
        filename="$(jq -r ".files[$i].filename" "$manifest_file")"
        
        local staging_file="$STAGING_DIR/$filename"
        
        if [[ ! -f "$staging_file" ]]; then
            error_exit "Required file missing from staging: $filename" $EXIT_VALIDATION_ERROR
        fi
    done
    
    log_info "Staging directory validation passed"
}

# Atomic swap from staging to current
atomic_swap() {
    log_info "Performing atomic swap from staging to current..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would perform atomic swap"
        return 0
    fi
    
    # Create backup of current directory
    local backup_dir="$CONTENT_DIR/backup-$(date +%Y%m%d-%H%M%S)"
    
    if [[ -d "$CURRENT_DIR" ]]; then
        log_debug "Creating backup: $backup_dir"
        mv "$CURRENT_DIR" "$backup_dir" || {
            error_exit "Failed to create backup of current directory" $EXIT_GENERAL_ERROR
        }
    fi
    
    # Move staging to current
    log_debug "Moving staging to current"
    mv "$STAGING_DIR" "$CURRENT_DIR" || {
        # Try to restore backup if swap failed
        if [[ -d "$backup_dir" ]]; then
            log_error "Swap failed, attempting to restore backup"
            mv "$backup_dir" "$CURRENT_DIR" || {
                log_error "Failed to restore backup! Manual intervention required."
            }
        fi
        error_exit "Failed to swap staging to current" $EXIT_GENERAL_ERROR
    }
    
    # Clean up old backups (keep last 5)
    log_debug "Cleaning up old backups"
    find "$CONTENT_DIR" -maxdepth 1 -name "backup-*" -type d | sort -r | tail -n +6 | xargs rm -rf 2>/dev/null || true
    
    log_info "Atomic swap completed successfully"
}

# Create staging directory for next sync
recreate_staging() {
    log_debug "Recreating staging directory"
    
    if [[ -d "$STAGING_DIR" ]]; then
        rm -rf "$STAGING_DIR"
    fi
    
    mkdir -p "$STAGING_DIR" || {
        error_exit "Failed to recreate staging directory" $EXIT_GENERAL_ERROR
    }
}

# Generate sync report
generate_report() {
    local manifest_file="$CURRENT_DIR/manifest.json"
    
    if [[ ! -f "$manifest_file" ]]; then
        log_warn "No manifest file found for reporting"
        return
    fi
    
    local version
    local files_count
    local total_size=0
    
    version="$(jq -r '.version // "unknown"' "$manifest_file")"
    files_count="$(jq '.files | length' "$manifest_file")"
    
    # Calculate total size
    while IFS= read -r filename; do
        local file="$CURRENT_DIR/$filename"
        if [[ -f "$file" ]]; then
            local size
            size="$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")"
            total_size=$((total_size + size))
        fi
    done < <(jq -r '.files[].filename' "$manifest_file")
    
    # Convert bytes to human readable format
    local human_size
    if [[ "$total_size" -gt 1073741824 ]]; then
        human_size="$(awk "BEGIN {printf \"%.1f GB\", $total_size/1073741824}")"
    elif [[ "$total_size" -gt 1048576 ]]; then
        human_size="$(awk "BEGIN {printf \"%.1f MB\", $total_size/1048576}")"
    elif [[ "$total_size" -gt 1024 ]]; then
        human_size="$(awk "BEGIN {printf \"%.1f KB\", $total_size/1024}")"
    else
        human_size="${total_size} bytes"
    fi
    
    log_info "Content sync completed successfully"
    log_info "Manifest version: $version"
    log_info "Files synchronized: $files_count"
    log_info "Total content size: $human_size"
}

# Main synchronization function
main() {
    log_info "Starting content synchronization (PID: $SCRIPT_PID)"
    
    # Parse arguments and load configuration
    parse_arguments "$@"
    load_config
    validate_config
    
    # Setup environment
    create_lock
    setup_directories
    check_connectivity
    
    # Download and process content
    local manifest_file
    manifest_file="$(download_manifest)"
    
    download_files "$manifest_file"
    validate_staging
    atomic_swap
    recreate_staging
    
    # Generate report
    generate_report
    
    log_info "Content synchronization completed successfully"
}

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    local required_deps=("curl" "jq" "sha256sum")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing required dependencies: ${missing_deps[*]}" $EXIT_CONFIG_ERROR
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check dependencies first
    check_dependencies
    
    # Run main function
    main "$@"
fi