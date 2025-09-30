#!/bin/bash
#
# health-check.sh - System Health Check Script
#
# Runtime script that monitors system health and performs automatic recovery.
# Designed for continuous monitoring via cron with automatic issue resolution.
#
# Features:
# - Chromium process and responsiveness monitoring
# - Memory usage monitoring with cache clearing
# - Node.js application server health verification
# - Disk space monitoring and cleanup
# - Network connectivity validation
# - Automatic service restart and recovery
# - Hardware watchdog feeding
# - Intelligent logging with spam prevention
#
# Usage:
#   health-check.sh [options]
#
# Options:
#   --verbose         Enable verbose output
#   --dry-run        Show what would be done without doing it
#   --force-restart  Force restart services even if healthy
#   --skip-watchdog  Skip hardware watchdog feeding
#   --config FILE    Use alternative config file
#

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_PID="$$"
readonly LOG_DIR="/var/log"
readonly LOG_FILE="$LOG_DIR/health-check.log"
readonly STATE_DIR="/var/lib/kioskbook"
readonly CONFIG_FILE="/etc/kioskbook/health-check.conf"
readonly LOCK_FILE="/var/run/health-check.lock"

# Watchdog device
readonly WATCHDOG_DEVICE="/dev/watchdog"
readonly WATCHDOG_TIMEOUT=60

# Health check thresholds
readonly MEMORY_WARNING_THRESHOLD=80  # % of total memory
readonly MEMORY_CRITICAL_THRESHOLD=90 # % of total memory
readonly DISK_WARNING_THRESHOLD=80    # % of partition
readonly DISK_CRITICAL_THRESHOLD=90   # % of partition
readonly APP_RESPONSE_TIMEOUT=10      # seconds
readonly CHROMIUM_RESPONSE_TIMEOUT=5  # seconds

# Service names
readonly APP_SERVICE="kiosk-app"
readonly DISPLAY_SERVICE="kiosk-display"

# Default configuration
DEFAULT_VERBOSE=false
DEFAULT_DRY_RUN=false
DEFAULT_FORCE_RESTART=false
DEFAULT_SKIP_WATCHDOG=false
DEFAULT_CHECK_INTERVAL=60
DEFAULT_LOG_RETENTION_DAYS=7

# Runtime configuration
VERBOSE="$DEFAULT_VERBOSE"
DRY_RUN="$DEFAULT_DRY_RUN"
FORCE_RESTART="$DEFAULT_FORCE_RESTART"
SKIP_WATCHDOG="$DEFAULT_SKIP_WATCHDOG"
CHECK_INTERVAL="$DEFAULT_CHECK_INTERVAL"
LOG_RETENTION_DAYS="$DEFAULT_LOG_RETENTION_DAYS"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_WARNING=1
readonly EXIT_CRITICAL=2
readonly EXIT_ERROR=3

# Global health status
HEALTH_STATUS="HEALTHY"
ISSUES_FOUND=()
ACTIONS_TAKEN=()

# Logging functions with spam prevention
log_with_level() {
    local level="$1"
    local message="$2"
    local hash="$3"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local log_line="$timestamp [$level] [PID:$SCRIPT_PID] $message"
    
    # Spam prevention: check if we've logged this exact message recently
    local spam_file="$STATE_DIR/log-spam-${hash}"
    local current_time="$(date +%s)"
    local spam_threshold=300  # 5 minutes
    
    if [[ -f "$spam_file" ]]; then
        local last_log_time
        last_log_time="$(cat "$spam_file" 2>/dev/null || echo "0")"
        local time_diff=$((current_time - last_log_time))
        
        if [[ "$time_diff" -lt "$spam_threshold" ]]; then
            # Skip logging this message to prevent spam
            return 0
        fi
    fi
    
    # Log the message
    if [[ -w "$LOG_DIR" ]]; then
        echo "$log_line" >> "$LOG_FILE" 2>/dev/null || true
    fi
    
    # Update spam prevention timestamp
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    echo "$current_time" > "$spam_file" 2>/dev/null || true
    
    # Console output based on verbosity
    case "$level" in
        "ERROR"|"CRITICAL")
            echo "$log_line" >&2
            ;;
        "WARNING")
            [[ "$VERBOSE" == "true" ]] && echo "$log_line" >&2
            ;;
        "INFO")
            [[ "$VERBOSE" == "true" ]] && echo "$log_line"
            ;;
        "DEBUG")
            [[ "$VERBOSE" == "true" ]] && echo "$log_line"
            ;;
    esac
}

log_info() {
    local hash="$(echo "$1" | sha256sum | cut -d' ' -f1 | head -c8)"
    log_with_level "INFO" "$1" "$hash"
}

log_warning() {
    local hash="$(echo "$1" | sha256sum | cut -d' ' -f1 | head -c8)"
    log_with_level "WARNING" "$1" "$hash"
    HEALTH_STATUS="WARNING"
}

log_error() {
    local hash="$(echo "$1" | sha256sum | cut -d' ' -f1 | head -c8)"
    log_with_level "ERROR" "$1" "$hash"
    HEALTH_STATUS="CRITICAL"
}

log_critical() {
    local hash="$(echo "$1" | sha256sum | cut -d' ' -f1 | head -c8)"
    log_with_level "CRITICAL" "$1" "$hash"
    HEALTH_STATUS="CRITICAL"
}

# Add issue to tracking
add_issue() {
    ISSUES_FOUND+=("$1")
}

# Add action to tracking
add_action() {
    ACTIONS_TAKEN+=("$1")
}

# Error handling
cleanup() {
    # Remove lock file
    [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE" 2>/dev/null || true
}

trap cleanup EXIT

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force-restart)
                FORCE_RESTART=true
                shift
                ;;
            --skip-watchdog)
                SKIP_WATCHDOG=true
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit $EXIT_SUCCESS
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit $EXIT_ERROR
                ;;
        esac
    done
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

System health check and automatic recovery for KioskBook kiosk systems.

Options:
  --verbose         Enable verbose output
  --dry-run        Show what would be done without doing it
  --force-restart  Force restart services even if healthy
  --skip-watchdog  Skip hardware watchdog feeding
  --config FILE    Use alternative config file
  --help           Show this help message

This script performs comprehensive health checks and automatic recovery:
- Chromium process and responsiveness monitoring
- Memory usage monitoring with cache clearing
- Node.js application server health verification
- Disk space monitoring and cleanup
- Network connectivity validation
- Automatic service restart and recovery
- Hardware watchdog feeding

Exit codes:
  $EXIT_SUCCESS - All checks passed (HEALTHY)
  $EXIT_WARNING - Issues found but resolved (WARNING)
  $EXIT_CRITICAL - Critical issues found (CRITICAL)
  $EXIT_ERROR - Script execution error
EOF
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE" || {
            log_warning "Failed to load configuration file: $CONFIG_FILE"
        }
    fi
}

# Create lock file
create_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
        
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another instance is already running (PID: $lock_pid)"
            exit $EXIT_ERROR
        else
            log_warning "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo "$SCRIPT_PID" > "$LOCK_FILE" || {
        log_error "Failed to create lock file: $LOCK_FILE"
        exit $EXIT_ERROR
    }
}

# Feed hardware watchdog
feed_watchdog() {
    if [[ "$SKIP_WATCHDOG" == "true" ]]; then
        return 0
    fi
    
    if [[ -c "$WATCHDOG_DEVICE" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would feed hardware watchdog"
        else
            echo "w" > "$WATCHDOG_DEVICE" 2>/dev/null || {
                log_warning "Failed to feed hardware watchdog"
                return 1
            }
            log_info "Hardware watchdog fed successfully"
        fi
    else
        log_info "Hardware watchdog device not available: $WATCHDOG_DEVICE"
    fi
}

# Check if Chromium is running
check_chromium_process() {
    log_info "Checking Chromium process..."
    
    local chromium_pids
    chromium_pids="$(pgrep -f "chromium.*--kiosk" 2>/dev/null || echo "")"
    
    if [[ -z "$chromium_pids" ]]; then
        add_issue "Chromium process not running"
        log_error "Chromium kiosk process not found"
        return 1
    fi
    
    # Check if process is responsive (not zombie)
    local responsive_count=0
    for pid in $chromium_pids; do
        if [[ -d "/proc/$pid" ]]; then
            local state
            state="$(cat "/proc/$pid/stat" 2>/dev/null | cut -d' ' -f3 || echo "")"
            if [[ "$state" != "Z" ]]; then
                ((responsive_count++))
            fi
        fi
    done
    
    if [[ "$responsive_count" -eq 0 ]]; then
        add_issue "Chromium processes are zombie/unresponsive"
        log_error "All Chromium processes are unresponsive"
        return 1
    fi
    
    log_info "Chromium process check passed ($responsive_count responsive processes)"
    return 0
}

# Check Chromium responsiveness via X11
check_chromium_responsiveness() {
    log_info "Checking Chromium responsiveness..."
    
    # Check if X11 is running and accessible
    if ! DISPLAY=:0 xset q >/dev/null 2>&1; then
        add_issue "X11 display not accessible"
        log_error "X11 display :0 not accessible"
        return 1
    fi
    
    # Try to get window information
    local window_count
    window_count="$(DISPLAY=:0 xwininfo -root -children 2>/dev/null | grep -c "chromium" || echo "0")"
    
    if [[ "$window_count" -eq 0 ]]; then
        add_issue "No Chromium windows detected"
        log_warning "No Chromium windows found in X11"
        return 1
    fi
    
    log_info "Chromium responsiveness check passed ($window_count windows)"
    return 0
}

# Monitor memory usage
check_memory_usage() {
    log_info "Checking memory usage..."
    
    # Get memory information
    local mem_total mem_available mem_used mem_usage_percent
    
    mem_total="$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')"
    mem_available="$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')"
    mem_used=$((mem_total - mem_available))
    mem_usage_percent=$((mem_used * 100 / mem_total))
    
    log_info "Memory usage: ${mem_usage_percent}% (${mem_used}KB/${mem_total}KB)"
    
    if [[ "$mem_usage_percent" -ge "$MEMORY_CRITICAL_THRESHOLD" ]]; then
        add_issue "Critical memory usage: ${mem_usage_percent}%"
        log_critical "Critical memory usage: ${mem_usage_percent}%"
        
        # Attempt to clear caches
        clear_system_caches
        return 1
        
    elif [[ "$mem_usage_percent" -ge "$MEMORY_WARNING_THRESHOLD" ]]; then
        add_issue "High memory usage: ${mem_usage_percent}%"
        log_warning "High memory usage: ${mem_usage_percent}%"
        
        # Clear Chromium cache
        clear_chromium_cache
        return 1
    fi
    
    log_info "Memory usage check passed"
    return 0
}

# Clear Chromium cache
clear_chromium_cache() {
    log_info "Clearing Chromium cache..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clear Chromium cache"
        return 0
    fi
    
    # Clear Chromium cache directories for kiosk user
    local cache_dirs=(
        "/home/kiosk/.cache/chromium"
        "/home/kiosk/.config/chromium/Default/Service Worker"
        "/tmp/.org.chromium.Chromium*"
    )
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            rm -rf "$cache_dir" 2>/dev/null || {
                log_warning "Failed to clear cache directory: $cache_dir"
            }
        fi
    done
    
    add_action "Cleared Chromium cache"
    log_info "Chromium cache cleared"
}

# Clear system caches
clear_system_caches() {
    log_info "Clearing system caches..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clear system caches"
        return 0
    fi
    
    # Drop page cache, dentries and inodes
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || {
        log_warning "Failed to drop system caches"
        return 1
    }
    
    # Clear temporary files
    find /tmp -type f -mtime +1 -delete 2>/dev/null || true
    find /var/tmp -type f -mtime +1 -delete 2>/dev/null || true
    
    add_action "Cleared system caches"
    log_info "System caches cleared"
}

# Check Node.js application server
check_app_server() {
    log_info "Checking Node.js application server..."
    
    # Check if service is running
    if ! rc-service "$APP_SERVICE" status >/dev/null 2>&1; then
        add_issue "Node.js application service not running"
        log_error "Service $APP_SERVICE is not running"
        return 1
    fi
    
    # Check if process is actually running
    local node_pids
    node_pids="$(pgrep -f "node.*server.js" 2>/dev/null || echo "")"
    
    if [[ -z "$node_pids" ]]; then
        add_issue "Node.js server process not found"
        log_error "Node.js server process not found"
        return 1
    fi
    
    # Test HTTP responsiveness
    local health_url="http://localhost:3000/health"
    local response_code
    
    response_code="$(curl --silent --max-time "$APP_RESPONSE_TIMEOUT" --write-out "%{http_code}" --output /dev/null "$health_url" 2>/dev/null || echo "000")"
    
    if [[ "$response_code" != "200" ]]; then
        add_issue "Node.js server not responding (HTTP $response_code)"
        log_error "Node.js server health check failed (HTTP $response_code)"
        return 1
    fi
    
    # Check response content
    local health_response
    health_response="$(curl --silent --max-time "$APP_RESPONSE_TIMEOUT" "$health_url" 2>/dev/null || echo "")"
    
    if ! echo "$health_response" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
        add_issue "Node.js server health response invalid"
        log_warning "Node.js server health response is not healthy"
        return 1
    fi
    
    log_info "Node.js application server check passed"
    return 0
}

# Check disk space
check_disk_space() {
    log_info "Checking disk space..."
    
    # Check /data partition
    local data_usage
    data_usage="$(df /data 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")"
    
    log_info "Disk usage on /data: ${data_usage}%"
    
    if [[ "$data_usage" -ge "$DISK_CRITICAL_THRESHOLD" ]]; then
        add_issue "Critical disk usage on /data: ${data_usage}%"
        log_critical "Critical disk usage on /data: ${data_usage}%"
        
        # Attempt cleanup
        cleanup_disk_space
        return 1
        
    elif [[ "$data_usage" -ge "$DISK_WARNING_THRESHOLD" ]]; then
        add_issue "High disk usage on /data: ${data_usage}%"
        log_warning "High disk usage on /data: ${data_usage}%"
        return 1
    fi
    
    # Check root partition
    local root_usage
    root_usage="$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")"
    
    log_info "Disk usage on /: ${root_usage}%"
    
    if [[ "$root_usage" -ge "$DISK_CRITICAL_THRESHOLD" ]]; then
        add_issue "Critical disk usage on /: ${root_usage}%"
        log_critical "Critical disk usage on /: ${root_usage}%"
        return 1
    fi
    
    log_info "Disk space check passed"
    return 0
}

# Clean up disk space
cleanup_disk_space() {
    log_info "Cleaning up disk space..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up disk space"
        return 0
    fi
    
    # Clean up old backups (keep last 3)
    find /data/content -maxdepth 1 -name "backup-*" -type d | sort -r | tail -n +4 | xargs rm -rf 2>/dev/null || true
    
    # Clean up old logs
    find /var/log -name "*.log" -mtime +7 -delete 2>/dev/null || true
    find /var/log -name "*.log.*" -mtime +3 -delete 2>/dev/null || true
    
    # Clean up temporary files
    find /tmp -type f -mtime +1 -delete 2>/dev/null || true
    find /var/tmp -type f -mtime +1 -delete 2>/dev/null || true
    
    # Clean up package cache
    apk cache clean 2>/dev/null || true
    
    add_action "Cleaned up disk space"
    log_info "Disk space cleanup completed"
}

# Check network connectivity
check_network_connectivity() {
    log_info "Checking network connectivity..."
    
    # Check if network interface is up
    local active_interfaces
    active_interfaces="$(ip link show up 2>/dev/null | grep -E '^[0-9]+:' | grep -v 'lo:' | wc -l || echo "0")"
    
    if [[ "$active_interfaces" -eq 0 ]]; then
        add_issue "No active network interfaces"
        log_error "No active network interfaces found"
        return 1
    fi
    
    # Test DNS resolution
    if ! nslookup google.com >/dev/null 2>&1; then
        add_issue "DNS resolution failed"
        log_error "DNS resolution test failed"
        return 1
    fi
    
    # Test internet connectivity
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        add_issue "Internet connectivity failed"
        log_error "Internet connectivity test failed"
        return 1
    fi
    
    log_info "Network connectivity check passed"
    return 0
}

# Restart service with safety checks
restart_service() {
    local service_name="$1"
    
    log_info "Restarting service: $service_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restart service: $service_name"
        return 0
    fi
    
    # Stop service gracefully
    if rc-service "$service_name" stop 2>/dev/null; then
        log_info "Service $service_name stopped"
    else
        log_warning "Failed to stop service $service_name gracefully"
    fi
    
    # Wait a moment for cleanup
    sleep 2
    
    # Start service
    if rc-service "$service_name" start 2>/dev/null; then
        log_info "Service $service_name started"
        add_action "Restarted service: $service_name"
        
        # Wait for service to stabilize
        sleep 5
        
        # Verify service is running
        if rc-service "$service_name" status >/dev/null 2>&1; then
            log_info "Service $service_name restart successful"
            return 0
        else
            log_error "Service $service_name failed to start after restart"
            return 1
        fi
    else
        log_error "Failed to start service: $service_name"
        return 1
    fi
}

# Perform recovery actions
perform_recovery() {
    log_info "Performing recovery actions..."
    
    local recovery_needed=false
    
    # Check if Chromium needs restart
    if ! check_chromium_process || ! check_chromium_responsiveness; then
        log_warning "Chromium issues detected, restarting display service"
        if restart_service "$DISPLAY_SERVICE"; then
            recovery_needed=true
        fi
    fi
    
    # Check if Node.js app needs restart
    if ! check_app_server; then
        log_warning "Node.js application issues detected, restarting app service"
        if restart_service "$APP_SERVICE"; then
            recovery_needed=true
        fi
    fi
    
    # Force restart if requested
    if [[ "$FORCE_RESTART" == "true" ]]; then
        log_info "Force restart requested"
        restart_service "$APP_SERVICE"
        restart_service "$DISPLAY_SERVICE"
        recovery_needed=true
    fi
    
    if [[ "$recovery_needed" == "true" ]]; then
        log_info "Recovery actions completed, waiting for services to stabilize"
        sleep 10
    fi
}

# Clean up old logs
cleanup_logs() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Clean up health check logs older than retention period
    find "$LOG_DIR" -name "health-check.log*" -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
    
    # Clean up spam prevention files older than 1 day
    find "$STATE_DIR" -name "log-spam-*" -mtime +1 -delete 2>/dev/null || true
}

# Generate health report
generate_health_report() {
    local report_status="$HEALTH_STATUS"
    local issues_count="${#ISSUES_FOUND[@]}"
    local actions_count="${#ACTIONS_TAKEN[@]}"
    
    log_info "=== Health Check Summary ==="
    log_info "Status: $report_status"
    log_info "Issues found: $issues_count"
    log_info "Actions taken: $actions_count"
    
    if [[ "$issues_count" -gt 0 ]]; then
        log_info "Issues detected:"
        for issue in "${ISSUES_FOUND[@]}"; do
            log_info "  - $issue"
        done
    fi
    
    if [[ "$actions_count" -gt 0 ]]; then
        log_info "Recovery actions taken:"
        for action in "${ACTIONS_TAKEN[@]}"; do
            log_info "  - $action"
        done
    fi
    
    log_info "=== End Health Check Summary ==="
}

# Main health check function
main() {
    log_info "Starting health check (PID: $SCRIPT_PID)"
    
    # Parse arguments and load configuration
    parse_arguments "$@"
    load_config
    
    # Setup environment
    create_lock
    mkdir -p "$STATE_DIR" 2>/dev/null || true
    
    # Perform health checks
    check_memory_usage || true
    check_disk_space || true
    check_network_connectivity || true
    check_app_server || true
    check_chromium_process || true
    check_chromium_responsiveness || true
    
    # Perform recovery if needed
    perform_recovery
    
    # Feed watchdog
    feed_watchdog
    
    # Cleanup
    cleanup_logs
    
    # Generate report
    generate_health_report
    
    # Determine exit code based on health status
    case "$HEALTH_STATUS" in
        "HEALTHY")
            log_info "Health check completed: $HEALTH_STATUS"
            exit $EXIT_SUCCESS
            ;;
        "WARNING")
            log_warning "Health check completed: $HEALTH_STATUS"
            exit $EXIT_WARNING
            ;;
        "CRITICAL")
            log_critical "Health check completed: $HEALTH_STATUS"
            exit $EXIT_CRITICAL
            ;;
        *)
            log_error "Unknown health status: $HEALTH_STATUS"
            exit $EXIT_ERROR
            ;;
    esac
}

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    local required_deps=("curl" "jq" "pgrep" "rc-service")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Missing required dependencies: ${missing_deps[*]}" >&2
        exit $EXIT_ERROR
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check dependencies first
    check_dependencies
    
    # Run main function
    main "$@"
fi