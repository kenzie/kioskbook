#!/bin/bash
# KioskBook Utilities Module

# Apply system optimizations
apply_optimizations() {
    log_step "Applying System Optimizations"
    
    # Configure timezone
    chroot /mnt/root ln -sf /usr/share/zoneinfo/America/Halifax /etc/localtime
    
    # Configure locale
    echo "LANG=en_US.UTF-8" > /mnt/root/etc/locale.conf
    
    # Optimize kernel parameters
    cat >> /mnt/root/etc/sysctl.conf << EOF
# Kiosk optimizations
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.panic=10
kernel.panic_on_oops=1
EOF
    
    log_info "System optimizations applied"
}

# Create management tools
create_tools() {
    log_step "Creating Management Tools"
    
    # Create kiosk management script
    cat > /mnt/root/usr/local/bin/kiosk << 'EOF'
#!/bin/bash
# KioskBook Management CLI

case "$1" in
    "status")
        echo "=== KioskBook Status ==="
        echo "Services:"
        rc-status | grep -E "(kiosk|tailscale)" | sed 's/^/  /'
        echo
        echo "Resources:"
        echo "  Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
        echo "  Disk: $(df / | tail -1 | awk '{print $5}')"
        echo
        echo "Network:"
        echo "  Tailscale: $(tailscale status --json 2>/dev/null | jq -r '.Self.Online // "Offline"')"
        ;;
    "restart")
        echo "Restarting kiosk services..."
        rc-service kiosk-app restart
        rc-service kiosk-browser restart
        echo "Services restarted"
        ;;
    "update")
        echo "Updating kiosk app..."
        /opt/update-kiosk.sh
        ;;
    "logs")
        case "$2" in
            "app")
                tail -f /var/log/kiosk-app.log
                ;;
            "browser")
                tail -f /var/log/kiosk-browser.log
                ;;
            *)
                echo "Usage: kiosk logs {app|browser}"
                ;;
        esac
        ;;
    *)
        echo "Usage: kiosk {status|restart|update|logs}"
        echo
        echo "Commands:"
        echo "  status   Show system status"
        echo "  restart  Restart kiosk services"
        echo "  update   Update kiosk app"
        echo "  logs     Show service logs"
        ;;
esac
EOF
    
    chmod +x /mnt/root/usr/local/bin/kiosk
    
    log_info "Management tools created"
}
