#!/bin/bash
#
# KioskBook Module: Kiosk CLI Management Tool
#
# Installs the kiosk management CLI for system administration.
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
CLI_SCRIPT="/usr/local/bin/kiosk"

log_info() {
    echo -e "${GREEN}[CLI]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[CLI]${NC} $1"
}

log_error() {
    echo -e "${RED}[CLI]${NC} $1"
    exit 1
}

# Create kiosk CLI script
create_cli_script() {
    log_info "Creating kiosk CLI management tool..."
    
    # Use config version if available, otherwise create enhanced version
    if [ -f "$KIOSKBOOK_DIR/config/kiosk-cli.sh" ]; then
        cp "$KIOSKBOOK_DIR/config/kiosk-cli.sh" "$CLI_SCRIPT"
        log_info "Using kiosk CLI from config"
    else
        # Create enhanced kiosk CLI
        cat > "$CLI_SCRIPT" << 'EOF'
#!/bin/bash
# KioskBook Enhanced Management CLI

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to show usage
show_usage() {
    echo "KioskBook Management CLI"
    echo "Usage: kiosk <command> [options]"
    echo
    echo "Commands:"
    echo "  status     - Show system status"
    echo "  restart    - Restart kiosk services"
    echo "  update     - Update system and app"
    echo "  screensaver - Control screensaver"
    echo "  logs       - View system logs"
    echo "  health     - Check system health"
    echo "  config     - Show configuration"
    echo "  version    - Show version info"
    echo "  module     - Run individual modules"
    echo
}

# Show system status
show_status() {
    echo -e "${CYAN}=== KioskBook System Status ===${NC}"
    echo
    
    # Service status
    echo -e "${BLUE}Services:${NC}"
    systemctl is-active --quiet kiosk-app.service && echo -e "  ${GREEN}✓${NC} kiosk-app.service" || echo -e "  ${RED}✗${NC} kiosk-app.service"
    systemctl is-active --quiet kiosk-browser.service && echo -e "  ${GREEN}✓${NC} kiosk-browser.service" || echo -e "  ${RED}✗${NC} kiosk-browser.service"
    systemctl is-active --quiet tailscaled.service && echo -e "  ${GREEN}✓${NC} tailscaled.service" || echo -e "  ${RED}✗${NC} tailscaled.service"
    systemctl is-active --quiet auto-update.service && echo -e "  ${GREEN}✓${NC} auto-update.service" || echo -e "  ${RED}✗${NC} auto-update.service"
    systemctl is-active --quiet screensaver.service && echo -e "  ${GREEN}✓${NC} screensaver.service" || echo -e "  ${RED}✗${NC} screensaver.service"
    systemctl is-active --quiet kiosk-health.service && echo -e "  ${GREEN}✓${NC} kiosk-health.service" || echo -e "  ${RED}✗${NC} kiosk-health.service"
    echo
    
    # App status
    echo -e "${BLUE}App Status:${NC}"
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Kiosk app is running${NC}"
    else
        echo -e "  ${RED}✗ Kiosk app is not responding${NC}"
    fi
    echo
    
    # Browser status
    echo -e "${BLUE}Browser Status:${NC}"
    if pgrep -f "chromium.*kiosk" >/dev/null; then
        echo -e "  ${GREEN}✓ Browser is running${NC}"
    else
        echo -e "  ${RED}✗ Browser is not running${NC}"
    fi
    echo
    
    # Tailscale status
    echo -e "${BLUE}Tailscale Status:${NC}"
    if command -v tailscale >/dev/null 2>&1; then
        tailscale status
    else
        echo -e "  ${RED}✗ Tailscale not available${NC}"
    fi
    echo
    
    # Health status
    echo -e "${BLUE}Health Status:${NC}"
    if [ -f "/var/run/kiosk-health.status" ]; then
        status=$(cat /var/run/kiosk-health.status)
        if [ "$status" = "healthy" ]; then
            echo -e "  ${GREEN}✓ System is healthy${NC}"
        else
            echo -e "  ${RED}✗ System is unhealthy${NC}"
        fi
    else
        echo -e "  ${YELLOW}? Health status unknown${NC}"
    fi
}

# Restart services
restart_services() {
    echo -e "${YELLOW}Restarting kiosk services...${NC}"
    
    systemctl restart kiosk-app.service
    systemctl restart kiosk-browser.service
    
    echo -e "${GREEN}Services restarted${NC}"
}

# Update system
update_system() {
    echo -e "${YELLOW}Updating system...${NC}"
    
    # Run auto-update
    systemctl start auto-update.service
    
    echo -e "${GREEN}System update initiated${NC}"
}

# Control screensaver
control_screensaver() {
    case "$1" in
        "on")
            echo -e "${YELLOW}Starting screensaver...${NC}"
            /opt/screensaver-control.sh start
            ;;
        "off")
            echo -e "${YELLOW}Stopping screensaver...${NC}"
            /opt/screensaver-control.sh stop
            ;;
        "status")
            /opt/screensaver-control.sh status
            ;;
        "toggle")
            /opt/screensaver-control.sh toggle
            ;;
        *)
            echo "Usage: kiosk screensaver {on|off|status|toggle}"
            ;;
    esac
}

# View logs
view_logs() {
    case "$1" in
        "app")
            journalctl -u kiosk-app -f
            ;;
        "browser")
            journalctl -u kiosk-browser -f
            ;;
        "health")
            journalctl -u kiosk-health -f
            ;;
        "update")
            journalctl -u auto-update -f
            ;;
        "screensaver")
            journalctl -u screensaver -f
            ;;
        "system")
            journalctl -f
            ;;
        *)
            echo "Usage: kiosk logs {app|browser|health|update|screensaver|system}"
            ;;
    esac
}

# Check health
check_health() {
    echo -e "${CYAN}=== System Health Check ===${NC}"
    
    # Run health check
    /opt/kiosk-health-check.sh
    
    # Show health status
    if [ -f "/var/run/kiosk-health.status" ]; then
        status=$(cat /var/run/kiosk-health.status)
        if [ "$status" = "healthy" ]; then
            echo -e "${GREEN}✓ System is healthy${NC}"
        else
            echo -e "${RED}✗ System is unhealthy${NC}"
        fi
    else
        echo -e "${YELLOW}? Health status unknown${NC}"
    fi
}

# Show configuration
show_config() {
    echo -e "${CYAN}=== KioskBook Configuration ===${NC}"
    echo
    
    echo -e "${BLUE}System Info:${NC}"
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p)"
    echo
    
    echo -e "${BLUE}Network:${NC}"
    ip addr show | grep "inet " | grep -v "127.0.0.1"
    echo
    
    echo -e "${BLUE}Services:${NC}"
    systemctl list-units --type=service --state=active | grep kiosk
    echo
    
    echo -e "${BLUE}Boot Time:${NC}"
    systemd-analyze time 2>/dev/null | grep "Startup finished in" || echo "Unknown"
}

# Show version
show_version() {
    echo -e "${CYAN}=== KioskBook Version ===${NC}"
    echo "KioskBook v0.1.0"
    echo "Modular Kiosk Deployment Platform"
    echo "Debian Linux + Tailscale Ready"
    echo "Built: $(date)"
    echo
    
    if [ -d "/opt/kioskbook" ]; then
        cd /opt/kioskbook
        if git rev-parse --git-dir > /dev/null 2>&1; then
            echo "Git Commit: $(git rev-parse --short HEAD)"
            echo "Git Branch: $(git branch --show-current)"
        fi
    fi
}

# Run module
run_module() {
    if [ -z "$1" ]; then
        echo "Usage: kiosk module <module-name> [args...]"
        echo "Available modules:"
        if [ -d "/opt/kioskbook/modules" ]; then
            ls /opt/kioskbook/modules/*.sh | sed 's/.*\///' | sed 's/\.sh$//' | sort
        fi
        return 1
    fi
    
    if [ -f "/opt/kioskbook/run-module.sh" ]; then
        /opt/kioskbook/run-module.sh "$@"
    else
        echo "Module runner not found at /opt/kioskbook/run-module.sh"
        return 1
    fi
}

# Main CLI function
main() {
    case "$1" in
        "status")
            show_status
            ;;
        "restart")
            restart_services
            ;;
        "update")
            update_system
            ;;
        "screensaver")
            control_screensaver "$2"
            ;;
        "logs")
            view_logs "$2"
            ;;
        "health")
            check_health
            ;;
        "config")
            show_config
            ;;
        "version")
            show_version
            ;;
        "module")
            shift
            run_module "$@"
            ;;
        *)
            show_usage
            ;;
    esac
}

main "$@"
EOF
        log_info "Created enhanced kiosk CLI"
    fi
    
    chmod +x "$CLI_SCRIPT"
    
    log_info "Kiosk CLI created at $CLI_SCRIPT"
}

# Create CLI man page
create_man_page() {
    log_info "Creating kiosk CLI man page..."
    
    mkdir -p /usr/local/share/man/man1/
    
    cat > /usr/local/share/man/man1/kiosk.1 << 'EOF'
.TH KIOSK 1 "KioskBook Management CLI"
.SH NAME
kiosk \- KioskBook management command line interface
.SH SYNOPSIS
.B kiosk
[\fIcommand\fR] [\fIoptions\fR]
.SH DESCRIPTION
KioskBook management CLI provides commands to manage and monitor
the KioskBook kiosk system.
.SH COMMANDS
.TP
.B status
Show system status including services, app, browser, and health status.
.TP
.B restart
Restart kiosk services (app and browser).
.TP
.B update
Update system and application.
.TP
.B screensaver {on|off|status|toggle}
Control screensaver functionality.
.TP
.B logs {app|browser|health|update|screensaver|system}
View system logs in real-time.
.TP
.B health
Check system health and run diagnostics.
.TP
.B config
Show system configuration and information.
.TP
.B version
Show KioskBook version information.
.TP
.B module <module-name> [args...]
Run individual installation modules.
.SH EXAMPLES
.TP
.B kiosk status
Show current system status
.TP
.B kiosk restart
Restart kiosk services
.TP
.B kiosk logs app
View application logs
.TP
.B kiosk module 10-display-stack
Re-run display stack module
.SH AUTHOR
KioskBook Team
.SH SEE ALSO
systemctl(1), journalctl(1)
EOF
    
    # Update man database
    mandb -q 2>/dev/null || true
    
    log_info "Man page created"
}

# Main function
main() {
    echo -e "${CYAN}=== Kiosk CLI Module ===${NC}"
    
    create_cli_script
    create_man_page
    
    log_info "Kiosk CLI setup complete"
    log_info "Usage: kiosk status"
    log_info "Help: kiosk --help or man kiosk"
}

main "$@"
