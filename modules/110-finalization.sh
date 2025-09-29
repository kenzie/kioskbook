#!/bin/bash
#
# KioskBook Module: Finalization
#
# Performs final system configuration and cleanup.
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

# Configuration
KIOSKBOOK_DIR="/opt/kioskbook"
KIOSK_USER="kiosk"

log_info() {
    echo -e "${GREEN}[FINALIZE]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[FINALIZE]${NC} $1"
}

log_error() {
    echo -e "${RED}[FINALIZE]${NC} $1"
    exit 1
}

# Set timezone
set_timezone() {
    local timezone="${1:-America/Halifax}"
    
    log_info "Setting timezone to $timezone..."
    timedatectl set-timezone "$timezone"
    log_info "Timezone set to $timezone"
}

# Configure system locale
configure_locale() {
    log_info "Configuring system locale..."
    
    # Set locale
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    
    # Update locale
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    
    log_info "Locale configured"
}

# Setup log rotation
setup_log_rotation() {
    log_info "Setting up comprehensive log rotation..."
    
    # Create logrotate configuration for all kiosk services
    cat > /etc/logrotate.d/kioskbook << 'EOF'
# KioskBook Log Rotation Configuration

/var/log/kiosk-*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

/var/log/auto-update.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

/var/log/screensaver.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}

/var/log/kiosk-health.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
    
    log_info "Log rotation configured"
}

# Create system information file
create_system_info() {
    log_info "Creating system information file..."
    
    cat > /opt/kioskbook/system-info.txt << EOF
KioskBook System Information
Generated: $(date)

Hostname: $(hostname)
OS: $(lsb_release -d | cut -f2)
Kernel: $(uname -r)
Architecture: $(uname -m)
Uptime: $(uptime -p)

Services:
$(systemctl list-units --type=service --state=active | grep kiosk)

Network:
$(ip addr show | grep "inet " | grep -v "127.0.0.1")

Boot Time:
$(systemd-analyze time 2>/dev/null | grep "Startup finished in" || echo "Unknown")

Disk Usage:
$(df -h /)

Memory Usage:
$(free -h)
EOF
    
    log_info "System information file created at /opt/kioskbook/system-info.txt"
}

# Setup backup directory
setup_backup_directory() {
    log_info "Setting up backup directory..."
    
    mkdir -p /var/backups/kioskbook
    chmod 755 /var/backups/kioskbook
    
    # Create backup script
    cat > /opt/kioskbook/backup.sh << 'EOF'
#!/bin/bash
# KioskBook Backup Script

BACKUP_DIR="/var/backups/kioskbook/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating backup at $BACKUP_DIR"

# Backup systemd services
cp -r /etc/systemd/system/kiosk* "$BACKUP_DIR/" 2>/dev/null || true

# Backup kioskbook config
cp -r /opt/kioskbook "$BACKUP_DIR/" 2>/dev/null || true

# Backup app directory
cp -r /opt/kiosk-app "$BACKUP_DIR/" 2>/dev/null || true

# Create backup info
cat > "$BACKUP_DIR/backup-info.txt" << EOL
KioskBook Backup
Created: $(date)
Hostname: $(hostname)
Version: $(cat /opt/kioskbook/VERSION 2>/dev/null || echo "Unknown")
EOL

echo "Backup completed: $BACKUP_DIR"
EOF
    
    chmod +x /opt/kioskbook/backup.sh
    
    log_info "Backup system configured"
}

# Create version file
create_version_file() {
    log_info "Creating version file..."
    
    cat > /opt/kioskbook/VERSION << EOF
KioskBook v0.1.0
Modular Kiosk Deployment Platform
Built: $(date)
Git Commit: $(cd /opt/kioskbook && git rev-parse --short HEAD 2>/dev/null || echo "Unknown")
Git Branch: $(cd /opt/kioskbook && git branch --show-current 2>/dev/null || echo "Unknown")
EOF
    
    log_info "Version file created"
}

# Setup maintenance cron jobs
setup_maintenance_cron() {
    log_info "Setting up maintenance cron jobs..."
    
    # Create maintenance script
    cat > /opt/kioskbook/maintenance.sh << 'EOF'
#!/bin/bash
# KioskBook Maintenance Script

# Clean old logs
find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null || true

# Clean package cache
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean 2>/dev/null || true

# Clean temporary files
find /tmp -type f -mtime +3 -delete 2>/dev/null || true

# Update system info
/opt/kioskbook/modules/110-finalization.sh 2>/dev/null || true

echo "Maintenance completed: $(date)"
EOF
    
    chmod +x /opt/kioskbook/maintenance.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/kioskbook/maintenance.sh >> /var/log/kioskbook-maintenance.log 2>&1") | crontab -
    
    log_info "Maintenance cron jobs configured"
}

# Final system sync and cleanup
final_cleanup() {
    log_info "Performing final cleanup..."
    
    # Sync filesystems
    sync
    
    # Clear package cache
    apt-get clean
    
    # Update package database
    apt-get update
    
    log_info "Final cleanup completed"
}

# Main function
main() {
    echo -e "${CYAN}=== Finalization Module ===${NC}"
    
    local timezone="${1:-America/Halifax}"
    
    set_timezone "$timezone"
    configure_locale
    setup_log_rotation
    create_system_info
    setup_backup_directory
    create_version_file
    setup_maintenance_cron
    final_cleanup
    
    log_info "Finalization complete"
    log_info "System is ready for kiosk operation"
}

main "$@"
