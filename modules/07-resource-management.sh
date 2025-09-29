#!/bin/bash
# KioskBook Resource Management Module

# Setup resource management and cleanup
setup_resource_management() {
    log_step "Setting Up Resource Management & Cleanup"
    
    # Create resource monitoring service
    cat > /mnt/root/etc/init.d/resource-monitor << 'EOF'
#!/sbin/openrc-run

name="Resource Monitor"
description="System resource monitoring and cleanup"

depend() {
    need net
    after net
}

start() {
    ebegin "Starting resource monitor"
    # Service runs via cron, no persistent daemon needed
    eend 0
}

stop() {
    ebegin "Stopping resource monitor"
    eend 0
}
EOF
    
    chmod +x /mnt/root/etc/init.d/resource-monitor
    chroot /mnt/root rc-update add resource-monitor default
    
    # Create comprehensive resource management script
    cat > /mnt/root/opt/resource-manager.sh << 'EOF'
#!/bin/bash
# KioskBook Resource Management & Cleanup

LOG_FILE="/var/log/resource-manager.log"
LOCK_FILE="/tmp/resource-manager.lock"

# Prevent concurrent runs
if [ -f "$LOCK_FILE" ]; then
    echo "$(date): Resource manager already running, skipping" >> "$LOG_FILE"
    exit 0
fi

touch "$LOCK_FILE"

# Logging function
log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
}

# Set trap for cleanup
trap cleanup EXIT

log "Starting resource management cycle"

# Memory management
check_memory() {
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    MEMORY_USAGE_INT=$(echo "$MEMORY_USAGE" | cut -d. -f1)
    
    log "Memory usage: ${MEMORY_USAGE}%"
    
    if [ "$MEMORY_USAGE_INT" -gt 85 ]; then
        log "WARNING: High memory usage (${MEMORY_USAGE}%), cleaning up..."
        
        # Clear page cache
        sync
        echo 3 > /proc/sys/vm/drop_caches
        
        # Kill any zombie processes
        ps aux | awk '$8 ~ /^Z/ { print $2 }' | xargs -r kill -9
        
        # Restart services if memory still high
        NEW_MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
        NEW_MEMORY_USAGE_INT=$(echo "$NEW_MEMORY_USAGE" | cut -d. -f1)
        
        if [ "$NEW_MEMORY_USAGE_INT" -gt 90 ]; then
            log "CRITICAL: Memory usage still high (${NEW_MEMORY_USAGE}%), restarting services"
            rc-service kiosk-browser restart
            sleep 5
            rc-service kiosk-app restart
        fi
    fi
}

# Disk space management
check_disk_space() {
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    log "Disk usage: ${DISK_USAGE}%"
    
    if [ "$DISK_USAGE" -gt 80 ]; then
        log "WARNING: High disk usage (${DISK_USAGE}%), cleaning up..."
        
        # Clean package cache
        apk cache clean
        
        # Clean temporary files
        find /tmp -type f -atime +7 -delete 2>/dev/null
        find /var/tmp -type f -atime +7 -delete 2>/dev/null
        
        # Clean browser cache
        rm -rf /tmp/chrome-kiosk/Cache/* 2>/dev/null
        rm -rf /tmp/chrome-kiosk/Code\ Cache/* 2>/dev/null
        
        # Clean old logs (keep last 1000 lines)
        if [ -f /var/log/auto-update.log ]; then
            tail -1000 /var/log/auto-update.log > /tmp/auto-update.log.tmp
            mv /tmp/auto-update.log.tmp /var/log/auto-update.log
        fi
        
        if [ -f /var/log/resource-manager.log ]; then
            tail -1000 /var/log/resource-manager.log > /tmp/resource-manager.log.tmp
            mv /tmp/resource-manager.log.tmp /var/log/resource-manager.log
        fi
        
        # Clean old git objects if app repo exists
        if [ -d /opt/kiosk-app/.git ]; then
            cd /opt/kiosk-app
            git gc --prune=now 2>/dev/null
        fi
        
        NEW_DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
        log "Disk usage after cleanup: ${NEW_DISK_USAGE}%"
        
        if [ "$NEW_DISK_USAGE" -gt 95 ]; then
            log "CRITICAL: Disk usage still critical (${NEW_DISK_USAGE}%), emergency cleanup"
            
            # Remove old kernel images
            apk del $(apk info | grep linux- | grep -v $(uname -r)) 2>/dev/null
            
            # Clean all logs older than 3 days
            find /var/log -name "*.log" -mtime +3 -delete 2>/dev/null
            
            # Clean browser data completely
            rm -rf /tmp/chrome-kiosk/* 2>/dev/null
        fi
    fi
}

# Process management
check_processes() {
    # Check for runaway processes
    HIGH_CPU_PROCESSES=$(ps aux --sort=-%cpu | head -10 | awk '$3 > 50.0 {print $2, $3, $11}' | grep -v "PID")
    
    if [ -n "$HIGH_CPU_PROCESSES" ]; then
        log "WARNING: High CPU processes detected:"
        echo "$HIGH_CPU_PROCESSES" | while read pid cpu cmd; do
            log "  PID $pid: ${cpu}% CPU - $cmd"
            
            # Kill processes using >90% CPU for more than 5 minutes
            if (( $(echo "$cpu > 90" | bc -l) )); then
                PROCESS_AGE=$(ps -o etime= -p "$pid" 2>/dev/null | awk -F: '{print $1*60+$2}')
                if [ "$PROCESS_AGE" -gt 300 ]; then
                    log "Killing runaway process PID $pid (${cpu}% CPU for >5min)"
                    kill -9 "$pid" 2>/dev/null
                fi
            fi
        done
    fi
    
    # Check for zombie processes
    ZOMBIE_COUNT=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    if [ "$ZOMBIE_COUNT" -gt 5 ]; then
        log "WARNING: $ZOMBIE_COUNT zombie processes detected, cleaning up"
        ps aux | awk '$8 ~ /^Z/ { print $2 }' | xargs -r kill -9
    fi
}

# Network resource management
check_network_resources() {
    # Check for too many network connections
    CONNECTION_COUNT=$(ss -tuln | wc -l)
    if [ "$CONNECTION_COUNT" -gt 1000 ]; then
        log "WARNING: High number of network connections ($CONNECTION_COUNT)"
        
        # Close idle connections
        ss -K -tuln | grep -E "(ESTAB|TIME-WAIT)" | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -5 | while read count ip; do
            if [ "$count" -gt 100 ]; then
                log "Closing $count connections from $ip"
                ss -K dst "$ip" 2>/dev/null
            fi
        done
    fi
}

# Log rotation
rotate_logs() {
    # Rotate large log files
    find /var/log -name "*.log" -size +10M -exec sh -c '
        for logfile; do
            mv "$logfile" "${logfile}.old"
            touch "$logfile"
            chmod 644 "$logfile"
            echo "$(date): Rotated $logfile" >> /var/log/resource-manager.log
        done
    ' _ {} +
}

# System optimization
optimize_system() {
    # Sync filesystem
    sync
    
    # Optimize memory
    if [ -f /proc/sys/vm/drop_caches ]; then
        echo 1 > /proc/sys/vm/drop_caches
    fi
    
    # Clean up temporary files
    find /tmp -type f -name "*.tmp" -mtime +1 -delete 2>/dev/null
    find /var/tmp -type f -name "*.tmp" -mtime +1 -delete 2>/dev/null
}

# Main execution
main() {
    log "Resource management cycle started"
    
    check_memory
    check_disk_space
    check_processes
    check_network_resources
    rotate_logs
    optimize_system
    
    log "Resource management cycle completed"
}

# Run main function
main
EOF
    
    chmod +x /mnt/root/opt/resource-manager.sh
    
    # Install bc for floating point calculations
    chroot /mnt/root apk add bc
    
    # Add resource management to crontab (every 15 minutes)
    echo "*/15 * * * * /opt/resource-manager.sh" | chroot /mnt/root crontab -
    
    # Create emergency cleanup script
    cat > /mnt/root/opt/emergency-cleanup.sh << 'EOF'
#!/bin/bash
# Emergency cleanup script for critical resource situations

echo "=== EMERGENCY CLEANUP ==="
echo "This will perform aggressive cleanup to free resources"
echo "Press Ctrl+C to cancel, or Enter to continue"
read

echo "Starting emergency cleanup..."

# Stop non-essential services
rc-service screensaver stop 2>/dev/null
rc-service auto-update stop 2>/dev/null

# Clear all caches
sync
echo 3 > /proc/sys/vm/drop_caches

# Clean all temporary files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clean browser data
rm -rf /tmp/chrome-kiosk/*

# Clean package cache
apk cache clean

# Remove old kernels
apk del $(apk info | grep linux- | grep -v $(uname -r)) 2>/dev/null

# Clean all logs
find /var/log -name "*.log" -delete 2>/dev/null
find /var/log -name "*.old" -delete 2>/dev/null

# Clean git objects
if [ -d /opt/kiosk-app/.git ]; then
    cd /opt/kiosk-app
    git gc --aggressive --prune=now 2>/dev/null
fi

# Restart essential services
rc-service kiosk-app restart
rc-service kiosk-browser restart

echo "Emergency cleanup completed"
echo "Current disk usage: $(df / | tail -1 | awk '{print $5}')"
echo "Current memory usage: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
EOF
    
    chmod +x /mnt/root/opt/emergency-cleanup.sh
    
    # Create resource status script
    cat > /mnt/root/opt/resource-status.sh << 'EOF'
#!/bin/bash
# Resource status overview

echo "=== KioskBook Resource Status ==="
echo

# Memory status
echo "Memory Usage:"
free -h | grep -E "(Mem|Swap)" | sed 's/^/  /'
echo "Memory pressure: $(cat /proc/pressure/memory 2>/dev/null | head -1 || echo 'Not available')"
echo

# Disk status
echo "Disk Usage:"
df -h | grep -E "(Filesystem|/dev/)" | sed 's/^/  /'
echo

# Process status
echo "Top CPU Processes:"
ps aux --sort=-%cpu | head -6 | sed 's/^/  /'
echo

# Network connections
echo "Network Connections:"
ss -tuln | wc -l | sed 's/^/  Total: /'
ss -tuln | grep ESTAB | wc -l | sed 's/^/  Established: /'
echo

# Log sizes
echo "Log File Sizes:"
find /var/log -name "*.log" -exec ls -lh {} \; 2>/dev/null | awk '{print "  " $9 ": " $5}' | head -10
echo

# Recent resource manager activity
if [ -f /var/log/resource-manager.log ]; then
    echo "Recent Resource Manager Activity:"
    tail -5 /var/log/resource-manager.log | sed 's/^/  /'
fi
EOF
    
    chmod +x /mnt/root/opt/resource-status.sh
    
    log_info "Resource management system installed"
}
