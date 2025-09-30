#!/bin/bash
#
# KioskBook Module: Boot Optimization
#
# Optimizes system boot time and disables unnecessary services.
# This module is idempotent - safe to re-run.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[BOOT]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[BOOT]${NC} $1"
}

log_error() {
    echo -e "${RED}[BOOT]${NC} $1"
    exit 1
}

# Configure GRUB for fast boot
configure_grub() {
    log_info "Configuring GRUB for fast boot..."
    
    # Backup original GRUB config
    if [ ! -f /etc/default/grub.backup ]; then
        cp /etc/default/grub /etc/default/grub.backup
    fi
    
    # Set GRUB timeout to 0
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    
    # Optimize kernel parameters for completely silent boot
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 rd.systemd.show_status=false rd.udev.log_priority=0 vga=current"/' /etc/default/grub
    
    # Hide GRUB menu completely
    sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="quiet splash loglevel=0"/' /etc/default/grub
    
    # Hide GRUB menu
    sed -i 's/^#GRUB_HIDDEN_TIMEOUT=.*/GRUB_HIDDEN_TIMEOUT=0/' /etc/default/grub
    sed -i 's/^#GRUB_HIDDEN_TIMEOUT_QUIET=.*/GRUB_HIDDEN_TIMEOUT_QUIET=true/' /etc/default/grub
    
    # Update GRUB
    update-grub
    
    log_info "GRUB configured for fast boot"
}

# Disable unnecessary services
disable_services() {
    log_info "Disabling unnecessary services..."
    
    # Services to disable
    SERVICES_TO_DISABLE=(
        "bluetooth.service"
        "cups.service"
        "ModemManager.service"
        "plymouth-quit-wait.service"
        "snapd.service"
        "snapd.socket"
        "snapd.seeded.service"
        "packagekit.service"
        "apt-daily.service"
        "apt-daily.timer"
        "apt-daily-upgrade.service"
        "apt-daily-upgrade.timer"
    )
    
    for service in "${SERVICES_TO_DISABLE[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            systemctl disable "$service" 2>/dev/null || true
            systemctl mask "$service" 2>/dev/null || true
            log_info "Disabled: $service"
        fi
    done
    
    log_info "Unnecessary services disabled"
}

# Optimize systemd
optimize_systemd() {
    log_info "Optimizing systemd configuration..."
    
    # Create systemd optimization override
    mkdir -p /etc/systemd/system.conf.d/
    cat > /etc/systemd/system.conf.d/kiosk-optimization.conf << 'EOF'
[Manager]
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=5s
DefaultRestartSec=100ms
ShowStatus=no
EOF
    
    # Optimize journald
    mkdir -p /etc/systemd/journald.conf.d/
    cat > /etc/systemd/journald.conf.d/kiosk-optimization.conf << 'EOF'
[Journal]
Storage=volatile
SystemMaxUse=50M
RuntimeMaxUse=50M
EOF
    
    # Hide systemd boot messages
    mkdir -p /etc/systemd/system/console-getty.service.d/
    cat > /etc/systemd/system/console-getty.service.d/override.conf << 'EOF'
[Service]
StandardOutput=null
StandardError=null
EOF
    
    log_info "Systemd optimization configured"
}

# Set timezone
set_timezone() {
    local timezone="${1:-America/Halifax}"
    
    log_info "Setting timezone to $timezone..."
    timedatectl set-timezone "$timezone"
    log_info "Timezone set to $timezone"
}

# Main function
main() {
    echo -e "${CYAN}=== Boot Optimization Module ===${NC}"
    
    configure_grub
    disable_services
    optimize_systemd
    set_timezone "${1:-America/Halifax}"
    
    log_info "Boot optimization complete"
    log_info "Current boot time: $(systemd-analyze time 2>/dev/null | grep "Startup finished in" | awk '{print $(NF-1), $NF}' || echo "unknown")"
}

main "$@"
