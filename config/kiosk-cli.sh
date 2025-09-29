#!/bin/bash
# KioskBook Management CLI

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
    echo
}

# Show system status
show_status() {
    echo -e "${CYAN}=== KioskBook System Status ===${NC}"
    echo
    
    # Service status
    echo -e "${BLUE}Services:${NC}"
    rc-service kiosk-app status
    rc-service kiosk-browser status
    rc-service tailscaled status
    rc-service auto-update status
    rc-service screensaver status
    echo
    
    # App status
    echo -e "${BLUE}App Status:${NC}"
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Kiosk app is running${NC}"
    else
        echo -e "${RED}✗ Kiosk app is not responding${NC}"
    fi
    echo
    
    # Browser status
    echo -e "${BLUE}Browser Status:${NC}"
    if pgrep -f "chromium-browser.*kiosk" >/dev/null; then
        echo -e "${GREEN}✓ Browser is running${NC}"
    else
        echo -e "${RED}✗ Browser is not running${NC}"
    fi
    echo
    
    # Tailscale status
    echo -e "${BLUE}Tailscale Status:${NC}"
    if command -v tailscale >/dev/null 2>&1; then
        tailscale status
    else
        echo -e "${RED}✗ Tailscale not available${NC}"
    fi
}

# Restart services
restart_services() {
    echo -e "${YELLOW}Restarting kiosk services...${NC}"
    
    rc-service kiosk-app restart
    rc-service kiosk-browser restart
    
    echo -e "${GREEN}Services restarted${NC}"
}

# Update system
update_system() {
    echo -e "${YELLOW}Updating system...${NC}"
    
    # Run auto-update
    /opt/auto-update.sh
    
    echo -e "${GREEN}System updated${NC}"
}

# Control screensaver
control_screensaver() {
    case "$1" in
        "on")
            echo -e "${YELLOW}Starting screensaver...${NC}"
            rc-service screensaver start
            ;;
        "off")
            echo -e "${YELLOW}Stopping screensaver...${NC}"
            rc-service screensaver stop
            ;;
        "status")
            rc-service screensaver status
            ;;
        *)
            echo "Usage: kiosk screensaver {on|off|status}"
            ;;
    esac
}

# View logs
view_logs() {
    case "$1" in
        "app")
            tail -f /var/log/kiosk-app.log
            ;;
        "browser")
            tail -f /var/log/kiosk-browser.log
            ;;
        "health")
            tail -f /var/log/kiosk-health.log
            ;;
        "update")
            tail -f /var/log/auto-update.log
            ;;
        "screensaver")
            tail -f /var/log/screensaver.log
            ;;
        *)
            echo "Usage: kiosk logs {app|browser|health|update|screensaver}"
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
    echo "OS: $(cat /etc/alpine_release)"
    echo "Kernel: $(uname -r)"
    echo
    
    echo -e "${BLUE}Network:${NC}"
    ip addr show | grep "inet " | grep -v "127.0.0.1"
    echo
    
    echo -e "${BLUE}Services:${NC}"
    rc-status
}

# Show version
show_version() {
    echo -e "${CYAN}=== KioskBook Version ===${NC}"
    echo "KioskBook v0.0.1"
    echo "Professional Kiosk Deployment Platform"
    echo "Alpine Linux + Tailscale Ready"
    echo "Built: $(date)"
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
        *)
            show_usage
            ;;
    esac
}

main "$@"
