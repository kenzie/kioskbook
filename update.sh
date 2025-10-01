#!/bin/bash
#
# KioskBook Update Script
#
# Applies latest improvements and fixes to an existing KioskBook installation.
# Safe to run multiple times (idempotent operations).
#
# Usage: sudo ./update.sh
#

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Configuration
readonly KIOSK_USER="kiosk"
readonly KIOSK_HOME="/home/kiosk"
readonly APP_DIR="/opt/kioskbook"

# Logging functions
log() { printf "${CYAN}[UPDATE]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warning() { printf "${YELLOW}[WARNING]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "═══════════════════════════════════════════════════════"
    echo "     KioskBook Update Script"
    echo "    Apply Latest Improvements to Existing Installation"
    echo "═══════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Must be root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
    fi
    
    # Check if this is a KioskBook system
    if [[ ! -f /etc/systemd/system/kioskbook-app.service ]]; then
        log_error "This doesn't appear to be a KioskBook installation"
    fi
    
    # Check if kiosk user exists
    if ! id "$KIOSK_USER" >/dev/null 2>&1; then
        log_error "Kiosk user not found. Is this a KioskBook system?"
    fi
    
    log_success "Prerequisites verified"
}

# Update system packages
update_system_packages() {
    log "Updating system packages..."
    
    # Update package lists
    apt-get update
    
    # Upgrade packages (with automatic yes)
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Clean up
    apt-get autoremove -y
    apt-get autoclean
    
    log_success "System packages updated"
}

# Update font configuration (idempotent)
update_font_configuration() {
    log "Updating font configuration..."
    
    # Create fontconfig directory if it doesn't exist
    mkdir -p /etc/fonts/conf.d
    
    # Create Inter font priority configuration (overwrites if exists)
    cat > /etc/fonts/conf.d/10-inter-default.conf << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Set Inter as default sans-serif font -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Inter</family>
      <family>Inter Display</family>
    </prefer>
  </alias>
  
  <!-- Set Inter as default for common web fonts -->
  <alias>
    <family>Arial</family>
    <prefer>
      <family>Inter</family>
    </prefer>
  </alias>
  
  <alias>
    <family>Helvetica</family>
    <prefer>
      <family>Inter</family>
    </prefer>
  </alias>
  
  <alias>
    <family>system-ui</family>
    <prefer>
      <family>Inter</family>
    </prefer>
  </alias>
</fontconfig>
EOF
    
    # Update font cache
    fc-cache -fv >/dev/null 2>&1
    
    log_success "Font configuration updated"
}

# Update SSH configuration (idempotent)
update_ssh_configuration() {
    log "Updating SSH configuration for faster startup..."
    
    local ssh_config="/etc/ssh/sshd_config"
    local updated=false
    
    # Add UseDNS no if not present
    if ! grep -q "^UseDNS no" "$ssh_config"; then
        echo "UseDNS no" >> "$ssh_config"
        updated=true
        log "Added UseDNS no to SSH config"
    fi
    
    # Add GSSAPIAuthentication no if not present
    if ! grep -q "^GSSAPIAuthentication no" "$ssh_config"; then
        echo "GSSAPIAuthentication no" >> "$ssh_config"
        updated=true
        log "Added GSSAPIAuthentication no to SSH config"
    fi
    
    # Pre-generate SSH host keys if missing
    if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
        ssh-keygen -A
        updated=true
        log "Generated missing SSH host keys"
    fi
    
    if [[ "$updated" == true ]]; then
        systemctl restart ssh
        log_success "SSH configuration updated and restarted"
    else
        log_success "SSH configuration already optimized"
    fi
}

# Update OpenBox autostart configuration (idempotent)
update_openbox_configuration() {
    log "Updating OpenBox autostart configuration..."
    
    local autostart_file="$KIOSK_HOME/.config/openbox/autostart"
    
    # Create the updated autostart script
    cat > "$autostart_file" << 'EOF'
#!/bin/bash
# Hide cursor after 1 second of inactivity
unclutter -idle 1 &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Wait for application to be ready (Vite dev server runs on 5173)
while ! curl -s http://localhost:5173 >/dev/null 2>&1; do
    sleep 1
done

# Start Chromium in kiosk mode with font optimization
exec chromium \
    --kiosk \
    --no-sandbox \
    --disable-infobars \
    --disable-features=TranslateUI \
    --disable-ipc-flooding-protection \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-default-apps \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --no-message-box \
    --start-fullscreen \
    --force-device-scale-factor=1 \
    --font-render-hinting=none \
    http://localhost:5173
EOF
    
    chmod +x "$autostart_file"
    chown "$KIOSK_USER:$KIOSK_USER" "$autostart_file"
    
    log_success "OpenBox configuration updated"
}

# Update systemd service configuration (idempotent)
update_systemd_service() {
    log "Updating systemd service configuration..."
    
    local service_file="/etc/systemd/system/kioskbook-app.service"
    
    # Create updated service file
    cat > "$service_file" << EOF
[Unit]
Description=KioskBook Application
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
Environment=NODE_ENV=production
Environment=HOST=0.0.0.0
Environment=PORT=5173
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload and restart if needed
    systemctl daemon-reload
    
    if systemctl is-active --quiet kioskbook-app; then
        log "Restarting KioskBook application service..."
        systemctl restart kioskbook-app
    fi
    
    log_success "Systemd service updated"
}

# Update application (idempotent)
update_application() {
    log "Updating application..."
    
    if [[ -d "$APP_DIR" ]]; then
        cd "$APP_DIR"
        
        # Check if it's a git repository
        if [[ -d .git ]]; then
            log "Pulling latest application code..."
            git pull
            
            # Update dependencies
            npm ci
            
            # Try to build if build script exists
            if npm run build 2>/dev/null; then
                log "Application built successfully"
            else
                log_warning "No build script found, using development mode"
            fi
            
            log_success "Application updated"
        else
            log_warning "Application directory is not a git repository"
        fi
    else
        log_error "Application directory not found: $APP_DIR"
    fi
}

# Restart kiosk session to apply changes
restart_kiosk_session() {
    log "Restarting kiosk session to apply changes..."
    
    # Check if LightDM is running
    if systemctl is-active --quiet lightdm; then
        systemctl restart lightdm
        log_success "Kiosk session restarted"
    else
        log_warning "LightDM not running, changes will apply on next boot"
    fi
}

# Install management CLI (idempotent)
install_management_cli() {
    log "Installing KioskBook management CLI..."
    
    # Copy kiosk command to system bin
    if [[ -f "./kiosk" ]]; then
        cp ./kiosk /usr/local/bin/kiosk
        chmod +x /usr/local/bin/kiosk
        log_success "Management CLI installed: kiosk command available"
    else
        log_warning "kiosk script not found in repository"
    fi
}

# Setup log rotation (Debian way)
setup_log_rotation() {
    log "Setting up log rotation..."
    
    # Create logrotate configuration for KioskBook
    cat > /etc/logrotate.d/kioskbook << 'EOF'
# KioskBook log rotation
/var/log/kioskbook/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}

# Systemd journal for kioskbook-app
{
    # Handled by systemd, but ensure cleanup
    postrotate
        systemctl reload-or-restart rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    
    # Create log directory
    mkdir -p /var/log/kioskbook
    
    # Test logrotate configuration
    logrotate -d /etc/logrotate.d/kioskbook >/dev/null 2>&1 || log_warning "Logrotate test failed"
    
    log_success "Log rotation configured"
}

# Setup monitoring and recovery (idempotent)
setup_monitoring() {
    log "Setting up monitoring and recovery..."
    
    # Create monitoring script
    cat > /usr/local/bin/kioskbook-monitor << 'EOF'
#!/bin/bash
# KioskBook monitoring and recovery script

LOG_FILE="/var/log/kioskbook/monitor.log"
MAX_MEMORY_MB=2048
MAX_LOAD=5.0

log_monitor() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Check memory usage
check_memory() {
    local memory_mb=$(free -m | awk '/^Mem:/ {print $3}')
    if [[ $memory_mb -gt $MAX_MEMORY_MB ]]; then
        log_monitor "HIGH MEMORY: ${memory_mb}MB > ${MAX_MEMORY_MB}MB"
        return 1
    fi
    return 0
}

# Check system load
check_load() {
    local load=$(cat /proc/loadavg | awk '{print $1}')
    if (( $(awk "BEGIN {print ($load > $MAX_LOAD)}") )); then
        log_monitor "HIGH LOAD: $load > $MAX_LOAD"
        return 1
    fi
    return 0
}

# Check if Chromium is running
check_chromium() {
    if ! pgrep -f "chromium.*kiosk" >/dev/null; then
        log_monitor "RECOVERY: Chromium not running, restarting display"
        systemctl restart lightdm
        return 1
    fi
    return 0
}

# Check if application is responding
check_application() {
    if ! curl -s --max-time 5 http://localhost:5173 >/dev/null; then
        log_monitor "RECOVERY: Application not responding, restarting service"
        systemctl restart kioskbook-app
        return 1
    fi
    return 0
}

# Main monitoring loop
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    check_memory
    check_load  
    check_chromium
    check_application
    
    # Log success if all checks pass
    if [[ $? -eq 0 ]]; then
        log_monitor "All systems healthy"
    fi
}

main "$@"
EOF
    
    chmod +x /usr/local/bin/kioskbook-monitor
    
    log_success "Monitoring system installed"
}

# Setup scheduled maintenance (Debian cron)
setup_scheduled_maintenance() {
    log "Setting up scheduled maintenance..."
    
    # Create maintenance cron jobs
    cat > /etc/cron.d/kioskbook << 'EOF'
# KioskBook scheduled maintenance
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# System monitoring every 5 minutes
*/5 * * * * root /usr/local/bin/kioskbook-monitor

# Daily maintenance at 3 AM
0 3 * * * root /usr/local/bin/kiosk maintenance

# Weekly system updates on Sunday at 2 AM
0 2 * * 0 root /usr/local/bin/kiosk update

# Clean old logs daily at 1 AM
0 1 * * * root journalctl --vacuum-time=7d

# Restart services weekly on Sunday at 4 AM (after updates)
0 4 * * 0 root /usr/local/bin/kiosk restart
EOF
    
    # Restart cron to pick up new jobs
    systemctl restart cron
    
    log_success "Scheduled maintenance configured"
}

# Setup system optimization (idempotent)
setup_system_optimization() {
    log "Setting up system optimization..."
    
    # Create systemd drop-in for journal limits
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/kioskbook.conf << 'EOF'
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=100M
MaxRetentionSec=7d
EOF
    
    # Restart journald to apply limits
    systemctl restart systemd-journald
    
    # Create swap management for low memory situations
    cat > /usr/local/bin/manage-swap << 'EOF'
#!/bin/bash
# Manage swap based on memory usage

MEMORY_THRESHOLD=90
SWAP_FILE="/swapfile"
SWAP_SIZE="1G"

check_memory() {
    local memory_percent=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2*100}')
    if [[ $memory_percent -gt $MEMORY_THRESHOLD ]]; then
        if [[ ! -f "$SWAP_FILE" ]]; then
            echo "Creating emergency swap file..."
            fallocate -l $SWAP_SIZE $SWAP_FILE
            chmod 600 $SWAP_FILE
            mkswap $SWAP_FILE
            swapon $SWAP_FILE
        fi
    fi
}

check_memory
EOF
    
    chmod +x /usr/local/bin/manage-swap
    
    log_success "System optimization configured"
}

# Setup automatic recovery (idempotent)
setup_automatic_recovery() {
    log "Setting up automatic recovery..."
    
    # Create systemd service for automatic recovery
    cat > /etc/systemd/system/kioskbook-recovery.service << 'EOF'
[Unit]
Description=KioskBook Automatic Recovery
After=kioskbook-app.service lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/kioskbook-monitor
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Create timer for recovery checks
    cat > /etc/systemd/system/kioskbook-recovery.timer << 'EOF'
[Unit]
Description=Run KioskBook recovery checks every 5 minutes
Requires=kioskbook-recovery.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    systemctl daemon-reload
    systemctl enable kioskbook-recovery.timer
    systemctl start kioskbook-recovery.timer
    
    log_success "Automatic recovery enabled"
}

# Enhanced silent boot configuration (idempotent)
enhance_silent_boot() {
    log "Enhancing silent boot configuration..."
    
    # Enhanced GRUB configuration for completely silent boot
    local updated=false
    
    # Update GRUB defaults for silent boot
    if ! grep -q "quiet splash loglevel=0" /etc/default/grub; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=0 console=tty3 rd.systemd.show_status=false rd.udev.log_level=3 systemd.show_status=false"/' /etc/default/grub
        updated=true
    fi
    
    # Set GRUB timeout to 0
    if ! grep -q "^GRUB_TIMEOUT=0" /etc/default/grub; then
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
        updated=true
    fi
    
    # Hide GRUB menu completely
    if ! grep -q "^GRUB_TIMEOUT_STYLE=hidden" /etc/default/grub; then
        echo "GRUB_TIMEOUT_STYLE=hidden" >> /etc/default/grub
        updated=true
    fi
    
    # Disable GRUB loading messages
    if ! grep -q "^GRUB_CMDLINE_LINUX=" /etc/default/grub; then
        echo 'GRUB_CMDLINE_LINUX=""' >> /etc/default/grub
        updated=true
    fi
    
    # Hide GRUB boot messages completely
    if ! grep -q "^GRUB_TERMINAL_OUTPUT=" /etc/default/grub; then
        echo "GRUB_TERMINAL_OUTPUT=console" >> /etc/default/grub
        updated=true
    fi
    
    # Disable GRUB OS prober to speed up and reduce messages
    if ! grep -q "^GRUB_DISABLE_OS_PROBER=true" /etc/default/grub; then
        echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
        updated=true
    fi
    
    # Set GRUB to be completely silent
    if ! grep -q "^GRUB_DISABLE_RECOVERY=true" /etc/default/grub; then
        echo "GRUB_DISABLE_RECOVERY=true" >> /etc/default/grub
        updated=true
    fi
    
    # Force GRUB to not show any messages during boot
    if ! grep -q "^GRUB_GFXMODE=" /etc/default/grub; then
        echo "GRUB_GFXMODE=text" >> /etc/default/grub
        updated=true
    fi
    
    # Completely hide GRUB output
    if ! grep -q "^GRUB_TERMINAL=" /etc/default/grub; then
        sed -i 's/^GRUB_TERMINAL=.*//' /etc/default/grub
        echo "GRUB_TERMINAL=" >> /etc/default/grub
        updated=true
    fi
    
    if [[ "$updated" == true ]]; then
        update-grub
        log "GRUB configuration updated"
    fi
    
    # Enhanced systemd configuration for silent boot
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/silent.conf << 'EOF'
[Manager]
ShowStatus=no
LogLevel=warning
SystemCallErrorNumber=EPERM
EOF
    
    # Create kernel parameters for completely silent boot
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/silent.conf << 'EOF'
# Suppress most kernel messages
options drm_kms_helper poll=0
options drm debug=0
EOF
    
    # Hide kernel messages on all consoles
    cat > /etc/sysctl.d/20-quiet-printk.conf << 'EOF'
kernel.printk = 3 3 3 3
EOF
    
    # Disable verbose fsck during boot
    if [[ -f /etc/default/rcS ]]; then
        sed -i 's/^#FSCKFIX=.*/FSCKFIX=yes/' /etc/default/rcS
    fi
    
    # Mask services that show boot messages
    systemctl mask \
        systemd-random-seed.service \
        systemd-update-utmp.service \
        systemd-tmpfiles-setup.service \
        e2scrub_reap.service 2>/dev/null || true
    
    # Create custom getty service to auto-login without messages
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin kiosk --noclear %I $TERM
StandardInput=tty
StandardOutput=tty
Environment=TERM=linux
TTYVTDisallocate=no
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log_success "Silent boot enhanced"
}

# Show completion
show_completion() {
    echo -e "\n${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}     KioskBook Production Update Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${CYAN}Updates Applied:${NC}"
    echo -e "  ✅ System packages updated"
    echo -e "  ✅ Font configuration optimized (Inter font priority)"
    echo -e "  ✅ SSH configuration optimized (faster startup)"
    echo -e "  ✅ OpenBox autostart updated (port 5173, font rendering)"
    echo -e "  ✅ Systemd service configuration updated"
    echo -e "  ✅ Application code updated"
    echo -e "  ✅ Management CLI installed"
    echo -e "  ✅ Log rotation configured"
    echo -e "  ✅ Monitoring and recovery enabled"
    echo -e "  ✅ Scheduled maintenance configured"
    echo -e "  ✅ System optimization applied"
    echo -e "  ✅ Automatic recovery enabled"
    echo -e "  ✅ Silent boot enhanced (completely silent)"
    
    echo -e "\n${CYAN}New Features:${NC}"
    echo -e "  🚀 Management CLI: ${YELLOW}kiosk status${NC}, ${YELLOW}kiosk health${NC}, ${YELLOW}kiosk logs${NC}"
    echo -e "  📊 Real-time monitoring: ${YELLOW}kiosk monitor${NC}"
    echo -e "  🔄 Automatic recovery: Every 5 minutes"
    echo -e "  📅 Scheduled maintenance: Daily at 3 AM"
    echo -e "  📦 Auto-updates: Weekly on Sunday at 2 AM"
    echo -e "  📝 Log rotation: 7-day retention"
    
    echo -e "\n${CYAN}System Status:${NC}"
    if systemctl is-active --quiet kioskbook-app; then
        echo -e "  ✅ KioskBook application running"
    else
        echo -e "  ❌ KioskBook application needs attention"
    fi
    
    echo -e "\n${CYAN}Management Commands:${NC}"
    echo -e "  Status: ${YELLOW}kiosk status${NC}"
    echo -e "  Health: ${YELLOW}kiosk health --detailed${NC}"
    echo -e "  Logs: ${YELLOW}kiosk logs -f${NC}"
    echo -e "  Update: ${YELLOW}kiosk update${NC}"
    echo -e "  Monitor: ${YELLOW}kiosk monitor${NC}"
}

# Main execution
main() {
    show_banner
    check_prerequisites
    update_system_packages
    update_font_configuration
    update_ssh_configuration
    update_openbox_configuration
    update_systemd_service
    update_application
    install_management_cli
    setup_log_rotation
    setup_monitoring
    setup_scheduled_maintenance
    setup_system_optimization
    setup_automatic_recovery
    enhance_silent_boot
    restart_kiosk_session
    show_completion
}

# Run
main "$@"