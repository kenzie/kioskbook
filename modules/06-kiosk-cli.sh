#!/bin/bash
# KioskBook CLI Module

# Setup kiosk CLI
setup_kiosk_cli() {
    log_step "Setting Up Kiosk CLI"
    
    # Create comprehensive kiosk CLI
    cat > /mnt/root/usr/local/bin/kiosk << 'EOF'
#!/bin/bash
# KioskBook Management CLI

case "$1" in
    "status")
        echo "=== KioskBook Status ==="
        echo "Services:"
        rc-status | grep -E "(kiosk|tailscale|auto-update|screensaver|resource-monitor)" | sed 's/^/  /'
        echo
        echo "Resources:"
        echo "  Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
        echo "  Disk: $(df / | tail -1 | awk '{print $5}')"
        echo
        echo "Network:"
        echo "  Tailscale: $(tailscale status --json 2>/dev/null | jq -r '.Self.Online // "Offline"')"
        echo
        echo "Applications:"
        echo "  Kiosk App: $(curl -s --max-time 2 http://localhost:3000 >/dev/null && echo "Running" || echo "Stopped")"
        echo "  Screensaver: $(curl -s --max-time 2 http://localhost:3001 >/dev/null && echo "Running" || echo "Stopped")"
        ;;
    "restart")
        echo "Restarting kiosk services..."
        rc-service kiosk-app restart
        sleep 3
        rc-service kiosk-browser restart
        echo "Services restarted"
        ;;
    "update")
        echo "Updating kiosk app..."
        /opt/update-kiosk.sh
        ;;
    "screensaver")
        case "$2" in
            "on")
                /opt/screensaver-manual.sh on
                ;;
            "off")
                /opt/screensaver-manual.sh off
                ;;
            *)
                echo "Usage: kiosk screensaver {on|off}"
                ;;
        esac
        ;;
    "logs")
        case "$2" in
            "app")
                tail -f /var/log/kiosk-app.log
                ;;
            "browser")
                tail -f /var/log/kiosk-browser.log
                ;;
            "update")
                tail -f /var/log/auto-update.log
                ;;
            "resource")
                tail -f /var/log/resource-manager.log
                ;;
            "recovery")
                tail -f /var/log/recovery.log
                ;;
            *)
                echo "Usage: kiosk logs {app|browser|update|resource|recovery}"
                ;;
        esac
        ;;
    "health")
        echo "Running health check..."
        /opt/kiosk-health-check.sh
        ;;
    "config")
        echo "=== KioskBook Configuration ==="
        echo "Hostname: $(hostname)"
        echo "GitHub Repo: $(cd /opt/kiosk-app && git remote get-url origin 2>/dev/null || echo 'Not configured')"
        echo "Tailscale Status: $(tailscale status --json 2>/dev/null | jq -r '.Self.Online // "Offline"')"
        echo "Current Time: $(date)"
        echo "Uptime: $(uptime)"
        ;;
    "version")
        echo "KioskBook v1.0.0"
        echo "Alpine Linux: $(cat /etc/alpine_release)"
        echo "Kernel: $(uname -r)"
        echo "Node.js: $(node --version 2>/dev/null || echo 'Not installed')"
        echo "Chromium: $(chromium-browser --version 2>/dev/null || echo 'Not installed')"
        ;;
    "recovery")
        case "$2" in
            "status")
                /opt/recovery-manager.sh status
                ;;
            "reset")
                /opt/recovery-manager.sh reset
                ;;
            "trigger")
                /opt/recovery-manager.sh trigger
                ;;
            "test")
                /opt/recovery-manager.sh test
                ;;
            *)
                echo "Usage: kiosk recovery {status|reset|trigger|test}"
                ;;
        esac
        ;;
    "recovery-status")
        /opt/recovery-manager.sh status
        ;;
    "recovery-reset")
        /opt/recovery-manager.sh reset
        ;;
    "recovery-trigger")
        /opt/recovery-manager.sh trigger
        ;;
    "recovery-test")
        /opt/recovery-manager.sh test
        ;;
    *)
        echo "Usage: kiosk {status|restart|update|screensaver|logs|health|config|version|recovery}"
        echo
        echo "Commands:"
        echo "  status      Show system status"
        echo "  restart     Restart kiosk services"
        echo "  update      Update kiosk app"
        echo "  screensaver Control screensaver (on/off)"
        echo "  logs        Show service logs"
        echo "  health      Run health check"
        echo "  config      Show configuration"
        echo "  version     Show version information"
        echo "  recovery    Recovery system management"
        echo "  recovery-status   Show recovery system status"
        echo "  recovery-reset    Reset recovery level"
        echo "  recovery-trigger  Trigger recovery manually"
        echo "  recovery-test     Test recovery system"
        ;;
esac
EOF
    
    chmod +x /mnt/root/usr/local/bin/kiosk
    
    # Install jq for JSON parsing if not already installed
    chroot /mnt/root apk add jq
    
    log_info "Kiosk CLI installed at /usr/local/bin/kiosk"
}
