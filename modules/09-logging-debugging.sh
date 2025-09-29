#!/bin/bash
# KioskBook Logging & Debugging Module

# Setup structured logging and debugging system
setup_logging_debugging() {
    log_step "Setting Up Logging & Debugging System"
    
    # Create logging service
    cat > /mnt/root/etc/init.d/kiosk-logger << 'EOF'
#!/sbin/openrc-run

name="Kiosk Logger"
description="Structured logging and log aggregation"

depend() {
    need net
    after net
}

start() {
    ebegin "Starting kiosk logger"
    # Service runs via cron and log rotation, no persistent daemon needed
    eend 0
}

stop() {
    ebegin "Stopping kiosk logger"
    eend 0
}
EOF
    
    chmod +x /mnt/root/etc/init.d/kiosk-logger
    chroot /mnt/root rc-update add kiosk-logger default
    
    # Create structured logging framework
    cat > /mnt/root/opt/kiosk-logger.sh << 'EOF'
#!/bin/bash
# KioskBook Structured Logging Framework

LOG_DIR="/var/log/kioskbook"
LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "CRITICAL")
CURRENT_LEVEL="INFO"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function with structured format
log() {
    local level="$1"
    local component="$2"
    local message="$3"
    local timestamp=$(date -Iseconds)
    local log_file="$LOG_DIR/${component}.log"
    
    # Check if we should log this level
    local level_num=0
    case "$level" in
        "DEBUG") level_num=0 ;;
        "INFO") level_num=1 ;;
        "WARN") level_num=2 ;;
        "ERROR") level_num=3 ;;
        "CRITICAL") level_num=4 ;;
    esac
    
    local current_level_num=0
    case "$CURRENT_LEVEL" in
        "DEBUG") current_level_num=0 ;;
        "INFO") current_level_num=1 ;;
        "WARN") current_level_num=2 ;;
        "ERROR") current_level_num=3 ;;
        "CRITICAL") current_level_num=4 ;;
    esac
    
    if [ "$level_num" -ge "$current_level_num" ]; then
        echo "$timestamp [$level] $component: $message" >> "$log_file"
        
        # Also log to system log for critical errors
        if [ "$level" = "CRITICAL" ]; then
            logger -t "kioskbook" "[$level] $component: $message"
        fi
    fi
}

# Convenience functions
log_debug() { log "DEBUG" "$1" "$2"; }
log_info() { log "INFO" "$1" "$2"; }
log_warn() { log "WARN" "$1" "$2"; }
log_error() { log "ERROR" "$1" "$2"; }
log_critical() { log "CRITICAL" "$1" "$2"; }

# Set log level
set_log_level() {
    if [[ " ${LOG_LEVELS[@]} " =~ " $1 " ]]; then
        CURRENT_LEVEL="$1"
        log_info "LOGGER" "Log level set to $1"
    else
        log_error "LOGGER" "Invalid log level: $1"
    fi
}

# Log rotation function
rotate_logs() {
    local component="$1"
    local log_file="$LOG_DIR/${component}.log"
    
    if [ -f "$log_file" ] && [ $(stat -c%s "$log_file") -gt 10485760 ]; then # 10MB
        mv "$log_file" "${log_file}.old"
        touch "$log_file"
        chmod 644 "$log_file"
        log_info "LOGGER" "Rotated log file: $log_file"
    fi
}

# Export functions for use in other scripts
export -f log log_debug log_info log_warn log_error log_critical set_log_level rotate_logs
EOF
    
    chmod +x /mnt/root/opt/kiosk-logger.sh
    
    # Create log aggregation script
    cat > /mnt/root/opt/log-aggregator.sh << 'EOF'
#!/bin/bash
# KioskBook Log Aggregation and Analysis

LOG_DIR="/var/log/kioskbook"
AGGREGATED_LOG="$LOG_DIR/kioskbook-combined.log"
ANALYSIS_LOG="$LOG_DIR/kioskbook-analysis.log"

# Source logging framework
source /opt/kiosk-logger.sh

# Aggregate all component logs
aggregate_logs() {
    log_info "AGGREGATOR" "Starting log aggregation"
    
    # Clear previous aggregated log
    > "$AGGREGATED_LOG"
    
    # Combine all component logs with timestamps
    for log_file in "$LOG_DIR"/*.log; do
        if [ -f "$log_file" ] && [ "$(basename "$log_file")" != "kioskbook-combined.log" ]; then
            component=$(basename "$log_file" .log)
            while IFS= read -r line; do
                echo "$line" >> "$AGGREGATED_LOG"
            done < "$log_file"
        fi
    done
    
    # Sort by timestamp
    sort -k1,1 "$AGGREGATED_LOG" > "${AGGREGATED_LOG}.tmp"
    mv "${AGGREGATED_LOG}.tmp" "$AGGREGATED_LOG"
    
    log_info "AGGREGATOR" "Log aggregation completed"
}

# Analyze logs for patterns and issues
analyze_logs() {
    log_info "AGGREGATOR" "Starting log analysis"
    
    # Clear previous analysis
    > "$ANALYSIS_LOG"
    
    echo "=== KioskBook Log Analysis - $(date) ===" >> "$ANALYSIS_LOG"
    echo >> "$ANALYSIS_LOG"
    
    # Count log levels
    echo "Log Level Distribution:" >> "$ANALYSIS_LOG"
    grep -E "\[(DEBUG|INFO|WARN|ERROR|CRITICAL)\]" "$AGGREGATED_LOG" | \
        sed 's/.*\[\([^]]*\)\].*/\1/' | sort | uniq -c | sort -nr >> "$ANALYSIS_LOG"
    echo >> "$ANALYSIS_LOG"
    
    # Count errors by component
    echo "Errors by Component:" >> "$ANALYSIS_LOG"
    grep "\[ERROR\]" "$AGGREGATED_LOG" | \
        sed 's/.*\[ERROR\] \([^:]*\):.*/\1/' | sort | uniq -c | sort -nr >> "$ANALYSIS_LOG"
    echo >> "$ANALYSIS_LOG"
    
    # Recent critical errors
    echo "Recent Critical Errors:" >> "$ANALYSIS_LOG"
    grep "\[CRITICAL\]" "$AGGREGATED_LOG" | tail -10 >> "$ANALYSIS_LOG"
    echo >> "$ANALYSIS_LOG"
    
    # Service restart patterns
    echo "Service Restart Patterns:" >> "$ANALYSIS_LOG"
    grep -i "restart\|recovery\|failed" "$AGGREGATED_LOG" | tail -20 >> "$ANALYSIS_LOG"
    echo >> "$ANALYSIS_LOG"
    
    # Performance issues
    echo "Performance Warnings:" >> "$ANALYSIS_LOG"
    grep -i "slow\|timeout\|memory\|disk" "$AGGREGATED_LOG" | tail -10 >> "$ANALYSIS_LOG"
    echo >> "$ANALYSIS_LOG"
    
    log_info "AGGREGATOR" "Log analysis completed"
}

# Generate daily report
generate_daily_report() {
    local report_file="$LOG_DIR/daily-report-$(date +%Y-%m-%d).txt"
    
    echo "=== KioskBook Daily Report - $(date) ===" > "$report_file"
    echo >> "$report_file"
    
    # System status
    echo "System Status:" >> "$report_file"
    echo "  Uptime: $(uptime)" >> "$report_file"
    echo "  Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')" >> "$report_file"
    echo "  Disk: $(df / | tail -1 | awk '{print $5}')" >> "$report_file"
    echo "  Load: $(cat /proc/loadavg)" >> "$report_file"
    echo >> "$report_file"
    
    # Service status
    echo "Service Status:" >> "$report_file"
    rc-status | grep -E "(kiosk|tailscale)" >> "$report_file"
    echo >> "$report_file"
    
    # Recent errors
    echo "Recent Errors (last 24h):" >> "$report_file"
    find "$LOG_DIR" -name "*.log" -mtime -1 -exec grep -l "\[ERROR\]\|\[CRITICAL\]" {} \; | \
        xargs grep "\[ERROR\]\|\[CRITICAL\]" | tail -20 >> "$report_file"
    echo >> "$report_file"
    
    # Network status
    echo "Network Status:" >> "$report_file"
    echo "  Tailscale: $(tailscale status --json 2>/dev/null | jq -r '.Self.Online // "Offline"')" >> "$report_file"
    echo "  Connections: $(ss -tuln | wc -l)" >> "$report_file"
    echo >> "$report_file"
    
    log_info "AGGREGATOR" "Daily report generated: $report_file"
}

# Main aggregation function
main() {
    aggregate_logs
    analyze_logs
    generate_daily_report
    
    # Clean up old reports (keep last 7 days)
    find "$LOG_DIR" -name "daily-report-*.txt" -mtime +7 -delete
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
EOF
    
    chmod +x /mnt/root/opt/log-aggregator.sh
    
    # Create debug tools
    cat > /mnt/root/opt/kiosk-debug.sh << 'EOF'
#!/bin/bash
# KioskBook Debug Tools

DEBUG_DIR="/var/log/kioskbook/debug"
mkdir -p "$DEBUG_DIR"

# Source logging framework
source /opt/kiosk-logger.sh

# System diagnostics
system_diagnostics() {
    local debug_file="$DEBUG_DIR/system-$(date +%Y%m%d-%H%M%S).txt"
    
    log_info "DEBUG" "Collecting system diagnostics"
    
    echo "=== KioskBook System Diagnostics - $(date) ===" > "$debug_file"
    echo >> "$debug_file"
    
    # System information
    echo "=== System Information ===" >> "$debug_file"
    uname -a >> "$debug_file"
    cat /etc/alpine_release >> "$debug_file"
    echo >> "$debug_file"
    
    # Hardware information
    echo "=== Hardware Information ===" >> "$debug_file"
    lscpu >> "$debug_file"
    echo >> "$debug_file"
    free -h >> "$debug_file"
    echo >> "$debug_file"
    df -h >> "$debug_file"
    echo >> "$debug_file"
    
    # Network information
    echo "=== Network Information ===" >> "$debug_file"
    ip addr show >> "$debug_file"
    echo >> "$debug_file"
    ip route show >> "$debug_file"
    echo >> "$debug_file"
    
    # Service status
    echo "=== Service Status ===" >> "$debug_file"
    rc-status >> "$debug_file"
    echo >> "$debug_file"
    
    # Process information
    echo "=== Process Information ===" >> "$debug_file"
    ps aux >> "$debug_file"
    echo >> "$debug_file"
    
    # Log information
    echo "=== Recent Log Entries ===" >> "$debug_file"
    find /var/log/kioskbook -name "*.log" -exec tail -50 {} \; >> "$debug_file"
    echo >> "$debug_file"
    
    log_info "DEBUG" "System diagnostics saved to $debug_file"
    echo "Diagnostics saved to: $debug_file"
}

# Network diagnostics
network_diagnostics() {
    local debug_file="$DEBUG_DIR/network-$(date +%Y%m%d-%H%M%S).txt"
    
    log_info "DEBUG" "Collecting network diagnostics"
    
    echo "=== KioskBook Network Diagnostics - $(date) ===" > "$debug_file"
    echo >> "$debug_file"
    
    # Network interfaces
    echo "=== Network Interfaces ===" >> "$debug_file"
    ip addr show >> "$debug_file"
    echo >> "$debug_file"
    
    # Routing table
    echo "=== Routing Table ===" >> "$debug_file"
    ip route show >> "$debug_file"
    echo >> "$debug_file"
    
    # DNS configuration
    echo "=== DNS Configuration ===" >> "$debug_file"
    cat /etc/resolv.conf >> "$debug_file"
    echo >> "$debug_file"
    
    # Network connections
    echo "=== Active Connections ===" >> "$debug_file"
    ss -tuln >> "$debug_file"
    echo >> "$debug_file"
    
    # Tailscale status
    echo "=== Tailscale Status ===" >> "$debug_file"
    tailscale status >> "$debug_file" 2>&1
    echo >> "$debug_file"
    
    # Connectivity tests
    echo "=== Connectivity Tests ===" >> "$debug_file"
    ping -c 3 8.8.8.8 >> "$debug_file" 2>&1
    echo >> "$debug_file"
    curl -I http://localhost:3000 >> "$debug_file" 2>&1
    echo >> "$debug_file"
    curl -I http://localhost:3001 >> "$debug_file" 2>&1
    echo >> "$debug_file"
    
    log_info "DEBUG" "Network diagnostics saved to $debug_file"
    echo "Network diagnostics saved to: $debug_file"
}

# Application diagnostics
app_diagnostics() {
    local debug_file="$DEBUG_DIR/app-$(date +%Y%m%d-%H%M%S).txt"
    
    log_info "DEBUG" "Collecting application diagnostics"
    
    echo "=== KioskBook Application Diagnostics - $(date) ===" > "$debug_file"
    echo >> "$debug_file"
    
    # Application status
    echo "=== Application Status ===" >> "$debug_file"
    rc-service kiosk-app status >> "$debug_file" 2>&1
    echo >> "$debug_file"
    rc-service kiosk-browser status >> "$debug_file" 2>&1
    echo >> "$debug_file"
    
    # Application processes
    echo "=== Application Processes ===" >> "$debug_file"
    ps aux | grep -E "(kiosk|chromium|http-server)" >> "$debug_file"
    echo >> "$debug_file"
    
    # Application logs
    echo "=== Application Logs ===" >> "$debug_file"
    tail -100 /var/log/kiosk-app.log >> "$debug_file" 2>/dev/null || echo "No kiosk-app log found" >> "$debug_file"
    echo >> "$debug_file"
    tail -100 /var/log/kiosk-browser.log >> "$debug_file" 2>/dev/null || echo "No kiosk-browser log found" >> "$debug_file"
    echo >> "$debug_file"
    
    # Application files
    echo "=== Application Files ===" >> "$debug_file"
    ls -la /opt/kiosk-app/ >> "$debug_file" 2>&1
    echo >> "$debug_file"
    
    # Application configuration
    echo "=== Application Configuration ===" >> "$debug_file"
    cat /opt/kiosk-app/package.json >> "$debug_file" 2>/dev/null || echo "No package.json found" >> "$debug_file"
    echo >> "$debug_file"
    
    # Browser information
    echo "=== Browser Information ===" >> "$debug_file"
    chromium-browser --version >> "$debug_file" 2>&1
    echo >> "$debug_file"
    
    log_info "DEBUG" "Application diagnostics saved to $debug_file"
    echo "Application diagnostics saved to: $debug_file"
}

# Performance diagnostics
performance_diagnostics() {
    local debug_file="$DEBUG_DIR/performance-$(date +%Y%m%d-%H%M%S).txt"
    
    log_info "DEBUG" "Collecting performance diagnostics"
    
    echo "=== KioskBook Performance Diagnostics - $(date) ===" > "$debug_file"
    echo >> "$debug_file"
    
    # System load
    echo "=== System Load ===" >> "$debug_file"
    uptime >> "$debug_file"
    cat /proc/loadavg >> "$debug_file"
    echo >> "$debug_file"
    
    # Memory usage
    echo "=== Memory Usage ===" >> "$debug_file"
    free -h >> "$debug_file"
    echo >> "$debug_file"
    cat /proc/meminfo >> "$debug_file"
    echo >> "$debug_file"
    
    # CPU usage
    echo "=== CPU Usage ===" >> "$debug_file"
    top -bn1 | head -20 >> "$debug_file"
    echo >> "$debug_file"
    
    # Disk usage
    echo "=== Disk Usage ===" >> "$debug_file"
    df -h >> "$debug_file"
    echo >> "$debug_file"
    du -sh /var/log/* >> "$debug_file" 2>/dev/null
    echo >> "$debug_file"
    
    # Network usage
    echo "=== Network Usage ===" >> "$debug_file"
    cat /proc/net/dev >> "$debug_file"
    echo >> "$debug_file"
    
    # I/O usage
    echo "=== I/O Usage ===" >> "$debug_file"
    iostat 1 3 >> "$debug_file" 2>/dev/null || echo "iostat not available" >> "$debug_file"
    echo >> "$debug_file"
    
    log_info "DEBUG" "Performance diagnostics saved to $debug_file"
    echo "Performance diagnostics saved to: $debug_file"
}

# Comprehensive diagnostics
comprehensive_diagnostics() {
    log_info "DEBUG" "Running comprehensive diagnostics"
    
    system_diagnostics
    network_diagnostics
    app_diagnostics
    performance_diagnostics
    
    # Create summary
    local summary_file="$DEBUG_DIR/summary-$(date +%Y%m%d-%H%M%S).txt"
    
    echo "=== KioskBook Diagnostic Summary - $(date) ===" > "$summary_file"
    echo >> "$summary_file"
    
    echo "System Status:" >> "$summary_file"
    echo "  Uptime: $(uptime)" >> "$summary_file"
    echo "  Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')" >> "$summary_file"
    echo "  Disk: $(df / | tail -1 | awk '{print $5}')" >> "$summary_file"
    echo "  Load: $(cat /proc/loadavg | awk '{print $1}')" >> "$summary_file"
    echo >> "$summary_file"
    
    echo "Service Status:" >> "$summary_file"
    rc-status | grep -E "(kiosk|tailscale)" >> "$summary_file"
    echo >> "$summary_file"
    
    echo "Recent Errors:" >> "$summary_file"
    find /var/log/kioskbook -name "*.log" -exec grep -l "\[ERROR\]\|\[CRITICAL\]" {} \; | \
        xargs grep "\[ERROR\]\|\[CRITICAL\]" | tail -5 >> "$summary_file"
    echo >> "$summary_file"
    
    log_info "DEBUG" "Comprehensive diagnostics completed"
    echo "Comprehensive diagnostics completed. Check $DEBUG_DIR for detailed reports."
}

# Command handler
case "$1" in
    "system")
        system_diagnostics
        ;;
    "network")
        network_diagnostics
        ;;
    "app")
        app_diagnostics
        ;;
    "performance")
        performance_diagnostics
        ;;
    "all"|"comprehensive")
        comprehensive_diagnostics
        ;;
    *)
        echo "Usage: $0 {system|network|app|performance|all}"
        echo
        echo "Commands:"
        echo "  system       Collect system diagnostics"
        echo "  network      Collect network diagnostics"
        echo "  app          Collect application diagnostics"
        echo "  performance  Collect performance diagnostics"
        echo "  all          Run comprehensive diagnostics"
        exit 1
        ;;
esac
EOF
    
    chmod +x /mnt/root/opt/kiosk-debug.sh
    
    # Create log viewer
    cat > /mnt/root/opt/kiosk-logs.sh << 'EOF'
#!/bin/bash
# KioskBook Log Viewer

LOG_DIR="/var/log/kioskbook"

# Source logging framework
source /opt/kiosk-logger.sh

# View specific component logs
view_component_log() {
    local component="$1"
    local log_file="$LOG_DIR/${component}.log"
    
    if [ -f "$log_file" ]; then
        echo "=== $component Log ==="
        tail -50 "$log_file"
    else
        echo "No log file found for component: $component"
    fi
}

# View all logs
view_all_logs() {
    echo "=== All KioskBook Logs ==="
    for log_file in "$LOG_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            component=$(basename "$log_file" .log)
            echo "=== $component ==="
            tail -20 "$log_file"
            echo
        fi
    done
}

# View errors only
view_errors() {
    echo "=== Recent Errors ==="
    find "$LOG_DIR" -name "*.log" -exec grep -l "\[ERROR\]\|\[CRITICAL\]" {} \; | \
        xargs grep "\[ERROR\]\|\[CRITICAL\]" | tail -20
}

# View by log level
view_by_level() {
    local level="$1"
    echo "=== Recent $level Messages ==="
    find "$LOG_DIR" -name "*.log" -exec grep "\[$level\]" {} \; | tail -20
}

# Follow logs in real-time
follow_logs() {
    local component="$1"
    
    if [ -n "$component" ]; then
        local log_file="$LOG_DIR/${component}.log"
        if [ -f "$log_file" ]; then
            tail -f "$log_file"
        else
            echo "No log file found for component: $component"
        fi
    else
        # Follow all logs
        tail -f "$LOG_DIR"/*.log
    fi
}

# Search logs
search_logs() {
    local pattern="$1"
    echo "=== Search Results for: $pattern ==="
    find "$LOG_DIR" -name "*.log" -exec grep -i "$pattern" {} \; | tail -20
}

# Command handler
case "$1" in
    "component")
        view_component_log "$2"
        ;;
    "all")
        view_all_logs
        ;;
    "errors")
        view_errors
        ;;
    "level")
        view_by_level "$2"
        ;;
    "follow")
        follow_logs "$2"
        ;;
    "search")
        search_logs "$2"
        ;;
    *)
        echo "Usage: $0 {component|all|errors|level|follow|search}"
        echo
        echo "Commands:"
        echo "  component <name>  View specific component log"
        echo "  all              View all logs"
        echo "  errors           View recent errors"
        echo "  level <level>    View messages by level (DEBUG|INFO|WARN|ERROR|CRITICAL)"
        echo "  follow [name]    Follow logs in real-time"
        echo "  search <pattern> Search logs for pattern"
        echo
        echo "Available components:"
        ls "$LOG_DIR"/*.log 2>/dev/null | sed 's/.*\///; s/\.log$//' | sort
        exit 1
        ;;
esac
EOF
    
    chmod +x /mnt/root/opt/kiosk-logs.sh
    
    # Add logging to crontab
    echo "0 2 * * * /opt/log-aggregator.sh" | chroot /mnt/root crontab -
    
    # Update kiosk CLI to include logging commands
    cat >> /mnt/root/usr/local/bin/kiosk << 'EOF'

# Add logging commands to kiosk CLI
    "logs")
        case "$2" in
            "component")
                /opt/kiosk-logs.sh component "$3"
                ;;
            "all")
                /opt/kiosk-logs.sh all
                ;;
            "errors")
                /opt/kiosk-logs.sh errors
                ;;
            "level")
                /opt/kiosk-logs.sh level "$3"
                ;;
            "follow")
                /opt/kiosk-logs.sh follow "$3"
                ;;
            "search")
                /opt/kiosk-logs.sh search "$3"
                ;;
            *)
                echo "Usage: kiosk logs {component|all|errors|level|follow|search}"
                echo
                echo "Commands:"
                echo "  component <name>  View specific component log"
                echo "  all              View all logs"
                echo "  errors           View recent errors"
                echo "  level <level>    View messages by level"
                echo "  follow [name]   Follow logs in real-time"
                echo "  search <pattern> Search logs for pattern"
                ;;
        esac
        ;;
    "debug")
        case "$2" in
            "system")
                /opt/kiosk-debug.sh system
                ;;
            "network")
                /opt/kiosk-debug.sh network
                ;;
            "app")
                /opt/kiosk-debug.sh app
                ;;
            "performance")
                /opt/kiosk-debug.sh performance
                ;;
            "all")
                /opt/kiosk-debug.sh all
                ;;
            *)
                echo "Usage: kiosk debug {system|network|app|performance|all}"
                ;;
        esac
        ;;
    "log-level")
        case "$2" in
            "debug"|"info"|"warn"|"error"|"critical")
                source /opt/kiosk-logger.sh
                set_log_level "$2"
                echo "Log level set to $2"
                ;;
            *)
                echo "Usage: kiosk log-level {debug|info|warn|error|critical}"
                ;;
        esac
        ;;
EOF
    
    # Update kiosk CLI help
    sed -i '/Commands:/a\
    logs         Log viewing and analysis\
    debug        System diagnostics and debugging\
    log-level    Set logging level' /mnt/root/usr/local/bin/kiosk
    
    log_info "Logging and debugging system installed"
}
