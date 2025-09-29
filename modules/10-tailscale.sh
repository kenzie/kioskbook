#!/bin/bash
# KioskBook Tailscale Module

# Setup Tailscale
setup_tailscale() {
    log_step "Setting Up Tailscale"
    
    # Install Tailscale
    chroot /mnt/root curl -fsSL https://tailscale.com/install.sh | sh
    
    # Configure Tailscale to start on boot
    chroot /mnt/root rc-update add tailscaled default
    
    # Create Tailscale configuration script
    cat > /mnt/root/etc/local.d/tailscale.start << EOF
#!/bin/sh
# Configure Tailscale on first boot
if [ ! -f /var/lib/tailscale/tailscaled.state ]; then
    tailscale up --authkey=$TAILSCALE_KEY --accept-routes --accept-dns=false
fi
EOF
    
    chmod +x /mnt/root/etc/local.d/tailscale.start
    
    log_info "Tailscale configured"
}
