#!/bin/bash
#
# Module: 20-network.sh
# Description: Network configuration, SSH optimization, and Tailscale VPN
#

set -euo pipefail

# Get script directory for accessing configs
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

module_name="Network & SSH"

log_module "$module_name" "Starting network configuration..."

# Install and configure UFW firewall
log_module "$module_name" "Installing UFW firewall..."
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw

log_module "$module_name" "Configuring UFW firewall..."
# Set default policies
ufw --force default deny incoming
ufw --force default allow outgoing

# Allow SSH
ufw allow 22/tcp comment 'SSH'

# Allow Tailscale interface (if it exists)
if ip link show tailscale0 &>/dev/null; then
    ufw allow in on tailscale0 comment 'Tailscale VPN'
fi

# Enable firewall
ufw --force enable
log_module "$module_name" "UFW firewall configured and enabled"

# Install and configure fail2ban
log_module "$module_name" "Installing fail2ban..."
DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban

# Enable and start fail2ban
systemctl enable fail2ban
systemctl start fail2ban
log_module "$module_name" "fail2ban configured and started"

# Optimize SSH configuration
log_module "$module_name" "Optimizing SSH configuration..."
ssh_config="/etc/ssh/sshd_config"
updated=false

# Add UseDNS no if not present
if ! grep -q "^UseDNS no" "$ssh_config"; then
    echo "UseDNS no" >> "$ssh_config"
    updated=true
    log_module "$module_name" "Added UseDNS no"
fi

# Add GSSAPIAuthentication no if not present
if ! grep -q "^GSSAPIAuthentication no" "$ssh_config"; then
    echo "GSSAPIAuthentication no" >> "$ssh_config"
    updated=true
    log_module "$module_name" "Added GSSAPIAuthentication no"
fi

# Disable root login
if ! grep -q "^PermitRootLogin no" "$ssh_config"; then
    # If PermitRootLogin exists (commented or not), replace it
    if grep -q "^#\?PermitRootLogin" "$ssh_config"; then
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$ssh_config"
    else
        # Otherwise append it
        echo "PermitRootLogin no" >> "$ssh_config"
    fi
    updated=true
    log_module "$module_name" "Disabled root login"
fi

# Only allow kiosk user
if ! grep -q "^AllowUsers kiosk" "$ssh_config"; then
    echo "AllowUsers kiosk" >> "$ssh_config"
    updated=true
    log_module "$module_name" "Restricted SSH access to kiosk user"
fi

# Remove duplicate lines at end of file (from previous runs)
# Keep only the first occurrence of each security setting
if grep -c "^PermitRootLogin no" "$ssh_config" | grep -q "^[2-9]"; then
    # Multiple PermitRootLogin lines exist, remove duplicates
    # Keep the first occurrence (line 33 area), remove ones at end
    sed -i '/^PermitRootLogin no/!b; :a; n; /^PermitRootLogin no/d; ba' "$ssh_config"
    updated=true
    log_module "$module_name" "Removed duplicate PermitRootLogin entries"
fi

# Pre-generate SSH host keys if missing
if [[ ! -f /etc/ssh/ssh_host_rsa_key ]]; then
    ssh-keygen -A
    updated=true
    log_module "$module_name" "Generated SSH host keys"
fi

if [[ "$updated" == true ]]; then
    systemctl restart ssh
    log_module "$module_name" "SSH configuration updated and restarted"
fi

# Install Tailscale if auth key provided
if [[ -n "${TAILSCALE_KEY:-}" ]]; then
    log_module "$module_name" "Installing Tailscale VPN..."

    # Add Tailscale repository
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

    # Install Tailscale
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale

    # Configure Tailscale
    tailscale up --authkey="$TAILSCALE_KEY" --ssh --hostname="kioskbook-$(hostname)"

    log_module "$module_name" "Tailscale configured"
else
    log_module "$module_name" "Skipping Tailscale (no auth key provided)"
fi

log_module_success "$module_name" "Network configuration complete"
