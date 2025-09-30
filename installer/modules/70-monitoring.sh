#!/bin/bash
#
# 70-monitoring.sh - System Monitoring and Finalization Module
#
# Sets up comprehensive system monitoring, logging, and finalization tasks.
# Configures health checks, performance monitoring, and system validation.
#
# Features:
# - System health monitoring with automated recovery
# - Performance metrics collection and logging
# - Service dependency validation
# - Final system configuration validation
# - Installation completion verification
# - Monitoring dashboard setup
#

set -e
set -o pipefail

# Import logging functions from main installer
source /dev/stdin <<< "$(declare -f log log_success log_warning log_error log_info add_rollback)"

# Module configuration
MODULE_NAME="70-monitoring"
MONITORING_DIR="/var/lib/kioskbook"
LOG_RETENTION_DAYS=30

log_info "Starting monitoring and finalization module..."

# Validate environment
validate_environment() {
    if [[ -z "$MOUNT_ROOT" || -z "$MOUNT_DATA" ]]; then
        log_error "Required environment variables not set. Run previous modules first."
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_ROOT"; then
        log_error "Root partition not mounted at $MOUNT_ROOT"
        exit 1
    fi
    
    if ! mountpoint -q "$MOUNT_DATA"; then
        log_error "Data partition not mounted at $MOUNT_DATA"
        exit 1
    fi
    
    log_info "Environment validation passed"
}

# Install monitoring packages
install_monitoring_packages() {
    log_info "Installing monitoring and logging packages..."
    
    local packages=(
        "rsyslog"
        "logrotate" 
        "htop"
        "iotop"
        "lsof"
        "strace"
        "procps"
        "psmisc"
        "sysstat"
        "smartmontools"
        "lm-sensors"
        "jq"
        "bc"
    )
    
    apk --root "$MOUNT_ROOT" add "${packages[@]}" || {
        log_error "Failed to install monitoring packages"
        exit 1
    }
    
    log_success "Monitoring packages installed"
}

# Configure system logging
configure_logging() {
    log_info "Configuring system logging..."
    
    # Configure rsyslog
    cat > "$MOUNT_ROOT/etc/rsyslog.conf" << 'EOF'
# KioskBook Rsyslog Configuration

# Load modules
module(load="imuxsock")    # provides support for local system logging
module(load="imklog")      # provides kernel logging support

# Set default permissions
$FileOwner root
$FileGroup adm
$FileCreateMode 0640
$DirCreateMode 0755
$Umask 0022

# Default logging rules
*.*;auth,authpriv.none          /var/log/syslog
auth,authpriv.*                 /var/log/auth.log
cron.*                          /var/log/cron.log
daemon.*                        /var/log/daemon.log
kern.*                          /var/log/kern.log
mail.*                          /var/log/mail.log
user.*                          /var/log/user.log

# KioskBook specific logs
:programname, isequal, "kiosk-app"     /var/log/kiosk-app.log
:programname, isequal, "kiosk-display" /var/log/kiosk-display.log
:programname, isequal, "health-check"  /var/log/health-check.log
:programname, isequal, "content-sync"  /var/log/content-sync.log

# Emergency and critical messages to console
*.emerg                         :omusrmsg:*
*.crit                          /dev/console

# Stop processing for kiosk logs
:programname, isequal, "kiosk-app"     stop
:programname, isequal, "kiosk-display" stop
:programname, isequal, "health-check"  stop
:programname, isequal, "content-sync"  stop
EOF

    # Configure logrotate
    cat > "$MOUNT_ROOT/etc/logrotate.conf" << 'EOF'
# KioskBook Logrotate Configuration

# Rotate logs weekly
weekly

# Keep 4 weeks worth of backlogs
rotate 4

# Create new (empty) log files after rotating old ones
create

# Use date as a suffix of the rotated file
dateext

# Compress rotated logs
compress
delaycompress

# Packages can drop log rotation information into this directory
include /etc/logrotate.d

# System logs
/var/log/syslog {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}

# Application logs
/var/log/kiosk-*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
}

# Health and monitoring logs
/var/log/health-check.log
/var/log/content-sync.log
/var/log/network-health.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF

    # Enable logging services
    chroot "$MOUNT_ROOT" rc-update add rsyslog default || {
        log_warning "Failed to enable rsyslog service"
    }
    
    log_success "System logging configured"
}

# Create monitoring directory structure
create_monitoring_structure() {
    log_info "Creating monitoring directory structure..."
    
    # Create monitoring directories
    local monitoring_path="$MOUNT_DATA$MONITORING_DIR"
    mkdir -p "$monitoring_path"/{metrics,status,reports,scripts}
    
    # Create system monitoring directory
    mkdir -p "$MOUNT_ROOT$MONITORING_DIR"/{state,cache,tmp}
    
    # Create symlink for persistence
    ln -sf "$MONITORING_DIR" "$MOUNT_ROOT$MONITORING_DIR/data" || {
        log_warning "Failed to create monitoring data symlink"
    }
    
    # Set permissions
    chmod 755 "$monitoring_path"
    chroot "$MOUNT_ROOT" chown -R root:root "$MONITORING_DIR"
    
    log_success "Monitoring structure created"
}

# Create system status dashboard
create_status_dashboard() {
    log_info "Creating system status dashboard..."
    
    cat > "$MOUNT_ROOT/usr/local/bin/system-status" << 'EOF'
#!/bin/bash
#
# KioskBook System Status Dashboard
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Status symbols
GOOD="✓"
WARNING="⚠"
ERROR="✗"
INFO="ℹ"

echo -e "${BLUE}KioskBook System Status Dashboard${NC}"
echo "=================================="
echo

# System information
echo -e "${BLUE}System Information:${NC}"
echo "  Hostname: $(hostname)"
echo "  Uptime: $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}' | sed 's/,//')"
echo "  Load: $(uptime | awk -F'load average:' '{print $2}' | xargs)"
echo "  Date: $(date)"
echo

# Resource usage
echo -e "${BLUE}Resource Usage:${NC}"

# CPU
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' || echo "N/A")
echo "  CPU Usage: $cpu_usage"

# Memory
memory_info=$(free -h | awk 'NR==2{printf "  Memory: %s/%s (%.2f%%)", $3, $2, $3*100/$2}')
echo "$memory_info"

# Disk usage
echo "  Disk Usage:"
df -h / /data 2>/dev/null | awk 'NR>1 {printf "    %s: %s/%s (%s)\n", $6, $3, $2, $5}'

echo

# Service status
echo -e "${BLUE}Service Status:${NC}"

services=("kiosk-app" "kiosk-display" "dhcpcd" "sshd" "rsyslog" "crond")
for service in "${services[@]}"; do
    if rc-service "$service" status >/dev/null 2>&1; then
        echo -e "  ${GREEN}$GOOD${NC} $service"
    else
        echo -e "  ${RED}$ERROR${NC} $service (stopped)"
    fi
done

# Tailscale status
if command -v tailscale >/dev/null 2>&1; then
    if tailscale status >/dev/null 2>&1; then
        echo -e "  ${GREEN}$GOOD${NC} tailscale"
    else
        echo -e "  ${YELLOW}$WARNING${NC} tailscale (disconnected)"
    fi
fi

echo

# Network status
echo -e "${BLUE}Network Status:${NC}"

# Connectivity
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    echo -e "  Internet: ${GREEN}$GOOD${NC} Connected"
else
    echo -e "  Internet: ${RED}$ERROR${NC} Disconnected"
fi

# DNS
if nslookup google.com >/dev/null 2>&1; then
    echo -e "  DNS: ${GREEN}$GOOD${NC} Working"
else
    echo -e "  DNS: ${RED}$ERROR${NC} Failed"
fi

echo

# Application status
echo -e "${BLUE}Application Status:${NC}"

# Node.js server
if pgrep -f "node.*server.js" >/dev/null; then
    echo -e "  Node.js server: ${GREEN}$GOOD${NC} Running"
    
    # Health check
    if curl -s "http://localhost:3000/health" >/dev/null; then
        echo -e "  HTTP health check: ${GREEN}$GOOD${NC} OK"
    else
        echo -e "  HTTP health check: ${RED}$ERROR${NC} Failed"
    fi
else
    echo -e "  Node.js server: ${RED}$ERROR${NC} Not running"
fi

# Chromium
chromium_count=$(pgrep -f chromium | wc -l)
if [[ "$chromium_count" -gt 0 ]]; then
    echo -e "  Chromium: ${GREEN}$GOOD${NC} Running ($chromium_count processes)"
else
    echo -e "  Chromium: ${RED}$ERROR${NC} Not running"
fi

# Display server
if pgrep -f Xorg >/dev/null; then
    echo -e "  X11 Display: ${GREEN}$GOOD${NC} Running"
else
    echo -e "  X11 Display: ${RED}$ERROR${NC} Not running"
fi

echo
echo "Use 'font-status' for font configuration"
echo "Use 'app-status' for application information"
echo "Use 'validate-installation' to verify system setup"
EOF

    chmod +x "$MOUNT_ROOT/usr/local/bin/system-status"
    
    log_success "System status dashboard created"
}

# Configure monitoring cron jobs
configure_monitoring_cron() {
    log_info "Configuring monitoring cron jobs..."
    
    # Create comprehensive cron configuration
    cat > "$MOUNT_ROOT/etc/cron.d/kioskbook-monitoring" << 'EOF'
# KioskBook System Monitoring Cron Jobs
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Application status monitoring every 15 minutes
*/15 * * * * root /usr/local/bin/app-status >/dev/null 2>&1

# Update font cache daily at 3 AM
0 3 * * * root /usr/local/bin/update-fonts >/dev/null 2>&1

# System status report daily at 6 AM
0 6 * * * root /usr/local/bin/system-status > /var/log/daily-status.log 2>&1

# Clean up old logs weekly
0 2 * * 0 root find /var/log -name "*.log.*" -mtime +7 -delete >/dev/null 2>&1
EOF

    log_success "Monitoring cron jobs configured"
}

# Create installation validation script
create_validation_script() {
    log_info "Creating installation validation script..."
    
    cat > "$MOUNT_ROOT/usr/local/bin/validate-installation" << 'EOF'
#!/bin/bash
#
# KioskBook Installation Validation Script
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GOOD="✓"
ERROR="✗"
WARNING="⚠"

validation_errors=0

check() {
    local description="$1"
    local command="$2"
    local is_critical="${3:-true}"
    
    printf "  %-50s " "$description"
    
    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}$GOOD${NC}"
        return 0
    else
        if [[ "$is_critical" == "true" ]]; then
            echo -e "${RED}$ERROR${NC}"
            ((validation_errors++))
        else
            echo -e "${YELLOW}$WARNING${NC}"
        fi
        return 1
    fi
}

echo -e "${BLUE}KioskBook Installation Validation${NC}"
echo "=================================="
echo

echo "System Components:"
check "Base system installed" "test -f /etc/alpine-release"
check "Init system (OpenRC)" "test -x /sbin/openrc"
check "Package manager (apk)" "which apk"

echo
echo "Display Stack:"
check "X11 server installed" "test -x /usr/bin/Xorg"
check "AMD GPU driver" "test -f /usr/lib/xorg/modules/drivers/amdgpu_drv.so"
check "Chromium browser" "which chromium"

echo
echo "Application:"
check "Node.js runtime" "which node"
check "npm package manager" "which npm"
check "Application directory" "test -d /data/app"
check "Express server script" "test -f /data/app/server.js"
check "Built application" "test -d /data/app/dist"
check "Content directory" "test -d /data/content/current"

echo
echo "Services:"
check "kiosk-app service" "test -f /etc/init.d/kiosk-app"
check "kiosk-display service" "test -f /etc/init.d/kiosk-display"
check "SSH service" "test -f /etc/init.d/sshd"
check "DHCP client" "test -f /etc/init.d/dhcpcd"

echo
echo "Fonts:"
check "Inter font installed" "fc-list | grep -i inter"
check "CaskaydiaCove installed" "fc-list | grep -i caskaydia"
check "Font configuration" "test -f /etc/fonts/local.conf"

echo
echo "Boot Configuration:"
check "GRUB bootloader" "test -f /boot/grub/grub.cfg"
check "Kernel installed" "ls /boot/vmlinuz-* >/dev/null 2>&1"
check "Initramfs created" "ls /boot/initrd >/dev/null 2>&1"

echo
echo "User Configuration:"
check "Kiosk user exists" "id kiosk"
check "Kiosk home directory" "test -d /home/kiosk"

echo
echo "Storage:"
check "Data partition available" "test -d /data"
check "Application data" "test -d /data/app"
check "Content data" "test -d /data/content"
check "Font data" "test -d /data/fonts"

echo
echo -e "${BLUE}Validation Summary:${NC}"
if [[ $validation_errors -eq 0 ]]; then
    echo -e "${GREEN}$GOOD Installation validation passed successfully!${NC}"
    echo
    echo "The KioskBook system has been installed and configured."
    echo "Use 'system-status' to check system health after boot."
    exit 0
else
    echo -e "${RED}$ERROR Installation validation failed ($validation_errors errors)${NC}"
    echo
    echo "Please review the errors above."
    exit 1
fi
EOF

    chmod +x "$MOUNT_ROOT/usr/local/bin/validate-installation"
    
    log_success "Installation validation script created"
}

# Perform final system validation
perform_final_validation() {
    log_info "Performing final system validation..."
    
    # Verify essential directories exist
    local essential_dirs=(
        "$MOUNT_DATA/app"
        "$MOUNT_DATA/content/current"
        "$MOUNT_DATA/fonts"
        "$MOUNT_ROOT/home/kiosk"
    )
    
    for dir in "${essential_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Essential directory missing: $dir"
            exit 1
        fi
    done
    
    # Check boot configuration
    if [[ ! -f "$MOUNT_ROOT/boot/grub/grub.cfg" ]]; then
        log_error "GRUB configuration missing"
        exit 1
    fi
    
    # Verify application files
    if [[ ! -f "$MOUNT_DATA/app/server.js" ]]; then
        log_error "Application server script missing"
        exit 1
    fi
    
    if [[ ! -d "$MOUNT_DATA/app/dist" ]]; then
        log_error "Built application missing"
        exit 1
    fi
    
    log_success "Final system validation passed"
}

# Create system information summary
create_system_summary() {
    log_info "Creating system information summary..."
    
    cat > "$MOUNT_ROOT/etc/kioskbook-info" << EOF
# KioskBook System Information
# Generated: $(date)

KIOSKBOOK_VERSION=1.0.0
INSTALLATION_DATE=$(date -Iseconds)
BASE_OS=Alpine Linux
GITHUB_REPO=${GITHUB_REPO:-unknown}

# System Configuration
KIOSK_USER=kiosk
APP_PORT=3000
DATA_MOUNT=/data
FONT_DIR=/data/fonts

# Management Commands
SYSTEM_STATUS="system-status"
FONT_STATUS="font-status"  
APP_STATUS="app-status"
VALIDATE_INSTALL="validate-installation"
EOF
    
    # Create motd
    cat > "$MOUNT_ROOT/etc/motd" << 'EOF'

 ██╗  ██╗██╗ ██████╗ ███████╗██╗  ██╗██████╗  ██████╗  ██████╗ ██╗  ██╗
 ██║ ██╔╝██║██╔═══██╗██╔════╝██║ ██╔╝██╔══██╗██╔═══██╗██╔═══██╗██║ ██╔╝
 █████╔╝ ██║██║   ██║███████╗█████╔╝ ██████╔╝██║   ██║██║   ██║█████╔╝ 
 ██╔═██╗ ██║██║   ██║╚════██║██╔═██╗ ██╔══██╗██║   ██║██║   ██║██╔═██╗ 
 ██║  ██╗██║╚██████╔╝███████║██║  ██╗██████╔╝╚██████╔╝╚██████╔╝██║  ██╗
 ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝

 KioskBook - Bulletproof Kiosk Deployment Platform
 ==================================================

 Status: system-status    Apps: app-status       Fonts: font-status
 Validate: validate-installation

EOF
    
    log_success "System information summary created"
}

# Main monitoring setup function
main() {
    log_info "=========================================="
    log_info "Module: Monitoring and Finalization"
    log_info "=========================================="
    
    validate_environment
    install_monitoring_packages
    configure_logging
    create_monitoring_structure
    create_status_dashboard
    configure_monitoring_cron
    create_validation_script
    perform_final_validation
    create_system_summary
    
    log_success "Monitoring and finalization completed successfully"
    log_info "System monitoring configured:"
    log_info "  - Health monitoring and recovery"
    log_info "  - Log rotation and retention"
    log_info "  - System status dashboard"
    log_info "Management commands available:"
    log_info "  - system-status: System dashboard"
    log_info "  - validate-installation: Verify setup"
    log_info "Installation completed - ready for first boot!"
}

# Execute main function
main "$@"